# DESCRIPTION: Show OpenRouter balance, per-key usage, and daily model activity. Pass --debug for raw API responses.
set -l _pre_vars (set --names -x)
llm-unsafe-load-admin-keys &>/dev/null

set -l debug 0
for arg in $argv
  if test "$arg" = "--debug" -o "$arg" = "-v"
    set debug 1
  end
end

if not set -q OPENROUTER_ADMIN_KEY
  echo "OPENROUTER_ADMIN_KEY not found. Add it to llm-admin-keys." >&2
  env-cleanup $_pre_vars
  return 1
end

# === Balance ===
set -l creds_resp (curl -s \
  "https://openrouter.ai/api/v1/credits" \
  -H "Authorization: Bearer $OPENROUTER_ADMIN_KEY")

if test "$debug" = "1"
  echo "DEBUG credits response:" >&2
  printf '%s\n' $creds_resp | jq . >&2 2>/dev/null; or printf '%s\n' $creds_resp >&2
end

set -l err (printf '%s\n' $creds_resp | jq -r '.error.message // empty' 2>/dev/null)
if test -n "$err"
  echo "Credits error: $err" >&2
else
  set -l total (printf '%s\n' $creds_resp | jq -r '.data.total_credits // 0')
  set -l used (printf '%s\n' $creds_resp | jq -r '.data.total_usage // 0')
  set -l remaining (math "$total - $used")

  set_color --bold; printf "=== OpenRouter Balance ===\n"; set_color normal
  printf "  Total Credits:    \$%.2f\n" $total
  printf "  Total Usage:      \$%.2f\n" $used
  if test "$total" = "0"
    printf "  Remaining:        \$0.00\n"
  else
    printf "  Remaining:        \$%.2f  (%.1f%%)\n" $remaining (math "($used / $total) * 100")
  end
  set_color brblack
  echo "  (credit data may be cached up to ~60s)"
  set_color normal
end

echo ""

# === Per-Key Usage ===
set -l keys_resp (curl -s \
  "https://openrouter.ai/api/v1/keys" \
  -H "Authorization: Bearer $OPENROUTER_ADMIN_KEY")

if test "$debug" = "1"
  echo "DEBUG keys response:" >&2
  printf '%s\n' $keys_resp | jq . >&2 2>/dev/null; or printf '%s\n' $keys_resp >&2
end

set -l keys_err (printf '%s\n' $keys_resp | jq -r '.error.message // empty' 2>/dev/null)
if test -n "$keys_err"
  echo "Keys error: $keys_err" >&2
else
  set -l key_count (printf '%s\n' $keys_resp | jq '[.data[] | select(.disabled != true)] | length')
  if test "$key_count" -gt 0
    set_color --bold; printf "=== Per-Key Usage ===\n"; set_color normal
    printf '%s\n' $keys_resp | jq -r '
      .data[]
      | select(.disabled != true)
      | "  \(.name // .label // "unnamed")"
      + "\n    Total:       $" + (.usage | tostring)
      + "\n    Daily:       $" + (.usage_daily | tostring)
      + "\n    Weekly:      $" + (.usage_weekly | tostring)
      + "\n    Monthly:     $" + (.usage_monthly | tostring)
      + if .limit != null then
          "\n    Limit:       $" + (.limit | tostring)
          + " (remaining: $" + (.limit_remaining | tostring) + ")"
        else
          "\n    Limit:       none"
        end
      + if .limit_reset != null then "\n    Limit reset: " + .limit_reset else "" end
    '
  else
    echo "  (no active API keys)"
  end
end

echo ""

# === Daily Activity (last 30 completed UTC days) ===
set -l act_resp (curl -s \
  "https://openrouter.ai/api/v1/activity" \
  -H "Authorization: Bearer $OPENROUTER_ADMIN_KEY")

if test "$debug" = "1"
  echo "DEBUG activity response:" >&2
  printf '%s\n' $act_resp | jq . >&2 2>/dev/null; or printf '%s\n' $act_resp >&2
end

set -l act_err (printf '%s\n' $act_resp | jq -r '.error.message // empty' 2>/dev/null)
if test -n "$act_err"
  echo "Activity error: $act_err" >&2
else
  set -l act_count (printf '%s\n' $act_resp | jq '[.data[] | select(.usage > 0)] | length')
  if test "$act_count" -gt 0
    set_color --bold; printf "=== Daily Activity (last 30 completed UTC days) ===\n"; set_color normal
    printf '%s\n' $act_resp | jq -r '
      [.data[] | select(.usage > 0)]
      | group_by(.date[:10])
      | reverse
      | .[]
      | ([.[].usage] | add | . * 100 | round | . / 100) as $day_total
      | ( "  \(.[0].date[:10])  $" + ($day_total | tostring) ),
        ( sort_by(-.usage)[]
          | "    \(.model)  $" + (.usage | tostring)
            + "  \(.requests) reqs  \(.prompt_tokens)→\(.completion_tokens) tok"
            + (if .reasoning_tokens > 0 then " +\(.reasoning_tokens) reason" else "" end)
            + "  [" + .provider_name + "]"
        )'
    set_color brblack
    echo "  (current partial UTC day excluded)"
    set_color normal
  else
    echo "  (no activity in the last 30 days)"
  end
end

env-cleanup $_pre_vars
