# DESCRIPTION: Open Anthropic billing page to purchase $AMOUNT in credits
set -l _pre_vars (set --names -x)
llm-unsafe-load-admin-keys &>/dev/null

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
