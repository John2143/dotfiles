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
    deepseek-costs.body = ''
      set -l _pre_vars (set --names -x)

      # Load DeepSeek API key from runtime keys.
      set -l creds_file /run/agenix/llm-runtime-keys
      if not test -f $creds_file
        echo "LLM runtime keys not found at $creds_file" >&2
        return 1
      end
      envsource $creds_file >/dev/null

      set -l debug 0
      set -l no_open 0
      for arg in $argv
        if test "$arg" = "--debug" -o "$arg" = "-v"
          set debug 1
        else if test "$arg" = "--no-open"
          set no_open 1
        end
      end

      # Open the DeepSeek platform usage page so the user can see detailed
      # per-key usage history and export CSVs. The API only exposes balance;
      # granular usage data is only available via the dashboard.
      set -l usage_url "https://platform.deepseek.com/usage"
      set -l did_open 0
      if test $no_open -eq 0 -a -n "$DISPLAY"
        if type -q xdg-open
          echo "Opening DeepSeek usage page..."
          xdg-open "$usage_url" 2>/dev/null; and set did_open 1
        end
        if test $did_open -eq 0; and type -q open
          echo "Opening DeepSeek usage page..."
          open "$usage_url" 2>/dev/null; and set did_open 1
        end
      end
      if test $did_open -eq 0
        echo "DeepSeek usage page: $usage_url"
      end
      echo ""

      # Query balance via the DeepSeek API.
      if set -q DEEPSEEK_API_KEY
        set -l resp (curl -s \
          -L -X GET 'https://api.deepseek.com/user/balance' \
          -H 'Accept: application/json' \
          -H "Authorization: Bearer $DEEPSEEK_API_KEY")
        if test "$debug" = "1"
          echo "DEBUG balance response:" >&2
          printf '%s\n' $resp | jq . >&2 2>/dev/null; or printf '%s\n' $resp >&2
        end
        set -l err (printf '%s\n' $resp | jq -r '.error.message // empty' 2>/dev/null)
        if test -n "$err"
          echo "Balance check error: $err"
        else
          set_color --bold; printf "=== DeepSeek Balance ===\n"; set_color normal
          printf '%s\n' $resp | jq -r '
            .balance_infos[] |
            "  Currency:       \(.currency)\n" +
            "  Total Balance:  \(.total_balance)\n" +
            "    Granted:      \(.granted_balance)\n" +
            "    Topped Up:    \(.topped_up_balance)"'

          set -l is_available (printf '%s\n' $resp | jq -r '.is_available // true')
          if test "$is_available" = "false"
            set_color red
            echo "  ⚠ Balance insufficient for API calls"
            set_color normal
          end

          echo ""
          set_color brblack
          echo "Pricing (per 1M tokens):"
          echo "  deepseek-v4-flash  input $0.14  (cache hit $0.0028)  output $0.28"
          echo "  deepseek-v4-pro    input $0.435 (cache hit $0.003625) output $0.87"
          echo "  (v4-pro is 75% off until 2026-05-31; see platform.deepseek.com/usage for history)"
          set_color normal
        end
      else
        echo "DEEPSEEK_API_KEY not found in runtime keys."
      end

      env-cleanup $_pre_vars
    '';
    deepseek-costs.description = "Open DeepSeek usage page and show current balance. Pass --no-open to suppress browser, --debug for raw API responses.";

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
    agent-cron-list.body = ''
      systemctl --user list-timers --all --no-pager 2>/dev/null | \
        awk 'NR==1 || /agent-/ || /NEXT/' | \
        awk 'BEGIN { count=0 } /agent-/ { count++ } { print } END { if (count==0) print "(no agent timers)" }'
    '';
    agent-cron-list.description = "List agent-created transient timers and their next trigger time";

    agent-cron-stop.body = ''
      if test (count $argv) -lt 1
        echo "Usage: agent-cron-stop <unit-name>" >&2
        echo "  e.g. agent-cron-stop agent-check-pr-42" >&2
        return 1
      end
      set -l unit $argv[1]
      if not string match -q "agent-*" $unit
        echo "Error: unit name must start with 'agent-'" >&2
        return 1
      end
      systemctl --user stop "$unit.timer" "$unit.service" 2>&1
      systemctl --user reset-failed "$unit.service" 2>/dev/null
    '';
    agent-cron-stop.description = "Stop an agent-created timer (and its service). Name must start with 'agent-'.";

    agent-cron-cleanup.body = ''
      set -l units (systemctl --user list-units --all --no-pager --plain 2>/dev/null | \
        awk '/agent-.*\.(timer|service)/ {print $1}')
      if test -z "$units"
        echo "No agent timers to clean up."
        return 0
      end
      echo "Stopping: $units"
      systemctl --user stop $units
      for u in $units
        systemctl --user reset-failed "$u" 2>/dev/null
      end
      echo "Done."
    '';
    agent-cron-cleanup.description = "Stop and clean up all agent-created timers and services";
  };
}
