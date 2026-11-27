# ── frigate-genai seat gate ─────────────────────────────────────────
# The frigate-genai dispatcher (argo/workloads/frigate-genai-dispatcher)
# describes recorded Frigate scenes with the local Ollama models while nobody is
# at this workstation, and yields the moment somebody sits down. It cannot see
# the seat itself; it reads four series from Mimir, fed by the node_exporter
# textfile this module writes:
#
#   frigate_genai_gate_open         1 when the seat has been idle >= 180 s
#   frigate_genai_free_vram_mb      free VRAM on the Ollama card, MiB
#   frigate_genai_loaded_models     models resident in Ollama
#   frigate_genai_gate_idle_seconds seconds since the last seat activity
#
# Why Hyprland IPC and not logind: on this host seat0 reports IdleHint=yes
# ("no session attached to the seat") while the Hyprland session reports no for
# as long as it is logged in, so logind's idea of idle is useless here. The
# sampler instead diffs workspace id+name, cursor position and the client count
# every 60 s; hyprctl costs ~9 ms per call.
#
# A sample that cannot be taken (no Hyprland, stale socket, hyprctl error) is
# *not* evidence of an idle seat: the gate is written 0 and the idle clock is
# restarted, so a broken sampler can only ever close the gate.
#
# Manual override: ~/.local/state/frigate-genai/seated containing 1 or 0
# overrides the computed gate while the file is younger than 30 minutes.
#   echo 1 > ~/.local/state/frigate-genai/seated   # run the batch now
#   echo 0 > ~/.local/state/frigate-genai/seated   # keep it off
#
# The alert below is the only way a dead sampler is visible at all: a stale
# .prom file makes every drain read the gate as closed, which is silent.
{pkgs, ...}: let
  # stdlib only: urllib, json, subprocess, pathlib, tempfile.
  pythonEnv = pkgs.python3.withPackages (ps: []);

  promDir = "/var/lib/node_exporter/textfile";
  promFile = "${promDir}/frigate_genai_gate.prom";
  alertStateDir = "/var/lib/frigate-genai-gate";

  gateScript = pkgs.writeScript "frigate-genai-gate" ''
    #!${pythonEnv}/bin/python3
    """Publish the frigate-genai seat gate; see nixos/modules/frigate-genai-seated.nix."""

    import json
    import os
    import pathlib
    import subprocess
    import sys
    import tempfile
    import time
    import urllib.request

    HYPRCTL = "${pkgs.hyprland}/bin/hyprctl"
    PROM_DIR = pathlib.Path("${promDir}")
    PROM_PATH = pathlib.Path("${promFile}")
    VRAM_DIR = pathlib.Path("/sys/class/drm/card1/device")
    OLLAMA_PS_URL = "http://127.0.0.1:11434/api/ps"
    IDLE_OPEN_SECONDS = 180
    OVERRIDE_MAX_AGE_SECONDS = 30 * 60
    HYPRCTL_TIMEOUT = 3
    OLLAMA_TIMEOUT = 2


    def log(message):
        print("frigate-genai-gate: " + message, flush=True)


    def warn(message):
        print("frigate-genai-gate: " + message, file=sys.stderr, flush=True)


    class HyprUnavailable(Exception):
        pass


    def state_root():
        base = os.environ.get("XDG_STATE_HOME") or os.path.join(
            os.path.expanduser("~"), ".local", "state"
        )
        root = pathlib.Path(base) / "frigate-genai"
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        return root


    def read_idle_state(path):
        try:
            data = json.loads(path.read_text())
            return {"sig": data["sig"], "since": int(data["since"])}
        except (OSError, ValueError, KeyError, TypeError):
            return None


    def write_idle_state(path, sig, since):
        # Losing the state file only means the idle clock restarts next sample,
        # so a write failure is logged rather than raised: the gate itself is
        # still publishable, and a sampler that dies here would publish nothing.
        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".hypr-sig.")
            with os.fdopen(fd, "w") as handle:
                json.dump({"sig": sig, "since": since}, handle)
            os.replace(tmp, path)
        except OSError as err:
            warn("cannot persist idle state to " + str(path) + ": " + str(err))
            if tmp is not None and os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass


    def hypr_instances(runtime_dir):
        """Candidate HYPRLAND_INSTANCE_SIGNATURE values, live one first.

        The user manager's environment carries the current signature; the
        runtime dir also holds directories from earlier Hyprland runs whose
        sockets are dead. Sort the leftovers by directory mtime so the current
        instance is tried early, and let the hyprctl call itself decide: a dead
        socket answers with ECONNREFUSED.
        """
        ordered = []
        current = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if current:
            ordered.append(current)
        hypr_root = pathlib.Path(runtime_dir) / "hypr"

        def mtime(name):
            try:
                return (hypr_root / name).stat().st_mtime
            except OSError:
                return 0.0

        try:
            names = [entry.name for entry in hypr_root.iterdir() if entry.is_dir()]
        except OSError:
            names = []
        for name in sorted(names, key=mtime, reverse=True):
            if name not in ordered:
                ordered.append(name)
        return ordered


    def hypr_json(args, env):
        try:
            proc = subprocess.run(
                [HYPRCTL, "-j"] + args,
                env=env,
                capture_output=True,
                timeout=HYPRCTL_TIMEOUT,
            )
        except (OSError, subprocess.TimeoutExpired) as err:
            raise HyprUnavailable(str(err)) from err
        if proc.returncode != 0:
            raise HyprUnavailable(proc.stderr.decode("utf-8", "replace").strip())
        try:
            return json.loads(proc.stdout.decode("utf-8", "replace"))
        except ValueError as err:
            raise HyprUnavailable("hyprctl " + " ".join(args) + ": " + str(err)) from err


    def seat_signature():
        """One string that changes on any seat activity, or None if unreadable."""
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/" + str(os.getuid())
        error = "no Hyprland instance"
        for instance in hypr_instances(runtime_dir):
            socket_path = pathlib.Path(runtime_dir) / "hypr" / instance / ".socket.sock"
            if not socket_path.exists():
                continue
            env = dict(os.environ)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = instance
            try:
                workspace = hypr_json(["activeworkspace"], env)
                cursor = hypr_json(["cursorpos"], env)
                clients = hypr_json(["clients"], env)
            except HyprUnavailable as err:
                error = str(err)
                continue
            return (
                str(workspace.get("id"))
                + "|" + str(workspace.get("name"))
                + "|" + str(cursor.get("x"))
                + "|" + str(cursor.get("y"))
                + "|" + str(len(clients) if isinstance(clients, list) else -1)
            )
        warn("hyprctl unavailable (" + error + ")")
        return None


    def read_int(path):
        try:
            return int(path.read_text().strip())
        except (OSError, ValueError):
            return 0


    def free_vram_mb():
        # mem_info_vram_* are bytes. 0 on hosts/cards without the attribute, and
        # the dispatcher requires >= 12 GB (>= 21.5 GB for the 26b model), so an
        # unreadable value always reads as "no room".
        total = read_int(VRAM_DIR / "mem_info_vram_total")
        used = read_int(VRAM_DIR / "mem_info_vram_used")
        if total <= 0:
            return 0
        return max(0, total - used) // (1024 * 1024)


    def loaded_models():
        # /api/ps lists what Ollama has resident. Unreachable Ollama counts as 0
        # loaded, exactly like a freshly started daemon; the VRAM sample is what
        # actually gates a 26b call.
        try:
            with urllib.request.urlopen(OLLAMA_PS_URL, timeout=OLLAMA_TIMEOUT) as response:
                payload = json.load(response)
        except Exception as err:
            warn("ollama /api/ps failed: " + str(err))
            return 0
        models = payload.get("models") if isinstance(payload, dict) else None
        return len(models) if isinstance(models, list) else 0


    def override_value(root, now):
        path = root / "seated"
        try:
            raw = path.read_text().strip()
            age = now - path.stat().st_mtime
        except OSError:
            return None
        if raw not in ("0", "1"):
            warn("ignoring manual override " + str(path) + ": expected 0 or 1")
            return None
        if age >= OVERRIDE_MAX_AGE_SECONDS:
            warn("ignoring manual override " + str(path) + ": " + str(int(age)) + "s old")
            return None
        return int(raw)


    def prometheus_text(gate, free_mb, models, idle):
        return "".join([
            "# HELP frigate_genai_gate_open 1 when the workstation seat has been idle long enough for batch LLM work.\n",
            "# TYPE frigate_genai_gate_open gauge\n",
            "frigate_genai_gate_open " + str(gate) + "\n",
            "# HELP frigate_genai_free_vram_mb Free VRAM on the Ollama card in MiB (0 when unknown).\n",
            "# TYPE frigate_genai_free_vram_mb gauge\n",
            "frigate_genai_free_vram_mb " + str(free_mb) + "\n",
            "# HELP frigate_genai_loaded_models Models currently resident in Ollama (0 when unreachable).\n",
            "# TYPE frigate_genai_loaded_models gauge\n",
            "frigate_genai_loaded_models " + str(models) + "\n",
            "# HELP frigate_genai_gate_idle_seconds Seconds since the last change of workspace, cursor or client list.\n",
            "# TYPE frigate_genai_gate_idle_seconds gauge\n",
            "frigate_genai_gate_idle_seconds " + str(idle) + "\n",
        ])


    def publish(text):
        # Same directory + os.replace so node_exporter never reads a half file.
        tmp = None
        try:
            fd, tmp = tempfile.mkstemp(dir=str(PROM_DIR), prefix=".frigate_genai_gate.")
            with os.fdopen(fd, "w") as handle:
                handle.write(text)
            os.chmod(tmp, 0o644)
            os.replace(tmp, PROM_PATH)
        except OSError as err:
            warn("cannot publish " + str(PROM_PATH) + ": " + str(err))
            if tmp is not None and os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
            return False
        return True


    def main():
        now = int(time.time())
        root = state_root()
        idle_path = root / "hypr-sig"
        previous = read_idle_state(idle_path)
        signature = seat_signature()
        if signature is None:
            # Unknown is not idle. Close the gate and restart the clock so a gap
            # in sampling can never accrue towards the 180 s threshold.
            since = now
            write_idle_state(idle_path, previous["sig"] if previous else None, since)
            gate = 0
            idle = 0
        else:
            if previous is not None and previous["sig"] == signature:
                since = min(previous["since"], now)
            else:
                since = now
            write_idle_state(idle_path, signature, since)
            idle = max(0, now - since)
            gate = 1 if idle >= IDLE_OPEN_SECONDS else 0

        forced = override_value(root, now)
        if forced is not None:
            log("manual override seated=" + str(forced))
            gate = forced

        free_mb = free_vram_mb()
        models = loaded_models()
        if not publish(prometheus_text(gate, free_mb, models, idle)):
            return 1
        log(
            "open=" + str(gate)
            + " idle=" + str(idle) + "s"
            + " free_vram_mb=" + str(free_mb)
            + " loaded_models=" + str(models)
        )
        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';

  # The sampler runs in john's user manager, where it can see Hyprland, and a
  # user-run process cannot write into a root-owned 0755 directory. Keep the
  # directory root-owned — root's own textfile writers (nixos.prom, restic.prom)
  # expect that — and make it group-writable instead: john's primary group is
  # `users`, and files it drops are 0644, which node_exporter reads as root.
  # The alert's cooldown state is a private directory and stays john-owned.
  tmpfilesRules = [
    "d ${promDir} 0775 root users -"
    "d ${alertStateDir} 0755 john users -"
  ];
