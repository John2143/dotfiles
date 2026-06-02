# DESCRIPTION: Convert Markdown file to PDF via pandoc → Typst → PDF pipeline
if test (count $argv) -lt 1
  echo "Usage: md2pdf <file.md>" >&2
  return 1
end
set -l input "$argv[1]"
if not test -f "$input"
  echo "File not found: $input" >&2
  return 1
end
set -l base (basename "$input" .md)
pandoc "$input" -t typst | sed 's/#horizontalrule/---/' > "$base.typ"
typst compile "$base.typ" "$base.pdf"
rm "$base.typ"
echo "→ $base.pdf"
