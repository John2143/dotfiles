# vikunja: one CLI for the Vikunja things the board's MCP cannot do.
#
# Vikunja's in-tree MCP (pkg/modules/mcp, v2.7.0) leaves two gaps that agents
# hit constantly:
#   * file bytes -- exposure.go keeps task-attachments-upload/-download off its
#     allow-list and its body-media gate drops every non-JSON operation, so a
#     task's attachments cannot be moved through an MCP tool at all;
#   * time tracking -- the live action registry has no time-entry actions, so
#     "when did the agent start and stop working" has no MCP representation.
# Both gaps are plain REST calls on the same token, so this one binary carries
# them: `vikunja attach upload|download` and `vikunja time start|stop|list`.
#
# Deliberate omissions: no attachment delete verb (task_attachments_delete on
# the MCP is gated by the token's route permissions -- keep it there), and no
# time-entry edit/delete (only start, stop and list are needed to mark work).
#
# Instance URL + token come from the agent's own agenix MCP config
# (/run/agenix/omp-mcp): one secret to rotate, every write carries the agent's
# identity. Enabled only where that secret exists -- same gate as .mcp.json in
# omp-config.nix -- so hosts importing home-cli.nix without it (nas, big,
# closet, strradmsad, darwin) never evaluate the secret path.
#
# The API token must be permitted on the routes used here:
#   /tasks/:id/attachments (GET, POST)            -- attach list/upload/download
#   /time-entries (GET, POST)                     -- time start
#   /time-entries/timer/stop (POST)               -- time stop
#   /tasks/:id/time-entries (GET)                 -- time list
# Missing routes make Vikunja answer 401 with a generic "invalid token" body;
# the CLI names the offending route instead of echoing that body verbatim.
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: let
  cfg = config.custom.vikunja-cli;
  hasToken = (osConfig.age.secrets or {}) ? omp-mcp;
