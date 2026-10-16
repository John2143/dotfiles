# vikunja-task-attachment: move files on and off Vikunja tasks for agents.
#
# The board's MCP (Vikunja's in-tree pkg/modules/mcp, v2.7.0) cannot move file
# bytes by design: exposure.go leaves task-attachments-upload/-download off its
# allow-list, and its body-media gate drops every non-JSON operation. The REST
# operations work with the same API token, so this CLI ships exactly those two
# verbs. Delete deliberately stays on the MCP (task_attachments_delete), where
# the token's route permissions gate it -- do not add a delete verb here.
#
# Instance URL + token come from the agent's own agenix MCP config
# (/run/agenix/omp-mcp): one secret to rotate, uploads carry the agent's
# identity. Enabled only where that secret exists -- same gate as .mcp.json in
# omp-config.nix -- so hosts importing home-cli.nix without it (nas, big,
# closet, strradmsad, darwin) never evaluate the secret path.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: let
  cfg = config.custom.vikunja-attachment;
  hasToken = (osConfig.age.secrets or {}) ? omp-mcp;
in {
  options.custom.vikunja-attachment = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = hasToken;
      description = "Install vikunja-task-attachment. Defaults to on wherever the agent's MCP config secret (omp-mcp) exists.";
    };

    mcpServer = lib.mkOption {
      type = lib.types.str;
      default = "ai_tasks";
      description = ''
        The board's MCP server name as it appears in tool names (mcp__<name>_...):
        the mcpServers key lowercased, every run of characters outside [a-z_]
        replaced by "_", repeated "_" collapsed, outer "_" trimmed -- exactly as
        omp's tool-bridge.ts sanitizes it. Exactly one key must match; there is
        no fallback to another server (that would write to the wrong board).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "vikunja-task-attachment";
        runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
        text = ''
          MCP_CONFIG="${osConfig.age.secrets.omp-mcp.path}"
          MCP_SERVER="${cfg.mcpServer}"

          usage() {
            printf '%s\n' \
              'usage:' \
              '  vikunja-task-attachment upload   <task-id> <file>' \
              '  vikunja-task-attachment download <task-id> <attachment-name> <out-path|->' \
              "" \
              '<task-id> is the numeric "id" from MCP results, not the "#N" identifier.' \
              'upload refuses if the task already has an attachment with that file name.' \
              'download never overwrites; "-" writes the bytes to stdout.' \
              'Prints one JSON line on success (download to stdout prints the bytes).' \
              'exit: 0 ok, 1 config/API error, 2 usage, 3 conflict, 4 no such attachment'
          }

          die() {
            local code=$1
            shift
            printf 'vikunja-task-attachment: %s\n' "$*" >&2
            exit "$code"
          }

          # Sets BASE (REST base, .../api/v2) and AUTH (verbatim Authorization
          # header value) from the one mcpServers entry whose sanitized key is
          # MCP_SERVER. Errors print key names only, never values.
          load_config() {
            local entry url
            [[ -r $MCP_CONFIG ]] || die 1 "cannot read $MCP_CONFIG (is the omp-mcp agenix secret on this host?)"
            entry=$(jq -ce --arg s "$MCP_SERVER" '
              [ .mcpServers // {} | to_entries[]
                | select((.key | ascii_downcase | gsub("[^a-z_]+"; "_") | gsub("_+"; "_") | gsub("^_+|_+$"; "")) == $s) ]
              | if length == 1 then .[0].value else empty end' "$MCP_CONFIG") \
              || die 1 "need exactly one mcpServers entry named $MCP_SERVER after sanitizing; keys present: $(jq -r '.mcpServers // {} | keys | join(", ")' "$MCP_CONFIG" 2>/dev/null)"
            url=$(jq -re '.url | select(type == "string" and (test("[$][{]") | not)) | sub("/+$"; "")' <<<"$entry") \
              || die 1 "$MCP_SERVER entry has no literal url; entry keys: $(jq -r 'keys | join(", ")' <<<"$entry")"
            [[ $url == */api/v2/mcp ]] || die 1 "$MCP_SERVER url does not end in /api/v2/mcp"
            BASE=''${url%/mcp}
            AUTH=$(jq -re '
              [ .headers // {} | to_entries[] | select(.key | ascii_downcase == "authorization") | .value ]
              | if length == 1 and (.[0] | type == "string" and (startswith("!") | not) and (test("[$][{]") | not) and (test("[\r\n\"\\\\]") | not))
                then .[0] else empty end' <<<"$entry") \
              || die 1 "$MCP_SERVER needs exactly one literal Authorization header (not a !command, env reference, or containing quotes/backslashes/newlines); header keys: $(jq -r '.headers // {} | keys | join(", ")' <<<"$entry")"
          }

          # curl with the Authorization header fed on stdin (printf is a shell
          # builtin): the token never appears in argv, /proc, or any message.
          api() {
            printf 'header = "Authorization: %s"\n' "$AUTH" \
              | curl --config - --silent --show-error --fail-with-body "$@"
          }

          # Prints the ids of attachments on task $1 whose file name is exactly
          # $2, one per line, walking every page. Runs inside $(...), where
          # errexit does not apply, so every failure is handled explicitly.
          find_by_name() {
            local task=$1 name=$2 page=1 resp pages
            while :; do
              resp=$(api "$BASE/tasks/$task/attachments?page=$page") || {
                printf '%s\n' "$resp" >&2
                return 1
              }
              jq -r --arg n "$name" '.items[] | select(.file.name == $n) | .id' <<<"$resp" || return 1
              pages=$(jq -er '.total_pages | numbers' <<<"$resp") || return 1
              ((page >= pages)) && return 0
              page=$((page + 1))
            done
          }

          cmd_upload() {
            [[ $# -eq 2 ]] || {
              usage >&2
              exit 2
            }
            local task=$1 file=$2 name ids res
            [[ $task =~ ^[0-9]+$ ]] || die 2 "task id must be the numeric id, got: $task"
            [[ -f $file && -r $file ]] || die 2 "not a readable regular file: $file"
            # curl -F parses ; , and " inside the path; refuse instead of misreading.
            [[ $file != *[\;,\"]* ]] || die 2 "path must not contain ; , or a double quote: $file"
            name=$(basename -- "$file")
            load_config
            ids=$(find_by_name "$task" "$name") || die 1 "could not list attachments on task $task"
            [[ -z $ids ]] || die 3 "task $task already has an attachment named $name (id $(head -n1 <<<"$ids")); not uploading"
            res=$(api --form "files=@$file" "$BASE/tasks/$task/attachments") || {
              printf '%s\n' "$res" >&2
              die 1 "upload to task $task failed"
            }
            # 201 even on partial failure: per-file errors live in the body.
            jq -e '((.errors // []) | length == 0) and ((.success // []) | length == 1)' <<<"$res" >/dev/null || {
              jq -r '(.errors // [])[] | .message' <<<"$res" >&2 || printf '%s\n' "$res" >&2
              die 1 "upload to task $task was rejected"
            }
            jq -c '.success[0] | {task: .task_id, attachment_id: .id, name: .file.name, size: .file.size}' <<<"$res"
          }

          cmd_download() {
            [[ $# -eq 3 ]] || {
              usage >&2
              exit 2
            }
            local task=$1 name=$2 out=$3 dir ids n
            [[ $task =~ ^[0-9]+$ ]] || die 2 "task id must be the numeric id, got: $task"
            [[ -n $name ]] || die 2 "attachment name is empty"
            if [[ $out == - ]]; then
              dir=''${TMPDIR:-/tmp}
            else
              [[ ! -e $out ]] || die 3 "refusing to overwrite existing $out"
              dir=$(dirname -- "$out")
            fi
            [[ -d $dir && -w $dir ]] || die 2 "not a writable directory: $dir"
            load_config
            ids=$(find_by_name "$task" "$name") || die 1 "could not list attachments on task $task"
            [[ -n $ids ]] || die 4 "task $task has no attachment named $name"
            n=$(wc -l <<<"$ids")
            [[ $n -eq 1 ]] || die 3 "task $task has $n attachments named $name (ids $(paste -sd, <<<"$ids")); resolve in the UI"
            TMP=$(mktemp -p "$dir" .vikunja-download.XXXXXX)
            if ! api --output "$TMP" "$BASE/tasks/$task/attachments/$ids"; then
              head -c 2000 -- "$TMP" >&2
              printf '\n' >&2
              die 1 "download of $name from task $task failed"
            fi
            if [[ $out == - ]]; then
              cat -- "$TMP"
            else
              # ln fails atomically if $out exists; mv -n's exit status varies across coreutils 9.x.
              ln -- "$TMP" "$out" || {
                [[ -e $out ]] && die 3 "refusing to overwrite $out (created while downloading)"
                die 1 "could not create $out"
              }
              rm -f -- "$TMP"
              TMP=""
              jq -nc --argjson task "$task" --argjson id "$ids" --arg name "$name" \
                --arg path "$(realpath -- "$out")" --argjson size "$(stat -c %s -- "$out")" \
                '{task: $task, attachment_id: $id, name: $name, path: $path, size: $size}'
            fi
          }

          BASE=""
          AUTH=""
          TMP=""
          trap '[[ -z $TMP ]] || rm -f -- "$TMP"' EXIT

          case ''${1:-} in
            upload)
              shift
              cmd_upload "$@"
              ;;
            download)
              shift
              cmd_download "$@"
              ;;
            -h | --help | help) usage ;;
            *)
              usage >&2
              exit 2
              ;;
          esac
        '';
      })
    ];
  };
}
