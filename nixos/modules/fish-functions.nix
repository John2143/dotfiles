{ ... }:
{
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
    llm-load-keys.body = ''
      # Loads admin LLM keys (ANTHROPIC_ADMIN_KEY, OPENAI_ADMIN_KEY) for use by
      # llm-costs. Runtime keys (ANTHROPIC_API_KEY, OPENAI_API_KEY) are mounted
      # at /run/agenix/llm-runtime-keys but only the admin file goes here —
      # llm-costs needs admin scope to read org cost reports.
      set -l creds_file /run/agenix/llm-admin-keys
      if not test -f $creds_file
        echo "LLM admin keys not found at $creds_file" >&2
        return 1
      end
      envsource $creds_file
    '';
    llm-load-keys.description = "Load LLM admin API keys into current shell (on-demand)";
    _llm-paginate-json.body = ''
      # Walk a paginated JSON API of the shape { data: [...], has_more, next_page }.
      # Outputs the merged .data array as compact JSON on stdout.
      # On API error, outputs the error message and returns 1.
      #
      # Usage: _llm-paginate-json DEBUG BASE_URL [-H HEADER]...
      set -l debug $argv[1]
      set -l base_url $argv[2]
      set -l headers $argv[3..]
      set -l url $base_url
      set -l pages

      while true
        set -l resp (curl -s $headers "$url")
        if test "$debug" = "1"
          echo "DEBUG GET $url" >&2
          printf '%s\n' $resp | jq . >&2 2>/dev/null; or printf '%s\n' $resp >&2
          echo "" >&2
        end
        set -l err (printf '%s\n' $resp | jq -r '.error.message // empty' 2>/dev/null)
        if test -n "$err"
          echo "$err"
          return 1
        end
        set -a pages (printf '%s\n' $resp | jq -c '.data // []' 2>/dev/null)
        set -l has_more (printf '%s\n' $resp | jq -r '.has_more // "false"' 2>/dev/null)
        test "$has_more" = "true"; or break
        set -l next (printf '%s\n' $resp | jq -r '.next_page // empty' 2>/dev/null)
        test -n "$next"; or break
        set url "$base_url&page=$next"
      end

      printf '%s\n' $pages | jq -sc 'add // []' 2>/dev/null
    '';
    _llm-paginate-json.description = "Internal: walk a paginated JSON API and emit the merged .data array";
    llm-costs.body = ''
      set -l _pre_vars (set --names -x)
      llm-load-keys &>/dev/null

      set -l debug 0
      set -l filtered_argv
      for arg in $argv
        if test "$arg" = "--debug" -o "$arg" = "-v"
          set debug 1
        else
          set -a filtered_argv $arg
        end
      end

      set -l days 30
      if test (count $filtered_argv) -gt 0
        set days $filtered_argv[1]
      end

      # --- OpenAI: /v1/organization/costs ---
      # Response amounts are USD (decimal strings); single endpoint, paginated by cursor.
      if set -q OPENAI_ADMIN_KEY
        set -l now (date +%s)
        set -l start_time (math "$now - $days * 86400")
        set -l url "https://api.openai.com/v1/organization/costs?start_time=$start_time&group_by[]=line_item&limit=180"
        set -l data (_llm-paginate-json $debug $url \
          -H "Authorization: Bearer $OPENAI_ADMIN_KEY")
        if test $status -ne 0
          echo "OpenAI error: $data"
        else
          set -l total (printf '%s\n' $data | jq '[.[].results[].amount.value | tonumber] | add // 0')
          if test -z "$total" -o "$total" = "null" -o "$total" = "0"
            echo "OpenAI: no data"
          else
            set_color --bold; printf "=== OpenAI (%d days) ===\n" $days; set_color normal
            printf "Total: \$%.2f\n" $total
            printf '%s\n' $data | jq -r '
              [.[].results[] | select((.amount.value | tonumber) > 0)]
              | group_by(.line_item)
              | map({item: .[0].line_item, total: ([.[].amount.value | tonumber] | add)})
              | sort_by(-.total)[]
              | "  \(.item): $\(.total * 100 | round | . / 100)"'
          end
        end
      else
        echo "OpenAI: no admin key set (OPENAI_ADMIN_KEY)"
      end

      echo ""

      # --- Anthropic: /v1/organizations/cost_report ---
      # Response amounts are in cents (divide by 100 for USD).
      # Standard + batch tier only; priority/fast-mode tier uses a separate billing
      # model and is excluded by design — see Claude Code section below for that.
      if set -q ANTHROPIC_ADMIN_KEY
        set -l start_date (date -d "$days days ago" -u +%Y-%m-%dT00:00:00Z)
        set -l end_date (date -d tomorrow -u +%Y-%m-%dT00:00:00Z)
        set -l url "https://api.anthropic.com/v1/organizations/cost_report?starting_at=$start_date&ending_at=$end_date&bucket_width=1d&group_by[]=model&limit=31"
        set -l data (_llm-paginate-json $debug $url \
          -H "anthropic-version: 2023-06-01" \
          -H "x-api-key: $ANTHROPIC_ADMIN_KEY")
        if test $status -ne 0
          echo "Anthropic error: $data"
        else
          set -l total (printf '%s\n' $data | jq '[.[].results[].amount | tonumber] | add // 0')
          if test -z "$total" -o "$total" = "null" -o "$total" = "0"
            echo "Anthropic: no data"
          else
            set_color --bold; printf "=== Anthropic (%d days) ===\n" $days; set_color normal
            printf "Total: \$%.2f (standard+batch tier)\n" (math "$total / 100")
            printf '%s\n' $data | jq -r '
              [.[].results[] | select((.amount | tonumber) > 0)]
              | group_by(.model // "other")
              | map({model: .[0].model // "other", total: ([.[].amount | tonumber] | add)})
              | sort_by(-.total)[]
              | "  \(.model): $\(.total | round | . / 100)"'
            set_color brblack
            echo "  (priority/fast-mode tier billed separately, see Claude Code section)"
            set_color normal
          end
        end

        # --- Anthropic Claude Code: /v1/organizations/usage_report/claude_code ---
        # Anthropic's own per-day estimated cost across ALL tiers including priority/fast.
        # Endpoint accepts a single date only, so we loop one paginated request per day.
        # Per-record schema: .actor, .models[]{model, estimated_cost.amount (cents), ...}
        set -l cc_pages
        set -l cc_err ""
        for offset in (seq (math "$days - 1") -1 0)
          set -l day (date -d "$offset days ago" -u +%Y-%m-%d)
          set -l cc_url "https://api.anthropic.com/v1/organizations/usage_report/claude_code?starting_at=$day&limit=1000"
          set -l cc_data (_llm-paginate-json $debug $cc_url \
            -H "anthropic-version: 2023-06-01" \
            -H "x-api-key: $ANTHROPIC_ADMIN_KEY")
          if test $status -ne 0
            set cc_err "$cc_data"
            break
          end
          set -a cc_pages $cc_data
        end

        if test -n "$cc_err"
          echo ""
          echo "Anthropic Claude Code error: $cc_err"
        else
          set -l merged (printf '%s\n' $cc_pages | jq -sc 'add // []')
          set -l cc_total (printf '%s\n' $merged | jq '[.[].models[].estimated_cost.amount | tonumber] | add // 0')
          if test -n "$cc_total" -a "$cc_total" != "null" -a "$cc_total" != "0"
            echo ""
            set_color --bold; printf "=== Anthropic Claude Code estimate (%d days) ===\n" $days; set_color normal
            printf "Total: \$%.2f (all tiers, Anthropic estimate)\n" (math "$cc_total / 100")
            printf '%s\n' $merged | jq -r '
              [.[].models[] | select((.estimated_cost.amount | tonumber) > 0)]
              | group_by(.model)
              | map({model: .[0].model, total: ([.[].estimated_cost.amount | tonumber] | add)})
              | sort_by(-.total)[]
              | "  \(.model): $\(.total | round | . / 100)"'
          end
        end
      else
        echo "Anthropic: no admin key set (ANTHROPIC_ADMIN_KEY)"
      end

      env-cleanup $_pre_vars
    '';
    llm-costs.description = "Show LLM API usage costs (default: last 30 days; pass N for custom, --debug for raw responses)";

    # === Vast.ai cloud GPU helpers ===
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
      # Internal helper: load profile + agenix creds, apply defaults,
      # discover host/port via Vast.ai API. Sets exported globals VAST_*
      # used by the other vast-* helpers. Caller is responsible for
      # env-cleanup.

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
      test -n "$VAST_MAX_MODEL_LEN"; or set -gx VAST_MAX_MODEL_LEN "1000000"
      test -n "$VAST_GPU_MEM_UTIL"; or set -gx VAST_GPU_MEM_UTIL "0.95"
      test -n "$VAST_LOCAL_PORT"; or set -gx VAST_LOCAL_PORT "8001"
      test -n "$VAST_VLLM_PORT"; or set -gx VAST_VLLM_PORT "8000"
      test -n "$VAST_SSH_USER"; or set -gx VAST_SSH_USER "root"
      set -q VAST_HF_TOKEN; or set -gx VAST_HF_TOKEN ""
      set -q VAST_TOOL_CALL_PARSER; or set -gx VAST_TOOL_CALL_PARSER ""
      set -q VAST_REASONING_PARSER; or set -gx VAST_REASONING_PARSER ""
      set -q VAST_EXTRA_ARGS; or set -gx VAST_EXTRA_ARGS ""

      # 5) Discover host/SSH port via API unless overridden in profile.
      if test -z "$VAST_HOST"; or test -z "$VAST_SSH_PORT"
        if not command -v vastai >/dev/null 2>&1
          echo "vastai CLI not found and VAST_HOST/VAST_SSH_PORT not set in $profile." >&2
          echo "Either install the wrapper (rebuild after enabling) or pin host manually." >&2
          return 1
        end
        set -l raw (vastai show instances --raw 2>/dev/null)
        if test -z "$raw"; or test "$raw" = "[]"
          echo "Vast.ai API returned no instances. Run `vast-create OFFER_ID` first." >&2
          return 1
        end
        set -l info (echo $raw | jq -r --arg label "$VAST_LABEL" '
          [.[] | select(.label == $label) | select(.actual_status == "running")]
          | first
          | if . == null then "" else "\(.public_ipaddr)\t\(.ports["22/tcp"][0].HostPort)" end
        ' 2>/dev/null)
        if test -z "$info"; or test "$info" = "null"
          echo "No running Vast.ai instance with label '$VAST_LABEL' found." >&2
          echo "List with: vast-show    Launch with: vast-create OFFER_ID" >&2
          return 1
        end
        set -gx VAST_HOST (echo $info | cut -f1)
        set -gx VAST_SSH_PORT (echo $info | cut -f2)
      end
    '';
    _vast-load.description = "Internal: load Vast profile, apply defaults, discover host/port via API.";

    vast-bootstrap.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
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
          "MODEL='$VAST_MODEL' SERVED='$VAST_SERVED_MODEL_NAME' VLLM_PORT='$VAST_VLLM_PORT' MAX_LEN='$VAST_MAX_MODEL_LEN' MEM_UTIL='$VAST_GPU_MEM_UTIL' HF_TOKEN='$VAST_HF_TOKEN' TOOL_PARSER='$VAST_TOOL_CALL_PARSER' REASONING_PARSER='$VAST_REASONING_PARSER' EXTRA_ARGS='$VAST_EXTRA_ARGS' bash -s" < /home/john/dotfiles/.config/vast-bootstrap.bash
      set -l rc $status
      env-cleanup $_pre_vars
      return $rc
    '';
    vast-bootstrap.description = "Bootstrap vLLM on the rented Vast.ai instance (host auto-discovered, idempotent).";

    vast-tunnel.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      if systemctl --user is-active --quiet vast-tunnel.service
        if contains -- --restart $argv
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
    vast-tunnel.description = "Open SSH tunnel from localhost:VAST_LOCAL_PORT to the rented vLLM port (--restart to recreate).";

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
      echo "Host:   $VAST_SSH_USER@$VAST_HOST:$VAST_SSH_PORT"
      echo "Model:  $VAST_MODEL"
      if systemctl --user is-active --quiet vast-tunnel.service
        echo "Tunnel: UP (localhost:$VAST_LOCAL_PORT -> remote :$VAST_VLLM_PORT)"
      else
        echo "Tunnel: DOWN (run: vast-tunnel)"
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
    vast-status.description = "Show Vast.ai tunnel + vLLM readiness.";

    vast-logs.body = ''
      set -l _pre_vars (set --names -x)
      if not _vast-load
        env-cleanup $_pre_vars
        return 1
      end

      set -l n 200
      if test (count $argv) -gt 0
        set n $argv[1]
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
    vast-logs.description = "Tail the remote vLLM log (vast-logs [N=200]).";

    # Helpers for finding and renting Vast.ai instances. Wrap the `vastai`
    # CLI (provided by the wrapper in shared-cli-configuration.nix). Run
    # `vast-search` first, copy an offer ID, then `vast-create <id>`.
    vast-search.body = ''
      set -l query 'reliability > 0.99 num_gpus=1 gpu_name=B200 inet_down > 5000 disk_space > 250 verified=true rentable=true'
      if test (count $argv) -gt 0
        set query $argv
      end
      vastai search offers $query -o 'dph_total'
    '';
    vast-search.description = "Search Vast.ai offers (default: verified 1xB200, ≥99% reliability, ≥5Gbps net, ≥250GB disk; pass extra args to override query).";

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
