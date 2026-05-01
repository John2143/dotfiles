# vllm-proxy — on-demand wakeup proxy for the vllm service.
#
# Sits in front of vllm so that:
#   1. vllm doesn't have to run all the time (it eats ~21 GiB VRAM at idle).
#   2. The first request from a client triggers `systemctl start <vllmUnit>`,
#      waits for vllm's /health to return 200, and then proxies the request.
#   3. After `idleTimeoutSeconds` of inactivity the proxy stops vllm and
#      starts the units in `onIdleStart` (typically ollama), returning the
#      GPU to the default tenant.
#
# Pair with `services.vllm.autoStart = false` and
# `services.vllm.conflictsServices = ["ollama.service"]` so ollama and vllm
# never collide on the GPU.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.vllm-proxy;

  proxyScript = pkgs.writers.writePython3Bin "vllm-proxy" {
    libraries = [pkgs.python3Packages.aiohttp];
    flakeIgnore = ["E501" "W503" "E402"];
  } ''
    import asyncio
    import logging
    import os
    import time
    from aiohttp import ClientSession, ClientTimeout, web

    PORT = int(os.environ["PORT"])
    TARGET = f"http://127.0.0.1:{os.environ['TARGET_PORT']}"
    VLLM_UNIT = os.environ["VLLM_UNIT"]
    COLD_START_TIMEOUT = int(os.environ["COLD_START_TIMEOUT"])
    IDLE_TIMEOUT = int(os.environ["IDLE_TIMEOUT"])
    ON_IDLE_START = [u for u in os.environ.get("ON_IDLE_START", "").split() if u]

    HOP_BY_HOP = {
        "host", "content-length", "connection", "keep-alive",
        "transfer-encoding", "te", "trailer", "proxy-authorization",
        "proxy-authenticate", "upgrade",
    }

    log = logging.getLogger("vllm-proxy")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    state = {"last_request": time.monotonic()}
    start_lock = asyncio.Lock()


    async def systemctl(action: str, unit: str) -> int:
        proc = await asyncio.create_subprocess_exec(
            "systemctl", action, unit,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate()
        if proc.returncode != 0:
            log.warning("systemctl %s %s exited %d: %s",
                        action, unit, proc.returncode, stderr.decode().strip())
        return proc.returncode


    async def is_ready(session: ClientSession) -> bool:
        try:
            async with session.get(f"{TARGET}/health",
                                   timeout=ClientTimeout(total=1)) as r:
                return r.status == 200
        except Exception:
            return False


    async def ensure_ready(session: ClientSession) -> bool:
        if await is_ready(session):
            return True
        async with start_lock:
            if await is_ready(session):
                return True
            log.info("cold-starting %s", VLLM_UNIT)
            await systemctl("start", VLLM_UNIT)
            deadline = time.monotonic() + COLD_START_TIMEOUT
            while time.monotonic() < deadline:
                if await is_ready(session):
                    log.info("vllm ready after %.1fs",
                             COLD_START_TIMEOUT - (deadline - time.monotonic()))
                    return True
                await asyncio.sleep(1)
            log.error("vllm did not become ready within %ds", COLD_START_TIMEOUT)
            return False


    async def handle(request: web.Request) -> web.StreamResponse:
        state["last_request"] = time.monotonic()
        session: ClientSession = request.app["session"]

        if not await ensure_ready(session):
            return web.Response(status=504, text="vllm cold start timed out")

        url = f"{TARGET}{request.rel_url}"
        headers = {k: v for k, v in request.headers.items()
                   if k.lower() not in HOP_BY_HOP}
        body = await request.read() if request.body_exists else None

        try:
            async with session.request(
                request.method, url,
                headers=headers, data=body,
                timeout=ClientTimeout(total=None, sock_read=600),
                allow_redirects=False,
            ) as upstream:
                resp_headers = {k: v for k, v in upstream.headers.items()
                                if k.lower() not in HOP_BY_HOP}
                resp = web.StreamResponse(status=upstream.status,
                                          headers=resp_headers)
                await resp.prepare(request)
                async for chunk in upstream.content.iter_any():
                    await resp.write(chunk)
                await resp.write_eof()
                return resp
        except Exception as e:
            log.exception("upstream error")
            return web.Response(status=502, text=f"upstream error: {e}")


    async def idle_watcher() -> None:
        if IDLE_TIMEOUT <= 0:
            return
        async with ClientSession() as session:
            while True:
                await asyncio.sleep(60)
                idle_for = time.monotonic() - state["last_request"]
                if idle_for < IDLE_TIMEOUT:
                    continue
                if not await is_ready(session):
                    continue
                log.info("idle %.0fs > %ds; stopping %s",
                         idle_for, IDLE_TIMEOUT, VLLM_UNIT)
                await systemctl("stop", VLLM_UNIT)
                for unit in ON_IDLE_START:
                    await systemctl("start", unit)
                state["last_request"] = time.monotonic()


    def make_app() -> web.Application:
        app = web.Application(client_max_size=0)

        async def on_startup(app: web.Application) -> None:
            app["session"] = ClientSession()
            app["idle_task"] = asyncio.create_task(idle_watcher())

        async def on_cleanup(app: web.Application) -> None:
            app["idle_task"].cancel()
            await app["session"].close()

        app.on_startup.append(on_startup)
        app.on_cleanup.append(on_cleanup)
        app.router.add_route("*", "/{path:.*}", handle)
        return app


    if __name__ == "__main__":
        web.run_app(make_app(), host="0.0.0.0", port=PORT, access_log=None)
  '';
in {
  options.services.vllm-proxy = {
    enable = lib.mkEnableOption "vllm on-demand wakeup proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "LAN-facing port the proxy listens on.";
    };

    targetPort = lib.mkOption {
      type = lib.types.port;
      default = 8001;
      description = "Local port where vllm itself listens.";
    };

    vllmUnit = lib.mkOption {
      type = lib.types.str;
      default = "podman-vllm.service";
      description = "Systemd unit to start when a request arrives and stop when idle.";
    };

    coldStartTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Maximum time to wait for vllm /health after triggering start. Returns 504 on timeout.";
    };

    idleTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Stop vllm after this many seconds of no requests. 0 disables idle shutdown.";
    };

    onIdleStart = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Units to start when idle-stopping vllm (e.g. ollama).";
      example = ["ollama.service"];
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open the firewall for the proxy port.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    systemd.services.vllm-proxy = {
      description = "On-demand wakeup proxy in front of vllm";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      environment = {
        PORT = toString cfg.port;
        TARGET_PORT = toString cfg.targetPort;
        VLLM_UNIT = cfg.vllmUnit;
        COLD_START_TIMEOUT = toString cfg.coldStartTimeoutSeconds;
        IDLE_TIMEOUT = toString cfg.idleTimeoutSeconds;
        ON_IDLE_START = lib.concatStringsSep " " cfg.onIdleStart;
      };

      serviceConfig = {
        ExecStart = "${proxyScript}/bin/vllm-proxy";
        Restart = "on-failure";
        RestartSec = 2;

        # Needs root to call `systemctl start/stop` on system units.
        User = "root";

        # Hardening: still root, but constrained.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = false; # Python JIT-y bits need this off
        SystemCallArchitectures = "native";
      };
    };
  };
}
