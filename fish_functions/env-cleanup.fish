# DESCRIPTION: Remove exported env vars not in the given snapshot
for _v in (set --names -x)
  if not contains $_v $argv
    set -e $_v
  end
end
