# DESCRIPTION: Convert Markdown file to self-contained HTML with water.css styling
if test (count $argv) -lt 1
  echo "Usage: md2html <file.md>" >&2
  return 1
end
set -l input "$argv[1]"
if not test -f "$input"
  echo "File not found: $input" >&2
  return 1
end
set -l output (basename "$input" .md).html
pandoc "$input" -s --embed-resources --standalone \
  -c https://cdn.jsdelivr.net/npm/water.css@2/out/water.min.css \
  -o "$output"
echo "→ $output"
