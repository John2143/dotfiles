# DESCRIPTION: Load admin-scoped LLM API keys into current shell (unsafe: exports secrets to env). Call before llm-costs, llm-topup-anthropic, openrouter-costs.
# Loads the admin LLM keys (ANTHROPIC_ADMIN_KEY, OPENROUTER_ADMIN_KEY)
# for use by llm-costs, llm-topup-anthropic, and openrouter-costs. The
# runtime key is mounted at /run/agenix/llm-runtime-keys but only the
# admin file goes here — cost/usage endpoints need admin-scope keys.
set -l creds_file /run/agenix/llm-admin-keys
if not test -f $creds_file
  echo "LLM admin keys not found at $creds_file" >&2
  return 1
end
envsource $creds_file
