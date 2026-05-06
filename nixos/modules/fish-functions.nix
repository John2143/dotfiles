{ ... }:
{
  programs.fish.interactiveShellInit = ''
    # Tab completion for vast-* commands that take an INSTANCE_ID.
    # Filters by VAST_LABEL (default vllm-deepseek-v4) and status:
    #   running  → vast-bootstrap, vast-tunnel, vast-logs, vast-pause
    #   stopped  → vast-unpause
    #   any      → vast-destroy
    complete -c vast-destroy  -f -a '(_vast-complete-ids any)'
    complete -c vast-bootstrap -f -a '(_vast-complete-ids running)'
    complete -c vast-tunnel    -f -a '(_vast-complete-ids running)'
    complete -c vast-logs      -f -a '(_vast-complete-ids running)'
    complete -c vast-pause     -f -a '(_vast-complete-ids running)'
    complete -c vast-unpause   -f -a '(_vast-complete-ids stopped)'
  '';

  programs.fish.functions = {
    hostname.body = "/usr/bin/env cat /etc/hostname";
    kc.body = ''
      set -f new_env (kubectl config get-contexts -o name | fzf)
      if test "A$new_env" = "A"
          exit 1
      end
      kubectl config use-context $new_env
    '';
    vc.body = ''
      set -f nodes (tailscale status --json | jq -r '.Peer[] | select(.ExitNodeOption == true) | .DNSName' | string collect)
      # add a node of "None" to the list of nodes so that we can exit if the user doesn't select a node
      # and also keep newlines separating the nodes so that fzf can display them on separate lines
      set nodes "None"\n"$nodes"
      set -f new_node (echo $nodes | fzf)
      if test "A$new_node" = "A"
          exit 1
      end
      if test $new_node = "None"
          sudo tailscale set --exit-node=""
      else
          sudo tailscale set --exit-node=$new_node --exit-node-allow-lan-access
      end
    '';
    vc.description = "Select a Tailscale exit node";

    test-program.body = ''
      set -f program "$argv[1]"
      mkdir -p ~/test/$program
      cd ~/test/$program
      nix flake init --template templates#rust
      nix-shell -p cargo --command "cargo init . --bin --name $program"
      nix-shell -p cargo --command "cargo b"
      echo "/result" >> .gitignore
      echo ".direnv" >> .gitignore
      git add -A
      nix build .
      ./result/bin/$program
      direnv allow
      git add -A
      git commit -m "Initial commit"
    '';
    replace-all.body = ''
      set -f find $argv[1]
      set -f rep $argv[2]
      set -f filter $argv[3]
      if test $filter
          echo "Replacing /$find/ with /$rep/ with extra $filter"
          rg --files-with-matches $filter | rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
      else
          echo "Replacing /$find/ with /$rep/"
          rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
      end
    '';
    sk.body = ''
      set -x SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep $EMAIL -B 3 | grep "(work|github|disco|1E7452EAEE)" -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')
      echo "Set Signing key to $SIGNING_KEY"
      git config --global user.signingkey $SIGNING_KEY > /dev/null
    '';
    juush.body = ''
      set -l _pre_vars (set --names -x)
      set -l creds_file /run/agenix/rustfs-credentials
      if test -f $creds_file
        envsource $creds_file
      end
      bash /home/john/dotfiles/.config/juush.bash $argv
      env-cleanup $_pre_vars
    '';
    juush.description = "Upload a file to juush and get a short URL";
    bigjuush.body = ''
      set -l creds_file /run/agenix/rustfs-credentials
      if not test -f $creds_file
        echo "Error: RustFS credentials not found at $creds_file" >&2
        return 1
      end
      set -l _pre_vars (set --names -x)
      envsource $creds_file
      mc alias set rustfs https://files.john2143.com $RUSTFS_USER $RUSTFS_PASSWORD 2>/dev/null
      bash /home/john/dotfiles/.config/nas-share.sh $argv
      env-cleanup $_pre_vars
    '';
    bigjuush.description = "Upload files to RustFS and get public share links";
    omp-safe.body = ''
      # Run omp with the tool-call approval hook loaded. Default `omp` runs
      # auto; `omp-safe` prompts before risky bash, force-pushes, etc.
      # See `~/.omp/agent/hooks/approve.ts` for the rule list.
      # Verify with: `try-check-prompt`
      omp --hook=$HOME/.omp/agent/hooks/approve.ts $argv
    '';
    omp-safe.description = "Run omp with the approval hook for risky tool calls";
    try-check-prompt.body = ''
      # Run omp with the approval hook and a safe prompt that exercises the
      # approve/deny confirm dialog. The prompt instructs the model to run a command
      # containing "rm -rf" (echo'd, not executed). Since the hook checks the
      # command string for risky patterns, `echo rm -rf <dir>` triggers the
      # confirm prompt even though the actual command is harmless.
      #
      # If the hook is working:
      #   - The confirm dialog appears: "Approve tool call?"
      #   - Approving runs: echo rm -rf /tmp/omp-hook-test
      #   - Denying throws and the tool call is blocked.
      #
      # If NO dialog appears, the hook may not be wired correctly.
      omp --hook=$HOME/.omp/agent/hooks/approve.ts $argv "Run: echo rm -rf /tmp/omp-hook-test  # verify the approval hook"
    '';
    try-check-prompt.description = "Verify the approval hook works — triggers the approve/deny confirm dialog with a safe echo'd rm -rf command";
 

    llm-load-keys.body = ''
      # Loads the admin LLM key (ANTHROPIC_ADMIN_KEY) for use by llm-costs and
      # llm-topup-anthropic. The runtime key (ANTHROPIC_API_KEY) is mounted
      # at /run/agenix/llm-runtime-keys but only the admin file goes here —
      # llm-costs and llm-topup-anthropic need admin scope for cost reports & billing.
      set -l creds_file /run/agenix/llm-admin-keys
      if not test -f $creds_file
        echo "LLM admin keys not found at $creds_file" >&2
        return 1
      end
      envsource $creds_file
    '';
    llm-load-keys.description = "Load Anthropic admin API key into current shell (on-demand)";
    argocd.body = ''
      set -l creds_file /run/agenix/argo-admin-password
      if not test -f $creds_file
        echo "ArgoCD admin password not found at $creds_file" >&2
        return 1
      end
      set -l password (cat $creds_file)
      set -lx ARGOCD_SERVER argocd.ts.2143.me
      set -lx ARGOCD_AUTH_TOKEN (
        curl -sk https://argocd.ts.2143.me/api/v1/session \
          -H 'Content-Type: application/json' \
          -d '{"username":"admin","password":"'$password'"}' | jq -r '.token // empty'
      )
      if test -z "$ARGOCD_AUTH_TOKEN"
        echo "Failed to obtain ArgoCD auth token" >&2
        return 1
      end
      command argocd --grpc-web $argv
    '';
    argocd.description = "ArgoCD CLI with auto-authentication via age-encrypted admin password";

    llm-costs.body = ''
      set -l _pre_vars (set --names -x)
      llm-load-keys &>/dev/null

      set -l debug 0
      set -l no_open 0
      for arg in $argv
        if test "$arg" = "--debug" -o "$arg" = "-v"
          set debug 1
        else if test "$arg" = "--no-open"
          set no_open 1
        end
      end

      # Open the Anthropic Console billing page so the user can see their balance.
      # There is no public API for balance/credit queries, so the browser is the
      # only way to check remaining credits programmatically from CLI.
      set -l billing_url "https://platform.claude.com/settings/billing"
      set -l did_open 0
      if test $no_open -eq 0 -a -n "$DISPLAY"
        if type -q xdg-open
          echo "Opening Anthropic billing page..."
          xdg-open "$billing_url" 2>/dev/null; and set did_open 1
        end
        if test $did_open -eq 0; and type -q open
          echo "Opening Anthropic billing page..."
          open "$billing_url" 2>/dev/null; and set did_open 1
        end
      end
      if test $did_open -eq 0
        echo "Anthropic billing page: $billing_url"
      end
      echo ""

      # Show a quick recent cost summary (last 7 days, single request).
      # This only covers standard+batch tier; priority/fast-mode is billed separately.
      if set -q ANTHROPIC_ADMIN_KEY
        set -l start_date (date -d "7 days ago" -u +%Y-%m-%dT00:00:00Z)
        set -l end_date (date -d tomorrow -u +%Y-%m-%dT00:00:00Z)
        set -l resp (curl -s \
          "https://api.anthropic.com/v1/organizations/cost_report?starting_at=$start_date&ending_at=$end_date&bucket_width=1d&group_by[]=description&limit=7" \
          -H "anthropic-version: 2023-06-01" \
          -H "x-api-key: $ANTHROPIC_ADMIN_KEY")
        if test "$debug" = "1"
          echo "DEBUG cost_report response:" >&2
          printf '%s\n' $resp | jq . >&2 2>/dev/null; or printf '%s\n' $resp >&2
        end
        set -l err (printf '%s\n' $resp | jq -r '.error.message // empty' 2>/dev/null)
        if test -n "$err"
          echo "Cost report error: $err"
        else
          set -l total (printf '%s\n' $resp | jq '[.data[].results[].amount | tonumber] | add // 0')
          if test -z "$total" -o "$total" = "null" -o "$total" = "0"
            echo "Recent spend (7d): no data"
          else
            set_color --bold; printf "=== Recent Spend (last 7 days, standard+batch tier) ===\n"; set_color normal
            printf "Total: \$%.2f\n" (math "$total / 100")
            printf '%s\n' $resp | jq -r '
              [.data[].results[] | select((.amount | tonumber) > 0)]
              | group_by(.description.model // "other")
              | map({model: .[0].description.model // "other", total: ([.[].amount | tonumber] | add)})
              | sort_by(-.total)[]
              | "  \(.model): $\(.total | round | . / 100)"'
            set_color brblack
            echo "  (see billing page for full balance and all tiers)"
            set_color normal
          end
        end
      end

      env-cleanup $_pre_vars
    '';
    llm-costs.description = "Open Anthropic billing page for balance and show recent spend (7d). Pass --no-open to suppress browser, --debug for raw API responses.";

    # === Vast.ai cloud GPU helpers ===
    llm-topup-anthropic.body = ''
      set -l _pre_vars (set --names -x)
      llm-load-keys &>/dev/null

      set -l usage_str "Usage: llm-topup-anthropic <dollar-amount>"

      if test (count $argv) -lt 1
        echo "$usage_str" >&2
        env-cleanup $_pre_vars
        return 1
      end

      set -l amount $argv[1]
      if not string match -qr '^\d+(\.\d{0,2})?$' "$amount"
        echo "Error: amount must be a number (e.g. 50 or 25.00)" >&2
        env-cleanup $_pre_vars
        return 1
      end

      # Open the Anthropic Console billing page for manual credit purchase.
      # There is no public API for purchasing credits — the billing page is the
      # only way to add funds programmatically from CLI.
      set -l billing_url "https://platform.claude.com/settings/billing"
      set -l did_open 0
      if test -n "$DISPLAY"
        if type -q xdg-open
          echo "Opening Anthropic billing page to add \$$amount..."
          xdg-open "$billing_url" 2>/dev/null; and set did_open 1
        end
        if test $did_open -eq 0; and type -q open
          echo "Opening Anthropic billing page to add \$$amount..."
          open "$billing_url" 2>/dev/null; and set did_open 1
        end
      end
      if test $did_open -eq 0
        echo "Anthropic billing page: $billing_url"
      end
      echo ""
      echo "To add \$$amount in credits:"
      echo "  1. Click \"Buy credits\" on the billing page"
      echo "  2. Enter \"$amount\" as the amount"
      echo "  3. Complete the purchase"

      env-cleanup $_pre_vars
    '';
    llm-topup-anthropic.description = "Open Anthropic billing page to purchase \$AMOUNT in credits";
    #
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
          "MODEL='$VAST_MODEL' SERVED='$VAST_SERVED_MODEL_NAME' VLLM_PORT='$VAST_VLLM_PORT' MAX_LEN='$VAST_MAX_MODEL_LEN' MEM_UTIL='$VAST_GPU_MEM_UTIL' MAX_NUM_SEQS='$VAST_MAX_NUM_SEQS' HF_TOKEN='$VAST_HF_TOKEN' TOOL_PARSER='$VAST_TOOL_CALL_PARSER' REASONING_PARSER='$VAST_REASONING_PARSER' EXTRA_ARGS='$VAST_EXTRA_ARGS' TENSOR_PARALLEL='$VAST_TENSOR_PARALLEL' FORCE_RESTART='$force_restart' bash -s" < /home/john/dotfiles/.config/vast-bootstrap.bash
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
      set -l instance_id $argv[1]
      if test -z "$instance_id"
        echo "Usage: vast-destroy INSTANCE_ID" >&2
        echo "List instances with: vast-show" >&2
        return 1
      end
      echo "Destroying Vast.ai instance $instance_id ..."
      vastai destroy instance $instance_id
    '';
    vast-destroy.description = "Destroy a Vast.ai instance by ID (run vast-show to find the ID).";

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
      if test $rc -eq 0
        _vast-wait-status $VAST_INSTANCE_ID running
      end
      env-cleanup $_pre_vars
      return $rc
    '';
    vast-unpause.description = "Resume (start) a stopped Vast.ai instance — subject to host GPU availability (vast-unpause [INSTANCE_ID] [--no-fzf]; with ≥2 stopped opens an fzf picker unless --no-fzf or fzf is missing). Waits up to 60s for the state change.";

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

    env-cleanup.body = ''
      for _v in (set --names -x)
        if not contains $_v $argv
          set -e $_v
        end
      end
    '';
    env-cleanup.description = "Remove exported env vars not in the given snapshot";

    envsource.body = ''
      set -f envfile "$argv"
      if not test -f "$envfile"
          echo "Unable to load $envfile"
          return 1
      end
      while read line
          if not string match -qr '^#|^$' "$line" # skip empty lines and comments
              if string match -qr '=' "$line" # if `=` in line assume we are setting variable.
                  set item (string split -m 1 '=' $line)
                  set item[2] (eval echo $item[2]) # expand any variables in the value
                  set -gx $item[1] $item[2]
                  echo "Exported key: $item[1]" # could say with $item[2] but that might be a secret
              else
                  eval $line # allow for simple commands to be run e.g. cd dir/mamba activate env
              end
          end
      end < "$envfile"
    '';
  };
}
