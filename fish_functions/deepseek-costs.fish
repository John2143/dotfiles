# DESCRIPTION: Open DeepSeek usage page and show current balance. Pass --no-open to suppress browser, --debug for raw API responses.
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