in {
  systemd.tmpfiles.rules = tmpfilesRules;

  systemd.user.services.frigate-genai-gate = {
    description = "Sample the frigate-genai seat gate into the node_exporter textfile";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gateScript}";
      # A hung run would keep the unit active, and OnUnitActiveSec never fires
      # again while it is, so the gate file would go stale silently.
      TimeoutStartSec = "30s";
    };
  };

  systemd.user.timers.frigate-genai-gate = {
    description = "Sample the frigate-genai seat gate every 60 s";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "60s";
      OnUnitActiveSec = "60s";
      AccuracySec = "5s";
    };
  };

  # Gate staleness alert. There is no generic "check an arbitrary condition and
  # push" helper in this repo, so this is the same oneshot + ntfy shape as
  # notify-failure@ in fleet-patching.nix, with a cooldown: a dead sampler would
  # otherwise push every 5 minutes. The dispatcher fails closed on a stale file,
  # which means a dead sampler looks exactly like a busy human — this is the only
  # signal that tells them apart.
  systemd.services.frigate-genai-gate-alert = {
    description = "Alert when frigate-genai's seat gate file stops being refreshed";
    path = [pkgs.bash pkgs.coreutils pkgs.curl];
    serviceConfig = {
      Type = "oneshot";
      User = "john";
      Group = "users";
    };
    script = ''
      set -u
      prom=${promFile}
      state=${alertStateDir}
      limit=300
      cooldown=21600
      now=$(date +%s)
      if [ -e "$prom" ]; then
        age=$(( now - $(stat -c %Y "$prom") ))
      else
        age=$(( limit + 1 ))
      fi
      if [ "$age" -le "$limit" ]; then
        exit 0
      fi
      last=0
      if [ -r "$state/last-alert" ]; then
        last=$(cat "$state/last-alert" 2>/dev/null || echo 0)
        case "$last" in *[!0-9]*|"") last=0 ;; esac
      fi
      if [ $(( now - last )) -lt "$cooldown" ]; then
        echo "gate file is ''${age}s old; already alerted $(( now - last ))s ago"
        exit 0
      fi
      if ! . /run/agenix/ntfy-topic-url; then
        echo "cannot read /run/agenix/ntfy-topic-url" >&2
        exit 1
      fi
      curl -fsS -m 20 \
        -H "Title: frigate-genai gate file stale on office" \
        -H "Priority: high" \
        -H "Tags: rotating_light" \
        -d "frigate_genai_gate.prom is ''${age}s old (limit ''${limit}s): the seat sampler is dead, so every drain reads the gate as closed and nothing gets described. journalctl --user -u frigate-genai-gate" \
        "$NTFY_TOPIC_URL" || {
        # Stamp only after a delivered push: an ntfy outage must not buy six
        # hours of silence, and a failed unit is itself visible in the journal.
        echo "ntfy push failed" >&2
        exit 1
      }
      printf '%s\n' "$now" > "$state/last-alert"
    '';
  };

  systemd.timers.frigate-genai-gate-alert = {
    description = "Check the frigate-genai seat gate file every 5 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "5min";
    };
  };
}
