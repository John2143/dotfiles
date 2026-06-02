# DESCRIPTION: Upload files to RustFS and get public share links
set -l creds_file /run/agenix/rustfs-credentials
if not test -f $creds_file
  echo "Error: RustFS credentials not found at $creds_file" >&2
  return 1
end
set -l _pre_vars (set --names -x)
envsource $creds_file
mc alias set rustfs https://files.john2143.com $RUSTFS_USER $RUSTFS_PASSWORD 2>/dev/null
bash ~/dotfiles/.config/nas-share.sh $argv
env-cleanup $_pre_vars
