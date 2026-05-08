{ ... }: {
  programs.fish.interactiveShellInit = ''
    # Tab completion for vast-* commands that take an INSTANCE_ID.
    # Filters by VAST_LABEL (default vllm-deepseek-v4) and status:
    #   running  → vast-bootstrap, vast-fetch-metrics, vast-tunnel, vast-logs, vast-pause
    #   stopped  → vast-unpause
    #   any      → vast-destroy
    complete -c vast-destroy  -f -a '(_vast-complete-ids any)'
    complete -c vast-bootstrap -f -a '(_vast-complete-ids running)'
    complete -c vast-tunnel    -f -a '(_vast-complete-ids running)'
    complete -c vast-logs      -f -a '(_vast-complete-ids running)'
    complete -c vast-pause     -f -a '(_vast-complete-ids running)'
    complete -c vast-fetch-metrics -f -a '(_vast-complete-ids running)'
    complete -c vast-unpause   -f -a '(_vast-complete-ids stopped)'
  '';

  programs.fish.functions = {
    my_claw.body = ''
      # Run Claude Code with inference offloaded to the local DeepSeek V4 Flash
      # behind vast-tunnel. Spawns a per-invocation LiteLLM proxy on a random
      # high port that translates Anthropic /v1/messages → OpenAI /v1/chat/completions
      # against http://localhost:$VAST_LOCAL_PORT/v1, then runs claude pointed at
      # it. Assumes vast-tunnel is up (same convention as omp).
      if not systemctl --user is-active --quiet vast-tunnel.service
        echo "my_claw: vast-tunnel is down. Run: vast-tunnel" >&2
        return 1
      end
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      # Random ephemeral port. TOCTOU collision risk is low across the 16k
      # range; if litellm fails to bind, the readiness poll below catches it.
      set -l port (random 49152 65535)
      set -l log (mktemp -t my_claw.XXXXXX.log)

      echo "my_claw: starting LiteLLM proxy on :$port → localhost:$VAST_LOCAL_PORT (model=$VAST_SERVED_MODEL_NAME, log=$log)"
      uvx --quiet --from 'litellm[proxy]' litellm \
          --model "openai/$VAST_SERVED_MODEL_NAME" \
          --api_base "http://localhost:$VAST_LOCAL_PORT/v1" \
          --port $port >$log 2>&1 &
      set -l proxy_pid $last_pid

      # First invocation downloads litellm[proxy] via uvx (~30s); subsequent
      # runs are warm from ~/.cache/uv. Cap at 120s to cover the cold case.
      set -l ready 0
      for i in (seq 1 240)
        if curl -fsS --max-time 1 "http://localhost:$port/v1/models" >/dev/null 2>&1
          set ready 1
          break
        end
        if not kill -0 $proxy_pid 2>/dev/null
          break
        end
        sleep 0.5
      end
      if test $ready -ne 1
        echo "my_claw: LiteLLM proxy never came up on :$port — see $log" >&2
        kill $proxy_pid 2>/dev/null
        env-cleanup $_pre_vars
        return 1
      end

      set -gx ANTHROPIC_BASE_URL "http://localhost:$port"
      set -gx ANTHROPIC_AUTH_TOKEN dummy
      set -gx ANTHROPIC_MODEL "$VAST_SERVED_MODEL_NAME"
      claude $argv
      set -l rc $status
      kill $proxy_pid 2>/dev/null
      rm -f $log
      env-cleanup $_pre_vars
      return $rc
    '';
    my_claw.description = "Run Claude Code routed through a per-invocation LiteLLM proxy to the local DeepSeek (assumes vast-tunnel is up).";

    # Full workflow + troubleshooting + market context: ../Vast.md
    #
    # Credential model (intentionally lightweight):
    #   - One long-lived secret (rare rotation):
    #       /run/agenix/vast-credentials   env-var format with both
    #                                      VAST_API_KEY and
    #                                      VAST_SSH_PRIVATE_KEY_B64
    #     SSH key gets materialized to /run/user/$UID/vast-ssh-key
    #     (per-user tmpfs, 0600) on first vast-* invocation each session.
    #   - Per-rental host/port: discovered live via the Vast.ai API
    #     (`vastai show instances --label $VAST_LABEL`), no file edits.
    #   - Optional non-secret config: ~/.config/vast/profile (plain
    #     KEY=VALUE file). Copy ~/.config/vast/profile.example to
    #     ~/.config/vast/profile and override any defaults.
    #
    # Quick reference:
    #   Rent      vast-search [query]                 # find offers
    #             vast-create OFFER_ID                # launch with our minimal image
    #   Spinup    vast-bootstrap                      # ~25 min first time (model download)
    #             vast-tunnel                         # localhost:VAST_LOCAL_PORT -> rental
    #             vast-status
    #   Use       omp → vast-vllm/<model>
    #             curl http://localhost:8001/v1/models
    #             vast-logs [N]                       # tail remote vllm.log
    #   Teardown  vast-tunnel-down
    #             vast-destroy INSTANCE_ID
    #
    # Renting a fresh instance just requires `vast-create` — no agenix
    # edit, no nix rebuild. The next `vast-bootstrap` discovers the new
    # host automatically because it's tagged with the same VAST_LABEL.
    _vast-load.body = ''
      # Internal helper: load profile + agenix creds, apply defaults.
      # Sets exported globals VAST_* used by the other vast-* helpers.
      # Does NOT resolve VAST_HOST/VAST_SSH_PORT — call _vast-resolve-instance
      # for that (so callers can target a specific instance by ID when several
      # are rented under the same VAST_LABEL). Caller owns env-cleanup.

      # 1) Optional plain-file profile (non-secret config).
      set -l profile $HOME/.config/vast/profile
      if test -f $profile
        envsource $profile >/dev/null
      end

      # 2) Combined credentials from agenix (VAST_API_KEY + b64 SSH key).
      set -l creds_file /run/agenix/vast-credentials
      if not test -f $creds_file
        echo "Vast.ai credentials not at $creds_file." >&2
        echo "Create via: cd ~/dotfiles && agenix -e secrets/vast-credentials.age" >&2
        echo "Format: VAST_API_KEY=...    VAST_SSH_PRIVATE_KEY_B64=..." >&2
        echo "Then: nh os switch ." >&2
        return 1
      end
      envsource $creds_file >/dev/null
      if test -z "$VAST_SSH_PRIVATE_KEY_B64"
        echo "VAST_SSH_PRIVATE_KEY_B64 missing from $creds_file" >&2
        return 1
      end

      # 3) Materialize SSH key to per-user tmpfs (0600). Persists for the
      # session — auto-wiped on logout when /run/user/$UID tears down.
      # Stable path so the systemd-run-launched tunnel can read it after
      # this fish process exits.
      set -gx VAST_SSH_KEY /run/user/(id -u)/vast-ssh-key
      echo $VAST_SSH_PRIVATE_KEY_B64 | base64 -d > $VAST_SSH_KEY
      chmod 600 $VAST_SSH_KEY

      # 4) Defaults for anything still empty.
      test -n "$VAST_LABEL"; or set -gx VAST_LABEL "vllm-deepseek-v4"
      test -n "$VAST_MODEL"; or set -gx VAST_MODEL "deepseek-ai/DeepSeek-V4-Flash"
      test -n "$VAST_SERVED_MODEL_NAME"; or set -gx VAST_SERVED_MODEL_NAME "deepseek-v4-flash"
      test -n "$VAST_MAX_MODEL_LEN"; or set -gx VAST_MAX_MODEL_LEN "auto"
      test -n "$VAST_GPU_MEM_UTIL"; or set -gx VAST_GPU_MEM_UTIL "auto"
      test -n "$VAST_MAX_NUM_SEQS"; or set -gx VAST_MAX_NUM_SEQS "auto"
      test -n "$VAST_LOCAL_PORT"; or set -gx VAST_LOCAL_PORT "8001"
      test -n "$VAST_VLLM_PORT"; or set -gx VAST_VLLM_PORT "8000"
      test -n "$VAST_SSH_USER"; or set -gx VAST_SSH_USER "root"
      set -q VAST_HF_TOKEN; or set -gx VAST_HF_TOKEN ""
      set -q VAST_TOOL_CALL_PARSER; or set -gx VAST_TOOL_CALL_PARSER ""
      set -q VAST_REASONING_PARSER; or set -gx VAST_REASONING_PARSER ""
      set -q VAST_EXTRA_ARGS; or set -gx VAST_EXTRA_ARGS ""
      set -q VAST_TENSOR_PARALLEL; or set -gx VAST_TENSOR_PARALLEL ""

      # Fish quirk: `set -q VAR; or set -gx VAR ""` returns 1 even when the
      # set succeeds (the empty-list `set` doesn't override the prior `set -q`
      # status), which would leak rc=1 out of this function. Force success.
      return 0
    '';
    _vast-load.description = "Internal: load Vast profile + creds, materialize SSH key, apply defaults.";

    _vast-resolve-instance.body = ''
      # Resolve which Vast.ai instance the caller targets. Sets exported
      # VAST_HOST, VAST_SSH_PORT, and VAST_INSTANCE_ID for ssh / vastai
      # calls that follow.
      #
      # Usage: _vast-resolve-instance [INSTANCE_ID] [STATUS] [NO_FZF]
      #   STATUS = "running" (default) | "stopped" | "any"
      #     - "running":  filter actual_status == "running" (bootstrap, tunnel, logs, pause)
      #     - "stopped":  filter actual_status != "running" (covers stopped/exited/loading; for unpause)
      #     - "any":      no status filter (rare; mostly for diagnostics)
      #   NO_FZF = "1" to skip the interactive picker on multi-candidate
      #            (otherwise fzf is launched if available; falls back to
      #            error-with-listing when fzf is missing).
      #
      # Behavior:
      #   - INSTANCE_ID given → pick that one (must match label + status).
      #   - Else if exactly one matches → pick it.
      #   - Else if 0 candidates → print message + return 1.
      #   - Else (2+):
      #       · Print the candidate list (always — useful as context).
      #       · If NO_FZF=1 or fzf missing → return 1.
      #       · Else launch fzf; ESC/empty selection → return 1.
      #
      # If $VAST_HOST and $VAST_SSH_PORT are already set (e.g. pinned in
      # ~/.config/vast/profile), skip API discovery — but error if the caller
      # also passed an instance ID. VAST_INSTANCE_ID is left unset on the pin
      # path; callers that need it (vast-pause, vast-unpause) must check.

      set -l want_id ""
      if test (count $argv) -gt 0; and test -n "$argv[1]"
        set want_id $argv[1]
      end
      set -l want_status running
      if test (count $argv) -gt 1; and test -n "$argv[2]"
        set want_status $argv[2]
      end
      set -l no_fzf 0
      if test (count $argv) -gt 2; and test "$argv[3]" = "1"
        set no_fzf 1
      end

      if test -n "$VAST_HOST"; and test -n "$VAST_SSH_PORT"
        if test -n "$want_id"
          echo "VAST_HOST/VAST_SSH_PORT pinned in profile; cannot also pass INSTANCE_ID=$want_id." >&2
          echo "Comment out the pin in ~/.config/vast/profile to use the multi-instance picker." >&2
          return 1
        end
        return 0
      end

      if not command -v vastai >/dev/null 2>&1
        echo "vastai CLI not found and VAST_HOST/VAST_SSH_PORT not set in profile." >&2
        echo "Either install the wrapper (rebuild after enabling) or pin host manually." >&2
        return 1
      end

      set -l raw (vastai show instances --raw 2>/dev/null)
      if test -z "$raw"; or test "$raw" = "[]"
        echo "Vast.ai API returned no instances. Run `vast-create OFFER_ID` first." >&2
        return 1
      end

      set -l candidates
      switch $want_status
        case running
          set candidates (echo $raw | jq -c --arg label "$VAST_LABEL" '
            [.[] | select(.label == $label) | select(.actual_status == "running")]
          ')
        case stopped
          set candidates (echo $raw | jq -c --arg label "$VAST_LABEL" '
            [.[] | select(.label == $label) | select(.actual_status != "running")]
          ')
        case any
          set candidates (echo $raw | jq -c --arg label "$VAST_LABEL" '
            [.[] | select(.label == $label)]
          ')
        case '*'
          echo "_vast-resolve-instance: unknown status '$want_status' (expected running|stopped|any)" >&2
          return 2
      end
      set -l count (echo $candidates | jq 'length')

      # Phrase candidate-list errors in the right voice for the chosen status.
      set -l noun "running"
      switch $want_status
        case stopped
          set noun "paused (non-running)"
        case any
          set noun ""
      end

      if test "$count" = "0"
        if test -n "$noun"
          echo "No $noun Vast.ai instance with label '$VAST_LABEL' found." >&2
        else
          echo "No Vast.ai instance with label '$VAST_LABEL' found." >&2
        end
        echo "List with: vast-show" >&2
        return 1
      end

      set -l selected ""
      if test -n "$want_id"
        set selected (echo $candidates | jq -c --arg id "$want_id" '
          map(select((.id | tostring) == $id))[0] // empty
        ')
        if test -z "$selected"
          if test -n "$noun"
            echo "No $noun Vast.ai instance with id=$want_id and label '$VAST_LABEL'." >&2
          else
            echo "No Vast.ai instance with id=$want_id and label '$VAST_LABEL'." >&2
          end
          echo "Candidates:" >&2
          echo $candidates | jq -r '.[] | "  id=\(.id) status=\(.actual_status) gpu=\(.gpu_name)×\(.num_gpus // 1) hourly=$\(.dph_total)"' >&2
          return 1
        end
      else if test "$count" = "1"
        set selected (echo $candidates | jq -c '.[0]')
      else
        if test -n "$noun"
          echo "Multiple $noun Vast.ai instances with label '$VAST_LABEL':" >&2
        else
          echo "Multiple Vast.ai instances with label '$VAST_LABEL':" >&2
        end
        set -l lines (echo $candidates | jq -r '.[] | "id=\(.id) status=\(.actual_status) host=\(.public_ipaddr) ssh_port=\(.ports."22/tcp"[0].HostPort // "?") gpu=\(.gpu_name)×\(.num_gpus // 1) hourly=$\(.dph_total)"')
        for line in $lines
          echo "  $line" >&2
        end

        if test "$no_fzf" = "1"
          echo "Pass an instance ID to disambiguate (omit --no-fzf for an interactive picker)." >&2
          return 1
        end
        if not command -v fzf >/dev/null 2>&1
          echo "Pass an instance ID to disambiguate (install fzf for an interactive picker)." >&2
          return 1
        end

        set -l picked (printf '%s\n' $lines | fzf --prompt "Select Vast instance > " --height 40% --reverse --border --header "$VAST_LABEL ($want_status candidates)")
        if test -z "$picked"
          echo "No instance selected — aborting." >&2
          return 1
        end
        set -l picked_id (string match -r '^id=([0-9]+)' -- $picked)[2]
        if test -z "$picked_id"
          echo "Could not parse selection: $picked" >&2
          return 1
        end
        set selected (echo $candidates | jq -c --arg id "$picked_id" '
          map(select((.id | tostring) == $id))[0]
        ')
      end

      set -gx VAST_INSTANCE_ID (echo $selected | jq -r '.id')
      set -gx VAST_HOST (echo $selected | jq -r '.public_ipaddr // empty')
      set -gx VAST_SSH_PORT (echo $selected | jq -r '.ports."22/tcp"[0].HostPort // empty')
      echo "Targeting Vast.ai instance $VAST_INSTANCE_ID ($VAST_HOST:$VAST_SSH_PORT)" >&2
    '';
    _vast-resolve-instance.description = "Internal: pick a Vast instance by ID or auto-disambiguate (status filter: running|stopped|any). Sets VAST_INSTANCE_ID/VAST_HOST/VAST_SSH_PORT.";

    vast-bootstrap.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l instance_id ""
      set -l force_restart ""
      set -l no_fzf ""
      for arg in $argv
        switch $arg
          case --restart
            set force_restart 1
          case --no-fzf
            set no_fzf 1
          case '*'
            if test -z "$instance_id"
              set instance_id $arg
            end
        end
      end

      if not _vast-resolve-instance $instance_id running $no_fzf
        env-cleanup $_pre_vars
        return 1
      end

      echo "Bootstrapping vLLM on $VAST_SSH_USER@$VAST_HOST:$VAST_SSH_PORT (model: $VAST_MODEL)"
      ssh -i $VAST_SSH_KEY \
          -p $VAST_SSH_PORT \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          $VAST_SSH_USER@$VAST_HOST \
          "MODEL='$VAST_MODEL' SERVED='$VAST_SERVED_MODEL_NAME' VLLM_PORT='$VAST_VLLM_PORT' MAX_LEN='$VAST_MAX_MODEL_LEN' MEM_UTIL='$VAST_GPU_MEM_UTIL' MAX_NUM_SEQS='$VAST_MAX_NUM_SEQS' HF_TOKEN='$VAST_HF_TOKEN' TOOL_PARSER='$VAST_TOOL_CALL_PARSER' REASONING_PARSER='$VAST_REASONING_PARSER' EXTRA_ARGS='$VAST_EXTRA_ARGS' TENSOR_PARALLEL='$VAST_TENSOR_PARALLEL' LOGGING_PROXY='$VAST_LOGGING_PROXY' FORCE_RESTART='$force_restart' bash -s" < /home/john/dotfiles/.config/vast-bootstrap.bash
      set -l rc $status
      env-cleanup $_pre_vars
      return $rc
    '';
    vast-bootstrap.description = "Bootstrap vLLM on a rented Vast.ai instance (vast-bootstrap [INSTANCE_ID] [--restart] [--no-fzf]; with ≥2 running instances opens an fzf picker unless --no-fzf or fzf is missing).";

    vast-tunnel.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l instance_id ""
      set -l want_restart 0
      set -l no_fzf ""
      for arg in $argv
        switch $arg
          case --restart
            set want_restart 1
          case --no-fzf
            set no_fzf 1
          case '*'
            if test -z "$instance_id"
              set instance_id $arg
            end
        end
      end

      if not _vast-resolve-instance $instance_id running $no_fzf
        env-cleanup $_pre_vars
        return 1
      end

      if systemctl --user is-active --quiet vast-tunnel.service
        if test $want_restart -eq 1
          echo "Restarting existing tunnel ..."
          systemctl --user stop vast-tunnel.service
        else
          echo "Tunnel already up on localhost:$VAST_LOCAL_PORT (pass --restart to recreate)."
          env-cleanup $_pre_vars
          return 0
        end
      end

      set -l ssh_bin (command -v ssh)
      echo "Opening tunnel: localhost:$VAST_LOCAL_PORT -> $VAST_HOST:$VAST_VLLM_PORT"
      systemd-run --user --unit=vast-tunnel --collect \
        $ssh_bin -N \
          -o ServerAliveInterval=30 \
          -o ServerAliveCountMax=3 \
          -o ExitOnForwardFailure=yes \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          -i $VAST_SSH_KEY \
          -p $VAST_SSH_PORT \
          -L $VAST_LOCAL_PORT:localhost:$VAST_VLLM_PORT \
          $VAST_SSH_USER@$VAST_HOST

      for i in (seq 1 20)
        if systemctl --user is-active --quiet vast-tunnel.service
          echo "Tunnel up. Test: curl http://localhost:$VAST_LOCAL_PORT/v1/models"
          env-cleanup $_pre_vars
          return 0
        end
        sleep 0.3
      end
      echo "Tunnel failed to come up. Logs:" >&2
      systemctl --user status vast-tunnel.service --no-pager >&2 || true
      env-cleanup $_pre_vars
      return 1
    '';
    vast-tunnel.description = "Open SSH tunnel localhost:VAST_LOCAL_PORT → rented vLLM (vast-tunnel [INSTANCE_ID] [--restart] [--no-fzf]; with ≥2 running instances opens an fzf picker unless --no-fzf or fzf is missing). One tunnel at a time — close before switching targets.";

    vast-tunnel-down.body = ''
      if systemctl --user is-active --quiet vast-tunnel.service
        systemctl --user stop vast-tunnel.service
        echo "Tunnel stopped."
      else
        echo "No tunnel running."
      end
    '';
    vast-tunnel-down.description = "Stop the vast-tunnel systemd user unit.";

    vast-status.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      echo "=== Vast.ai status (label: $VAST_LABEL) ==="
      echo "Model:  $VAST_MODEL"

      # Identify the host the active tunnel currently forwards to (if any),
      # so we can mark the matching instance with "(tunnel target)".
      set -l tunnel_host ""
      if systemctl --user is-active --quiet vast-tunnel.service
        set -l exec_line (systemctl --user show vast-tunnel.service -p ExecStart --value 2>/dev/null)
        set tunnel_host (printf '%s\n' $exec_line | string match -r 'root@[0-9.]+' | string sub -s 6)
      end

      set -l running ""
      set -l count 0
      if command -v vastai >/dev/null 2>&1
        set -l raw (vastai show instances --raw 2>/dev/null)
        if test -n "$raw"; and test "$raw" != "[]"
          set running (echo $raw | jq -c --arg label "$VAST_LABEL" '
            [.[] | select(.label == $label) | select(.actual_status == "running")]
          ')
          set count (echo $running | jq 'length')
        end
      end

      if test "$count" = "0"
        echo "(no running instances with label '$VAST_LABEL')"
      else
        for idx in (seq 0 (math "$count - 1"))
          set -l inst (echo $running | jq -c ".[$idx]")
          set -l id    (echo $inst | jq -r '.id')
          set -l gpu   (echo $inst | jq -r '.gpu_name')
          set -l ngpu  (echo $inst | jq -r '.num_gpus // 1')
          set -l rate  (echo $inst | jq -r '.dph_total')
          set -l ihost (echo $inst | jq -r '.public_ipaddr')
          set -l iport (echo $inst | jq -r '.ports."22/tcp"[0].HostPort // "?"')
          set -l annot ""
          if test -n "$tunnel_host"; and test "$ihost" = "$tunnel_host"
            set annot "  (tunnel target)"
          end
          printf "Instance: %s  GPU: %s×%s  Hourly: \$%s%s\n" $id $gpu $ngpu $rate $annot
          printf "Host:     %s@%s:%s\n" $VAST_SSH_USER $ihost $iport
        end
      end

      if systemctl --user is-active --quiet vast-tunnel.service
        echo "Tunnel: UP (localhost:$VAST_LOCAL_PORT -> remote :$VAST_VLLM_PORT)"
      else
        echo "Tunnel: DOWN (run: vast-tunnel [INSTANCE_ID])"
      end

      set -l models_url "http://localhost:$VAST_LOCAL_PORT/v1/models"
      if curl -fsS --max-time 3 $models_url >/dev/null 2>&1
        echo "vLLM:   READY at $models_url"
        curl -s $models_url | jq -c '.data[] | {id: .id, max_len: .max_model_len}' 2>/dev/null
      else
        echo "vLLM:   not responding at $models_url"
      end

      env-cleanup $_pre_vars
    '';
    vast-status.description = "Show Vast.ai tunnel + vLLM readiness across all running instances with VAST_LABEL.";

    vast-logs.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l instance_id ""
      set -l n 200
      set -l no_fzf ""
      set -l want_id_mode ""
      for arg in $argv
        switch $arg
          case --id
            set want_id_mode 1
          case --no-fzf
            set no_fzf 1
          case '*'
            if test -n "$want_id_mode"
              set instance_id $arg
              set want_id_mode ""
            else
              set n $arg
            end
        end
      end
      if test -n "$want_id_mode"
        echo "vast-logs: --id requires an INSTANCE_ID argument" >&2
        env-cleanup $_pre_vars
        return 2
      end

      if not _vast-resolve-instance $instance_id running $no_fzf
        env-cleanup $_pre_vars
        return 1
      end

      ssh -i $VAST_SSH_KEY \
          -p $VAST_SSH_PORT \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          $VAST_SSH_USER@$VAST_HOST \
          "tail -n $n -f /workspace/vllm.log"
      set -l rc $status
      env-cleanup $_pre_vars
      return $rc
    '';
    vast-logs.description = "Tail the remote vLLM log (vast-logs [--id INSTANCE_ID] [N=200] [--no-fzf]; with ≥2 running instances opens an fzf picker unless --no-fzf or fzf is missing).";

    vast-metrics.body = ''
            # Check the per-rental metrics monitor (started by vast-bootstrap).
            # Shows monitor status, sample count, avg/peak GPU util, latest rows.
            # vast-destroy fetches the full /workspace/metrics/ at teardown; this
            # is the live-view counterpart.
            set -l _pre_vars (set --names -x)
            if not _vast-load
              env-cleanup $_pre_vars
              return 1
            end
            set -l instance_id ""
            set -l no_fzf ""
            for arg in $argv
              switch $arg
                case --no-fzf
                  set no_fzf 1
                case -h --help
                  echo "Usage: vast-metrics [--no-fzf] [INSTANCE_ID]" >&2
                  env-cleanup $_pre_vars
                  return 0
                case '*'
                  set instance_id $arg
              end
            end
            if not _vast-resolve-instance $instance_id running $no_fzf
              env-cleanup $_pre_vars
              return 1
            end

            ssh -i $VAST_SSH_KEY \
                -p $VAST_SSH_PORT \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR \
                $VAST_SSH_USER@$VAST_HOST \
                'set -u
      echo "=== monitor ==="
      if [ -f /workspace/metrics/monitor.pid ] && kill -0 "$(cat /workspace/metrics/monitor.pid)" 2>/dev/null; then
        echo "  running (pid $(cat /workspace/metrics/monitor.pid))"
      else
        echo "  NOT RUNNING — run vast-bootstrap to start it"
      fi
      echo "=== files ==="
      ls -la /workspace/metrics/ 2>/dev/null || echo "  (none yet)"
      echo "=== gpu.csv summary ==="
      if [ -s /workspace/metrics/gpu.csv ]; then
        awk -F, '"'"'NR>1 {n++; ng[$2]=1; s+=$3+0; if($3+0>p) p=$3+0; if(t0=="") t0=$1; t1=$1} END {ngc=0; for(k in ng) ngc++; if(n>0) printf "  %d samples × %d GPU(s)\n  span: %s →%s\n  avg util: %.1f%%, peak %.0f%%\n", n/ngc, ngc, t0, t1, s/n, p}'"'"' /workspace/metrics/gpu.csv
        echo "=== latest rows ==="
        tail -n 5 /workspace/metrics/gpu.csv
      else
        echo "  (no gpu.csv yet)"
      fi
      echo "=== vllm.prom size ==="
      ls -lh /workspace/metrics/vllm.prom 2>/dev/null || echo "  (none)"'
            set -l rc $status
            env-cleanup $_pre_vars
            return $rc
    '';
    vast-metrics.description = "Show live GPU+vLLM metrics state on the rental (vast-metrics [INSTANCE_ID] [--no-fzf]; monitor status, sample count, avg/peak util, latest samples).";
    vast-fetch-metrics.body = ''
      # Snapshot /workspace/metrics + vllm.log from a running rental into
      # ~/vast-metrics/$id-$ts/, then render PNGs + summary.txt via
      # vast-render-metrics. Non-destructive — instance keeps running.
      # vast-destroy delegates to this for its teardown snapshot.
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end
      set -l instance_id ""
      set -l no_fzf ""
      for arg in $argv
        switch $arg
          case --no-fzf
            set no_fzf 1
          case -h --help
            echo "Usage: vast-fetch-metrics [--no-fzf] [INSTANCE_ID]" >&2
            env-cleanup $_pre_vars
            return 0
          case '*'
            set instance_id $arg
        end
      end
      if not _vast-resolve-instance $instance_id running $no_fzf
        env-cleanup $_pre_vars
        return 1
      end
      set -l ts (date +%Y%m%d-%H%M%S)
      set -l dest "$HOME/vast-metrics/$VAST_INSTANCE_ID-$ts"
      mkdir -p $dest
      echo "Fetching metrics from instance $VAST_INSTANCE_ID → $dest ..."
      scp -i $VAST_SSH_KEY \
          -P $VAST_SSH_PORT \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          -r $VAST_SSH_USER@$VAST_HOST:/workspace/metrics $dest/
      set -l rc_metrics $status
      scp -i $VAST_SSH_KEY \
          -P $VAST_SSH_PORT \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o LogLevel=ERROR \
          $VAST_SSH_USER@$VAST_HOST:/workspace/vllm.log $dest/
      set -l rc_log $status

      # Capture rental cost metadata so vast-render-metrics can compute $/Mtok.
      # vastai show instances may fail (revoked key, paused instance) — non-fatal.
      set -l raw (vastai show instances --raw 2>/dev/null)
      if test -n "$raw"; and test "$raw" != "[]"
        echo $raw | jq --arg id "$VAST_INSTANCE_ID" '
          .[] | select((.id | tostring) == $id)
              | {instance_id: .id, dph_total: .dph_total,
                 gpu_name: .gpu_name, num_gpus: (.num_gpus // 1),
                 fetched_at: now | todate}
        ' > $dest/rental.json 2>/dev/null
      end
      if test $rc_metrics -ne 0; or test $rc_log -ne 0
        echo "Warning: scp partial/failed (metrics rc=$rc_metrics, log rc=$rc_log)." >&2
      end
      if test -d $dest/metrics
        if command -q vast-render-metrics
          vast-render-metrics $dest
          or echo "Warning: vast-render-metrics failed; raw CSVs are still in $dest." >&2
        else
          echo "vast-render-metrics not on PATH (rebuild needed); raw CSVs in $dest." >&2
        end
      end
      env-cleanup $_pre_vars
      return 0
    '';
    vast-fetch-metrics.description = "Snapshot /workspace/metrics + vllm.log from a running rental into ~/vast-metrics/<id>-<ts>/ and render PNGs (vast-fetch-metrics [--no-fzf] [INSTANCE_ID]; non-destructive — instance keeps running).";

    # Helpers for finding and renting Vast.ai instances. Wrap the `vastai`
    # CLI (provided by the wrapper in shared-cli-configuration.nix). Run
    # `vast-search` first, copy an offer ID, then `vast-create <id>`.
    vast-search.body = ''
      set -l query 'reliability > 0.85 gpu_name=B200 disk_space > 170 rentable=true'
      if test (count $argv) -gt 0
        set query $argv
      end
      vastai search offers $query -o 'dph_total'
    '';
    vast-search.description = "Search Vast.ai offers (default: verified 1xB200, ≥99% reliability, ≥5Gbps net, ≥250GB disk; pass extra args to override query).";

    vast-search-big.body = ''
      # Like vast-search but filters by total VRAM across the host instead
      # of a specific GPU model. Default ≥1100 GB covers DeepSeek-V4-Pro
      # (~865 GB weights + KV/activation headroom) — typically 8×B200 or
      # 8×H200. gpu_total_ram is in GB per vastai's field schema.
      #
      # disk_space > 1000: V4-Pro weights are ~865 GB on disk; plus venv,
      # HF download scratch, and vLLM runtime overhead. 1 TB is the safe
      # floor — anything less risks an aborted download mid-bootstrap.
      set -l query 'reliability > 0.85 gpu_total_ram > 1100 disk_space > 1000 rentable=true'
      if test (count $argv) -gt 0
        set query $argv
      end
      vastai search offers $query -o 'dph_total'
    '';
    vast-search-big.description = "Search Vast.ai offers with ≥1100 GB total host VRAM (sized for DeepSeek-V4-Pro). Pass extra args to override query.";

    vast-search-any.body = ''
      # Catch-all "modern big-VRAM card" search — doesn't pin a model name,
      # just filters by capability. Matches B200 (192 GB, 8 TB/s) and any
      # future Hopper-successor with HBM3e+. Excludes A100/H100/H200 by the
      # 175 GB per-GPU floor, and excludes Ampere by compute_cap ≥ 900.
      #
      #   gpu_ram > 175       — per-GPU VRAM in GB; B200=192, MI300=192
      #   gpu_mem_bw > 4000   — memory bandwidth in GB/s; B200~8000, H200~4800
      #   compute_cap >= 900  — Hopper or newer (H100/H200=900, B200=1000)
      set -l query 'reliability > 0.85 gpu_ram > 175 gpu_mem_bw > 4000 compute_cap >= 900 disk_space > 170 rentable=true'
      if test (count $argv) -gt 0
        set query $argv
      end
      vastai search offers $query -o 'dph_total'
    '';
    vast-search-any.description = "Search Vast.ai offers for any modern big-VRAM GPU (≥175 GB/GPU, ≥4 TB/s memory bw, Hopper+). Pass extra args to override query.";

    vast-create.body = ''
      set -l offer_id $argv[1]
      if test -z "$offer_id"
        echo "Usage: vast-create OFFER_ID" >&2
        echo "Find an offer with: vast-search" >&2
        return 1
      end
      vastai create instance $offer_id \
        --image nvidia/cuda:12.8.0-devel-ubuntu24.04 \
        --disk 300 \
        --ssh \
        --direct \
        --label vllm-deepseek-v4
    '';
    vast-create.description = "Create a Vast.ai instance with our minimal CUDA image (300GB disk, SSH-only, labelled vllm-deepseek-v4).";

    vast-show.body = ''
      vastai show instances --raw 2>/dev/null | jq -r '.[] | select(.label == "vllm-deepseek-v4") | "id=\(.id) status=\(.actual_status) host=\(.public_ipaddr) ssh_port=\(.ports."22/tcp"[0].HostPort // "?") gpu=\(.gpu_name) disk=\(.disk_space)GB hourly=\(.dph_total)"'
    '';
    vast-show.description = "Show currently-rented Vast.ai instances tagged vllm-deepseek-v4 (id, status, host, ssh port).";

    vast-destroy.body = ''
      set -l no_fetch ""
      set -l no_fzf ""
      set -l instance_id ""
      for arg in $argv
        switch $arg
          case --no-fetch
            set no_fetch 1
          case --no-fzf
            set no_fzf 1
          case -h --help
            echo "Usage: vast-destroy [--no-fetch] [--no-fzf] INSTANCE_ID" >&2
            return 0
          case '*'
            set instance_id $arg
        end
      end
      if test -z "$instance_id"
        echo "Usage: vast-destroy [--no-fetch] [--no-fzf] INSTANCE_ID" >&2
        echo "List instances with: vast-show" >&2
        return 1
      end

      if test -z "$no_fetch"
        vast-fetch-metrics --no-fzf $instance_id
        or echo "Warning: vast-fetch-metrics failed; destroying anyway." >&2
      end

      echo "Destroying Vast.ai instance $instance_id ..."
      vastai destroy instance $instance_id
    '';
    vast-destroy.description = "Destroy a Vast.ai instance, fetching /workspace/metrics first (--no-fetch to skip; --no-fzf to skip picker).";

    _vast-wait-status.body = ''
      # Poll the Vast.ai API until instance $argv[1] reaches the desired
      # state ($argv[2] = "running" or "stopped"), up to 60s (20 × 3s).
      # Returns 0 on both match and timeout — the caller's API call already
      # succeeded; this just gives the state change time to land before
      # control returns to the prompt.
      #
      # Usage: _vast-wait-status INSTANCE_ID running|stopped
      set -l id $argv[1]
      set -l want $argv[2]
      set -l cur ""
      echo -n "Waiting for $want "
      for i in (seq 1 20)
        set cur (vastai show instances --raw 2>/dev/null | jq -r --arg id "$id" '
          .[] | select((.id | tostring) == $id) | .actual_status
        ')
        switch $want
          case running
            if test "$cur" = "running"
              echo " done (status=$cur)."
              return 0
            end
          case stopped
            if test -n "$cur"; and test "$cur" != "running"
              echo " done (status=$cur)."
              return 0
            end
        end
        echo -n "."
        sleep 3
      end
      echo " timeout after 60s (last status=$cur)."
      return 0
    '';
    _vast-wait-status.description = "Internal: poll until a Vast instance reaches running/stopped state, up to 60s.";

    _vast-complete-ids.body = ''
      # Emit `id<TAB>description` lines for fish tab completion of vast-*
      # commands that take an INSTANCE_ID. Must be silent on missing CLI,
      # API errors, or empty results — completion callbacks should never
      # noise the prompt.
      #
      # Usage: _vast-complete-ids running|stopped|any
      #
      # Defaults VAST_LABEL to vllm-deepseek-v4 (matches vast-create /
      # vast-show) since completion runs in a fresh subshell without
      # _vast-load having been called.
      set -l want $argv[1]
      set -l label vllm-deepseek-v4
      test -n "$VAST_LABEL"; and set label $VAST_LABEL
      if not command -v vastai >/dev/null 2>&1
        return 0
      end
      set -l raw (vastai show instances --raw 2>/dev/null)
      if test -z "$raw"; or test "$raw" = "[]"
        return 0
      end
      echo $raw | jq -r --arg label "$label" --arg want "$want" '
        .[]
        | select(.label == $label)
        | select(
            $want == "any"
            or ($want == "running" and .actual_status == "running")
            or ($want == "stopped" and .actual_status != "running")
          )
        | "\(.id)\t\(.actual_status) \(.gpu_name)×\(.num_gpus // 1) $\(.dph_total)/hr"
      ' 2>/dev/null
    '';
    _vast-complete-ids.description = "Internal: emit id<TAB>description lines for fish tab completion of vast-* INSTANCE_ID args.";

    vast-pause.body = ''
      # Stops a running rental via `vastai stop instance`. Disk/data are
      # preserved (storage charges still accrue at ~$0.10/GB-month); compute
      # billing pauses. Resume with `vast-unpause` — subject to GPU
      # availability on the host machine, which is NOT guaranteed.
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l instance_id ""
      set -l no_fzf ""
      for arg in $argv
        switch $arg
          case --no-fzf
            set no_fzf 1
          case '*'
            if test -z "$instance_id"
              set instance_id $arg
            end
        end
      end

      if not _vast-resolve-instance $instance_id running $no_fzf
        env-cleanup $_pre_vars
        return 1
      end

      if not set -q VAST_INSTANCE_ID; or test -z "$VAST_INSTANCE_ID"
        echo "vast-pause needs API discovery, but VAST_HOST/VAST_SSH_PORT pin is active." >&2
        echo "Comment out the pin in ~/.config/vast/profile, or run: vastai stop instance <ID>" >&2
        env-cleanup $_pre_vars
        return 1
      end

      # Warn if the active tunnel targets this instance — it'll go stale.
      if systemctl --user is-active --quiet vast-tunnel.service
        set -l exec_line (systemctl --user show vast-tunnel.service -p ExecStart --value 2>/dev/null)
        set -l tunnel_host (printf '%s\n' $exec_line | string match -r 'root@[0-9.]+' | string sub -s 6)
        if test "$tunnel_host" = "$VAST_HOST"
          echo "Note: active tunnel targets $VAST_HOST — run 'vast-tunnel-down' to clean up." >&2
        end
      end

      echo "Pausing Vast.ai instance $VAST_INSTANCE_ID ..."
      vastai stop instance $VAST_INSTANCE_ID
      set -l rc $status
      if test $rc -eq 0
        _vast-wait-status $VAST_INSTANCE_ID stopped
      end
      env-cleanup $_pre_vars
      return $rc
    '';
    vast-pause.description = "Pause (stop) a running Vast.ai instance — disk preserved, compute billing pauses (vast-pause [INSTANCE_ID] [--no-fzf]; with ≥2 running opens an fzf picker unless --no-fzf or fzf is missing). Waits up to 60s for the state change.";

    vast-unpause.body = ''
      # Restarts a previously-stopped rental via `vastai start instance`.
      # Vast.ai may refuse if the host machine no longer has the GPU
      # capacity available — there is no guarantee. After a successful
      # start the instance gets fresh public_ipaddr / ssh port, which
      # vast-bootstrap & vast-tunnel will rediscover on next call.
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l instance_id ""
      set -l no_fzf ""
      set -l no_bootstrap 0
      for arg in $argv
        switch $arg
          case --no-fzf
            set no_fzf 1
          case --no-bootstrap
            set no_bootstrap 1
          case '*'
            if test -z "$instance_id"
              set instance_id $arg
            end
        end
      end

      if not _vast-resolve-instance $instance_id stopped $no_fzf
        env-cleanup $_pre_vars
        return 1
      end

      if not set -q VAST_INSTANCE_ID; or test -z "$VAST_INSTANCE_ID"
        echo "vast-unpause needs API discovery, but VAST_HOST/VAST_SSH_PORT pin is active." >&2
        echo "Comment out the pin in ~/.config/vast/profile, or run: vastai start instance <ID>" >&2
        env-cleanup $_pre_vars
        return 1
      end

      echo "Unpausing Vast.ai instance $VAST_INSTANCE_ID ..."
      echo "Note: starting is subject to GPU availability on the host machine." >&2
      vastai start instance $VAST_INSTANCE_ID
      set -l rc $status
      if test $rc -ne 0
        env-cleanup $_pre_vars
        return $rc
      end

      _vast-wait-status $VAST_INSTANCE_ID running

      # Capture the id before env-cleanup wipes VAST_INSTANCE_ID — vast-bootstrap
      # will call _vast-load + _vast-resolve-instance itself with a fresh API
      # query, picking up the new public_ipaddr / ssh_port that Vast assigns
      # on every start.
      set -l unpaused_id $VAST_INSTANCE_ID
      env-cleanup $_pre_vars

      if test $no_bootstrap -eq 1
        echo "Skipping auto-bootstrap (--no-bootstrap). Run manually: vast-bootstrap $unpaused_id" >&2
        return 0
      end

      # Container status flips to "running" the moment vastd marks it up, but
      # SSH inside the container often needs another few seconds to bind.
      # Sleep briefly so the first bootstrap SSH doesn't race the daemon.
      echo "Container running; waiting 10s for SSH to settle, then re-running vast-bootstrap ..."
      sleep 10
      vast-bootstrap $unpaused_id
      return $status
    '';
    vast-unpause.description = "Resume (start) a stopped Vast.ai instance and re-launch vLLM via vast-bootstrap (vast-unpause [INSTANCE_ID] [--no-fzf] [--no-bootstrap]; with ≥2 stopped opens an fzf picker unless --no-fzf or fzf is missing). Pass --no-bootstrap to skip the vLLM relaunch.";

    vast-balance.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l credit (vastai show user --raw 2>/dev/null | jq -r '.credit // 0')
      set -l hourly 0
      set -l count 0
      set -l raw (vastai show instances --raw 2>/dev/null)
      if test -n "$raw"; and test "$raw" != "[]"
        set hourly (echo $raw | jq --arg label "$VAST_LABEL" '
          [.[] | select(.label == $label) | select(.actual_status == "running") | .dph_total | tonumber] | add // 0
        ')
        set count (echo $raw | jq --arg label "$VAST_LABEL" '
          [.[] | select(.label == $label) | select(.actual_status == "running")] | length
        ')
      end

      printf "Credit: \$%.2f\n" $credit
      printf "Rate: \$%.2f/hr (%d instances)\n" $hourly $count

      if test (echo $hourly | jq '. > 0') = "true"
        set -l hrs (jq -rn --arg b "$credit" --arg h "$hourly" '
          ($b | tonumber) as $bal | ($h | tonumber) as $hr |
          ($bal / $hr) as $total_hours |
          ($total_hours | floor) as $hours |
          (($total_hours - $hours) * 60 | round) as $minutes |
          "\($hours):\($minutes | tostring | if length == 1 then "0" + . else . end)"
        ')
        printf "Remaining: ~%s\n" $hrs
      end

      env-cleanup $_pre_vars
    '';
    vast-balance.description = "Show Vast.ai credit balance + summed hourly burn rate across running instances + hours remaining.";
  };
}
