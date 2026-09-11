# DESCRIPTION: Probe ChatGPT subscription quota through the LiteLLM proxy. Prints "available" or the reset time parsed from the upstream 429. Usage: codex-quota [model-slug] [--debug]
# Quota state is not exposed by any LiteLLM endpoint, so this fires a minimal
# Responses probe through the proxy. A 429 carries the upstream reset data in
# its error body; a 200 means the quota is not exhausted (the probe consumes a
# tiny amount of subscription quota in that case). Default model: gpt-5.6-terra.
set -l debug 0
set -l model chatgpt/gpt-5.6-terra
for arg in $argv
  if test "$arg" = "--debug" -o "$arg" = "-v"
    set debug 1
  else if test "$arg" = "--help" -o "$arg" = "-h"
    echo "usage: codex-quota [model-slug] [--debug]"
    echo "  model-slug defaults to chatgpt/gpt-5.6-terra"
    return 0
  else
    set model $arg
  end
end

if not set -q LITELLM_EDITOR_KEY; and set -q LITELLM_MASTER_KEY
  set -gx LITELLM_EDITOR_KEY $LITELLM_MASTER_KEY
end
if not set -q LITELLM_EDITOR_KEY
  echo "LITELLM_EDITOR_KEY (or LITELLM_MASTER_KEY) not set." >&2
  return 1
end

set -l payload (string join '' \
  '{"model":"' $model '",' \
  '"input":[{"role":"user","content":[{"type":"input_text","text":"ping"}]}],' \
  '"stream":true}')

set -l resp (curl -sS --max-time 60 -w '\n%{http_code}' \
  "https://llm.2143.me/v1/responses" \
  -H "Authorization: Bearer $LITELLM_EDITOR_KEY" \
  -H "Content-Type: application/json" \
  -d "$payload" 2>/dev/null)
set -l code $resp[-1]
set -l body (string join (printf '\n') $resp[1..-2])

if test "$debug" = "1"
  echo "DEBUG HTTP $code:" >&2
  printf '%s\n' $body >&2
end

switch $code
  case 200
    set_color green
    echo "$model: quota available"
    set_color normal
    echo "(probe consumed a small amount of subscription quota)"

  case 429
    # The message embeds the upstream ChatgptException JSON:
    # ...ChatgptException - {"error":{"type":"usage_limit_reached","plan_type":...}}...
    set -l msg (printf '%s' $body | jq -r '.error.message // empty' 2>/dev/null)
    set -l raw (printf '%s' $msg | string match -r '\{.*\}' | head -n1)
    set -l plan (printf '%s' $raw | jq -r '.error.plan_type // .plan_type // empty' 2>/dev/null)
    set -l reset_at (printf '%s' $raw | jq -r '.error.resets_at // .resets_at // empty' 2>/dev/null)
    set -l secs (printf '%s' $raw | jq -r '.error.resets_in_seconds // .resets_in_seconds // empty' 2>/dev/null)
    if test -n "$reset_at" -a "$reset_at" != "null"
      set -l when (date -d "@$reset_at" '+%Y-%m-%d %H:%M %Z')
      set -l duration ""
      if test -n "$secs" -a "$secs" != "null"
        set -l hrs (math --scale=0 "floor($secs / 3600)")
        set -l mins (math --scale=0 "floor(($secs - $hrs * 3600) / 60)")
        set duration " (in "$hrs"h "$mins"m)"
      end
      set_color yellow
      echo "$model: quota EXHAUSTED (plan: $plan)"
      echo "resets: $when$duration"
      set_color normal
    else
      echo "$model: 429 rate limited (no reset info in body)"
      printf '%s\n' $body
    end

  case 401
    echo "$model: unauthorized — check LITELLM_EDITOR_KEY." >&2
    return 1

  case '*'
    echo "$model: unexpected HTTP $code" >&2
    printf '%s\n' $body >&2
    return 1
end
