# Archive every new EFI pstore crash record and announce it.
# ARCHIVE_DIR, NOTIFY and PSTOREDIR are injected by crash-capture.nix.
set -eu

install -d -m 0755 "$ARCHIVE_DIR"

new=0
sig=""
for d in "$PSTOREDIR"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  # Already archived: never re-copy, never overwrite the pristine record.
  if [ -e "$ARCHIVE_DIR/$name" ]; then
    continue
  fi

  cp -a "$d" "$ARCHIVE_DIR/$name"
  # systemd-pstore leaves these root-only; make them readable for the owner.
  chmod -R a+rX "$ARCHIVE_DIR/$name" 2>/dev/null || true
  new=$((new + 1))

  # The lines that identify a crash; drop the amdgpu queue-eviction and
  # split-lock spam that dominates this box's ring buffer.
  line=$(
    grep -hE 'BUG: |Kernel panic|Oops:|RIP: 0010|Comm: |Hardware name:|not-present page' \
      "$ARCHIVE_DIR/$name"/*/dmesg.txt 2>/dev/null |
      grep -vE 'Freeing queue|split_lock' |
      head -6 | tr '\n' ' ' | cut -c1-600 || true
  )
  if [ -n "$line" ]; then
    sig="${sig}${name}: ${line}
"
  fi
done

if [ "$new" -eq 0 ]; then
  echo "pstore-archive: no new records"
  exit 0
fi

echo "pstore-archive: archived $new new record(s) under $ARCHIVE_DIR"
if [ -n "$sig" ]; then
  printf '%s' "$sig"
fi

if [ "$NOTIFY" = "1" ] && [ -r /run/agenix/ntfy-topic-url ]; then
  set -a
  # Runtime secret, not a build input.
  # shellcheck disable=SC1091
  . /run/agenix/ntfy-topic-url
  set +a
  body=${sig:-"crash record archived under $ARCHIVE_DIR"}
  if [ -z "${NTFY_TOPIC_URL:-}" ]; then
    echo "pstore-archive: ntfy-topic-url secret has no NTFY_TOPIC_URL"
  else
    curl -fsS -m 20 \
      -H "Title: kernel crash on $(hostname)" \
      -H "Priority: max" -H "Tags: skull" \
      -d "$(printf '%s\n%s' "$body" "records: $ARCHIVE_DIR")" \
      "$NTFY_TOPIC_URL" || echo "pstore-archive: ntfy push failed (record is on disk)"
  fi
fi
