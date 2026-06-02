# DESCRIPTION: Open Anthropic billing page for balance and show recent spend (7d)
set -l _pre_vars (set --names -x)
llm-unsafe-load-admin-keys &>/dev/null

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