in {
  options.custom.vikunja-cli = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = hasToken;
      description = "Install the vikunja CLI. Defaults to on wherever the agent's MCP config secret (omp-mcp) exists.";
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
        name = "vikunja";
        runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
        text = ''
          MCP_CONFIG="${osConfig.age.secrets.omp-mcp.path}"
          MCP_SERVER="${cfg.mcpServer}"

          usage() {
            printf '%s\n' \
              'usage:' \
              '  vikunja attach upload   <task-id> <file>' \
              '  vikunja attach download <task-id> <attachment-name> <out-path|->' \
              '  vikunja time start      <task-id> [comment]' \
              '  vikunja time stop' \
              '  vikunja time list       <task-id>' \
              "" \
              '<task-id> is the numeric "id" from MCP results, not the "#N" identifier.' \
              'attach upload refuses a name the task already has; download never overwrites.' \
              'attach download with "-" writes the bytes to stdout.' \
              'time start logs a running entry (end_time null); only one timer runs per user.' \
              'time stop ends the running timer, whichever task it belongs to.' \
              'exit: 0 ok, 1 config/API error, 2 usage, 3 conflict, 4 not found / no running timer'
          }

          die() {
            local code=$1
            shift
            printf 'vikunja: %s\n' "$*" >&2
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

          # Runs a request, leaving the body in RESP and the HTTP status in
          # STATUS. The Authorization header is fed on stdin (printf is a shell
          # builtin): the token never appears in argv, /proc, or any message.
          # Returns non-zero only when no response arrived at all.
          api() {
            local out
            STATUS=""
            RESP=""
            out=$(printf 'header = "Authorization: %s"\n' "$AUTH" \
              | curl --config - --silent --show-error "$@" -w '\n%{http_code}') || return 1
            STATUS=''${out##*$'\n'}
            RESP=''${out%$'\n'*}
          }

          # Dies on a non-2xx status. Auth failures get the route name instead
          # of Vikunja's always-identical "invalid token" body.
          check_http() {
            local route=$1
            case $STATUS in
              2??) return 0 ;;
              401 | 403)
                printf '%s\n' "$RESP" >&2
                die 1 "the API token is not permitted on $route; grant the $MCP_SERVER token that route on the board (Vikunja: Settings -> API Tokens -> routes)"
                ;;
              "")
                die 1 "$route: no HTTP response (network or TLS failure)"
                ;;
              *)
                printf '%s\n' "$RESP" >&2
                die 1 "$route failed with HTTP $STATUS"
                ;;
            esac
          }

          # api + status check in one step, for endpoints where every non-2xx
          # is an error. check_http always exits, so nothing follows it.
          call() {
            local route=$1
            shift
            api "$@" || check_http "$route"
            check_http "$route"
          }

          check_task() {
            local task=$1
            [[ $task =~ ^[0-9]+$ ]] || die 2 "task id must be the numeric id, got: $task"
            [[ $task -ne 0 ]] || die 2 "task id must not be 0"
          }

          # ── attach ─────────────────────────────────────────────────────────

          # Prints the ids of attachments on task $1 whose file name is exactly
          # $2, one per line, walking every page. Runs inside $(...), where
          # errexit does not apply, so every failure is handled explicitly.
          find_by_name() {
            local task=$1 name=$2 page=1 pages
            while :; do
              api "$BASE/tasks/$task/attachments?page=$page" || return 1
              [[ $STATUS == 2?? ]] || {
                printf '%s\n' "$RESP" >&2
                return 1
              }
              jq -r --arg n "$name" '.items[] | select(.file.name == $n) | .id' <<<"$RESP" || return 1
              pages=$(jq -er '.total_pages | numbers' <<<"$RESP") || return 1
              ((page >= pages)) && return 0
              page=$((page + 1))
            done
          }

          cmd_attach_upload() {
            [[ $# -eq 2 ]] || {
              usage >&2
              exit 2
            }
            local task=$1 file=$2 name ids res
            check_task "$task"
            [[ -f $file && -r $file ]] || die 2 "not a readable regular file: $file"
            # curl -F parses ; , and " inside the path; refuse instead of misreading.
            [[ $file != *[\;,\"]* ]] || die 2 "path must not contain ; , or a double quote: $file"
            name=$(basename -- "$file")
            load_config
            ids=$(find_by_name "$task" "$name") || die 1 "could not list attachments on task $task"
            [[ -z $ids ]] || die 3 "task $task already has an attachment named $name (id $(head -n1 <<<"$ids")); not uploading"
            call "POST /tasks/$task/attachments" --form "files=@$file" "$BASE/tasks/$task/attachments"
            res=$RESP
            # 201 even on partial failure: per-file errors live in the body.
            jq -e '((.errors // []) | length == 0) and ((.success // []) | length == 1)' <<<"$res" >/dev/null || {
              jq -r '(.errors // [])[] | .message' <<<"$res" >&2 || printf '%s\n' "$res" >&2
              die 1 "upload to task $task was rejected"
            }
            jq -c '.success[0] | {task: .task_id, attachment_id: .id, name: .file.name, size: .file.size}' <<<"$res"
          }

          cmd_attach_download() {
            [[ $# -eq 3 ]] || {
              usage >&2
              exit 2
            }
            local task=$1 name=$2 out=$3 dir ids n
            check_task "$task"
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
              die 1 "download of $name from task $task failed (no HTTP response)"
            fi
            if [[ $STATUS != 2?? ]]; then
              head -c 2000 -- "$TMP" >&2
              printf '\n' >&2
              die 1 "download of $name from task $task failed (HTTP $STATUS)"
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

          # ── time ───────────────────────────────────────────────────────────

          cmd_time_start() {
            [[ $# -ge 1 && $# -le 2 ]] || {
              usage >&2
              exit 2
            }
            local task=$1 comment=''${2:-} now body
            check_task "$task"
            load_config
            now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            body=$(jq -nc --argjson t "$task" --arg s "$now" --arg c "$comment" \
              '{task_id: $t, start_time: $s, end_time: null} + (if $c == "" then {} else {comment: $c} end)')
            call "POST /time-entries" -X POST -H 'Content-Type: application/json' --data "$body" "$BASE/time-entries"
            jq -ce '{task: .task_id, entry_id: .id, start_time: .start_time, running: (.end_time == null)}' <<<"$RESP" \
              || die 1 "unexpected response from POST /time-entries"
          }

          cmd_time_stop() {
            [[ $# -eq 0 ]] || {
              usage >&2
              exit 2
            }
            load_config
            api -X POST "$BASE/time-entries/timer/stop" \
              || check_http "POST /time-entries/timer/stop"
            [[ $STATUS == 404 ]] && die 4 "no timer is running for this user"
            check_http "POST /time-entries/timer/stop"
            jq -ce '{entry_id: .id, task: .task_id, start_time: .start_time, end_time: .end_time}' <<<"$RESP" \
              || die 1 "unexpected response from POST /time-entries/timer/stop"
          }

          cmd_time_list() {
            [[ $# -eq 1 ]] || {
              usage >&2
              exit 2
            }
            local task=$1
            check_task "$task"
            load_config
            call "GET /tasks/$task/time-entries" "$BASE/tasks/$task/time-entries?per_page=50"
            jq -ce '.items[] | {id, task: .task_id, start_time, end_time, running: (.end_time == null), comment}' <<<"$RESP" \
              || die 1 "unexpected response from GET /tasks/$task/time-entries"
          }

          BASE=""
          AUTH=""
          STATUS=""
          RESP=""
          TMP=""
          trap '[[ -z $TMP ]] || rm -f -- "$TMP"' EXIT

          # ── dispatch ───────────────────────────────────────────────────────

          case ''${1:-} in
            attach)
              shift
              case ''${1:-} in
                upload)
                  shift
                  cmd_attach_upload "$@"
                  ;;
                download)
                  shift
                  cmd_attach_download "$@"
                  ;;
                *)
                  usage >&2
                  exit 2
                  ;;
              esac
              ;;
            time)
              shift
              case ''${1:-} in
                start)
                  shift
                  cmd_time_start "$@"
                  ;;
                stop)
                  shift
                  cmd_time_stop "$@"
                  ;;
                list)
                  shift
                  cmd_time_list "$@"
                  ;;
                *)
                  usage >&2
                  exit 2
                  ;;
              esac
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
