# DESCRIPTION: Generate a video with Google Veo via the litellm proxy. Usage: veo "prompt" [--image seed.jpg] [--key sk-...] [--seconds 8] [--size 1280x720] [--model veo-3.1] [-o out.mp4] [--poll-interval 5] [--timeout 600] [--debug]
set -l _pre_vars (set --names -x)

# Key resolution: --key flag > $LITELLM_EDITOR_KEY > $LITELLM_MASTER_KEY >
# /run/agenix/llm-runtime-keys (this machine's managed keys).
set -l base_url "https://llm.2143.me/v1"

argparse --name=veo 'image=' 'k/key=' 'm/model=' 's/seconds=' 'z/size=' 'o/output=' 'i/poll-interval=' 't/timeout=' 'd/debug' -- $argv
or return 1

set -l api_key "$_flag_key"
if test -z "$api_key"
  set api_key "$LITELLM_EDITOR_KEY"
end
if test -z "$api_key"
  set api_key "$LITELLM_MASTER_KEY"
end
if test -z "$api_key"
  set -l creds_file /run/agenix/llm-runtime-keys
  if test -f $creds_file
    envsource $creds_file >/dev/null
    set api_key "$LITELLM_EDITOR_KEY"
    if test -z "$api_key"
      set api_key "$LITELLM_MASTER_KEY"
    end
  end
end
if test -z "$api_key"
  echo "veo: no API key. Pass --key sk-... (virtual key from https://llm.2143.me/ui/keys) or export LITELLM_EDITOR_KEY" >&2
  return 1
end

set -l model "veo-3.1"
if set -q _flag_model; and test -n "$_flag_model"
  set model "$_flag_model"
end
set -l seconds "8"
if set -q _flag_seconds; and test -n "$_flag_seconds"
  set seconds "$_flag_seconds"
end
set -l size "1280x720"
if set -q _flag_size; and test -n "$_flag_size"
  set size "$_flag_size"
end
set -l poll_interval 5
if set -q _flag_poll_interval; and test -n "$_flag_poll_interval"
  set poll_interval "$_flag_poll_interval"
end
set -l timeout 600
if set -q _flag_timeout; and test -n "$_flag_timeout"
  set timeout "$_flag_timeout"
end
# Optional seed image (first frame). Veo image conditioning accepts one image
# per generation; encode it as base64 with a mime type.
set -l image_b64 ""
set -l image_mime ""
if set -q _flag_image; and test -n "$_flag_image"
  set -l image_file "$_flag_image"
  if not test -f "$image_file"
    echo "veo: image file not found: $image_file" >&2
    return 1
  end
  switch (string lower (path extension "$image_file"))
    case .jpg .jpeg
      set image_mime "image/jpeg"
    case .png
      set image_mime "image/png"
    case .webp
      set image_mime "image/webp"
    case '*'
      echo "veo: unsupported image type (use .jpg, .png or .webp)" >&2
      return 1
  end
  if test (uname) = Darwin
    set image_b64 (base64 -b 0 < "$image_file")
  else
    set image_b64 (base64 -w0 < "$image_file")
  end
  if test -z "$image_b64"
    echo "veo: could not base64-encode image: $image_file" >&2
    return 1
  end
end

set -l prompt (string join ' ' $argv)
if test -z "$prompt"
  echo "usage: veo \"prompt\" [--image seed.jpg] [--key sk-...] [--seconds 8] [--size 1280x720] [--model veo-3.1] [-o out.mp4] [--poll-interval 5] [--timeout 600] [--debug]" >&2
  return 1
end

for bin in curl jq
  if not type -q $bin
    echo "veo: requires $bin" >&2
    return 1
  end
end

# Build the request body with jq so prompts with quotes/newlines are safe.
set -l body (jq -n --arg model "$model" --arg prompt "$prompt" --arg seconds "$seconds" --arg size "$size" --arg b64 "$image_b64" --arg mime "$image_mime" \
  '{model: $model, prompt: $prompt, seconds: $seconds, size: $size} + (if ($b64 | length) > 0 then {input_reference: {bytesBase64Encoded: $b64, mimeType: $mime}} else {} end)')

set -l create_resp (curl -s "$base_url/videos" \
  -H "Authorization: Bearer $api_key" \
  -H "Content-Type: application/json" \
  -d "$body")
if test -z "$create_resp"
  echo "veo: create request failed (network error?)" >&2
  return 1
end
set -l err (printf '%s\n' $create_resp | jq -r '.error.message // empty' 2>/dev/null)
if test -n "$err"
  echo "veo: create failed: $err" >&2
  return 1
end
# IMPORTANT: use THIS id for all polling/download. Status responses re-encode
# the id with an empty model_id, which litellm cannot resolve back to a model.
set -l video_id (printf '%s\n' $create_resp | jq -r '.id // empty')
if test -z "$video_id"
  echo "veo: no video id in create response" >&2
  if set -q _flag_debug
    printf '%s\n' $create_resp >&2
  end
  return 1
end
echo "Created video $video_id (model $model)"

set -l waited 0
set -l vid_status "processing"
set -l status_resp ""
while test "$vid_status" = "processing"
  if test $waited -ge $timeout
    echo "veo: timed out after "$timeout"s, video still processing" >&2
    echo "  poll manually: curl \"$base_url/videos/$video_id\" -H \"Authorization: Bearer <your key>\"" >&2
    return 1
  end
  sleep $poll_interval
  set waited (math $waited + $poll_interval)
  set status_resp (curl -s "$base_url/videos/$video_id" -H "Authorization: Bearer $api_key")
  set vid_status (printf '%s\n' $status_resp | jq -r '.status // empty' 2>/dev/null)
  if test -z "$vid_status"
    echo "veo: bad status response" >&2
    if set -q _flag_debug
      printf '%s\n' $status_resp >&2
    end
    return 1
  end
  echo "  $vid_status after "$waited"s"
end

if test "$vid_status" != "completed"
  set -l fail (printf '%s\n' $status_resp | jq -r '.error // empty' 2>/dev/null)
  echo "veo: video failed: $fail" >&2
  return 1
end
echo "Video completed after "$waited"s"

set -l out "$_flag_output"
if test -z "$out"
  set out "veo-"(date +%Y%m%d-%H%M%S)".mp4"
end
curl -L -s -o "$out" "$base_url/videos/$video_id/content" -H "Authorization: Bearer $api_key"
if not test -s "$out"
  echo "veo: download produced an empty file: $out" >&2
  rm -f "$out"
  return 1
end
echo "Saved $out ("(du -h "$out" | cut -f1)")"

env-cleanup $_pre_vars
