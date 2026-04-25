#!/usr/bin/env bash
set -euo pipefail

MC_ALIAS="${MC_ALIAS:-rustfs}"
BUCKET="${SHARE_BUCKET:-shares}"
BASE_URL="${SHARE_BASE_URL:-https://files.john2143.com}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <path>

Upload a file or directory to RustFS under an unguessable UUID prefix
and print the public URL(s).

Options:
  -n, --name NAME   Override the destination name (default: basename of path)
  -i, --index       Generate an index.html for directory shares (default for dirs)
  -I, --no-index    Skip index.html generation for directory shares
  -h, --help        Show this help

Prerequisites (one-time):
  mc alias set $MC_ALIAS https://files.john2143.com \$USER \$PASSWORD
  mc mb $MC_ALIAS/$BUCKET
  mc anonymous set download $MC_ALIAS/$BUCKET

Revoking a share:
  mc rm --recursive --force $MC_ALIAS/$BUCKET/<uuid>/
EOF
  exit 0
}

generate_index() {
  local uuid="$1" name="$2"
  shift 2
  local files=("$@")

  cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$name</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 2rem auto; padding: 0 1rem; }
  h1 { font-size: 1.4rem; }
  ul { list-style: none; padding: 0; }
  li { padding: 0.3rem 0; }
  a { color: #0969da; text-decoration: none; }
  a:hover { text-decoration: underline; }
</style>
</head>
<body>
<h1>$name</h1>
<ul>
HTML

  for f in "${files[@]}"; do
    local display="${f#"$name/"}"
    echo "  <li><a href=\"$BASE_URL/$BUCKET/$uuid/$f\">$display</a></li>"
  done

  cat <<HTML
</ul>
</body>
</html>
HTML
}

dest_name=""
make_index=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)  dest_name="$2"; shift 2 ;;
    -i|--index) make_index="yes"; shift ;;
    -I|--no-index) make_index="no"; shift ;;
    -h|--help)  usage ;;
    --)         shift; break ;;
    -*)         echo "Unknown option: $1" >&2; exit 1 ;;
    *)          break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Error: no path provided" >&2
  usage
fi

src="$1"

if [[ ! -e "$src" ]]; then
  echo "Error: $src does not exist" >&2
  exit 1
fi

uuid="$(cat /proc/sys/kernel/random/uuid)"
name="${dest_name:-$(basename "$src")}"

if [[ -f "$src" ]]; then
  dest="$MC_ALIAS/$BUCKET/$uuid/$name"
  echo "Uploading file..."
  mc cp "$src" "$dest"
  echo ""
  echo "$BASE_URL/$BUCKET/$uuid/$name"

elif [[ -d "$src" ]]; then
  dest="$MC_ALIAS/$BUCKET/$uuid/$name/"
  echo "Uploading directory..."
  mc cp --recursive "$src" "$dest"

  # Collect relative paths for index generation
  uploaded=()
  while IFS= read -r line; do
    uploaded+=("$line")
  done < <(cd "$src" && find . -type f | sed 's|^\./||' | sort)

  prefixed=()
  for f in "${uploaded[@]}"; do
    prefixed+=("$name/$f")
  done

  if [[ "$make_index" != "no" ]]; then
    index_tmp="$(mktemp)"
    generate_index "$uuid" "$name" "${prefixed[@]}" > "$index_tmp"
    mc cp "$index_tmp" "$MC_ALIAS/$BUCKET/$uuid/index.html"
    rm -f "$index_tmp"
  fi

  echo ""
  if [[ "$make_index" != "no" ]]; then
    echo "$BASE_URL/$BUCKET/$uuid/index.html"
  fi
  echo "$BASE_URL/$BUCKET/$uuid/$name/"
  for f in "${uploaded[@]}"; do
    echo "  $BASE_URL/$BUCKET/$uuid/$name/$f"
  done
fi
