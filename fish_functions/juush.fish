# DESCRIPTION: Upload a file to juush and get a short URL
set -l _pre_vars (set --names -x)
set -l creds_file /run/agenix/rustfs-credentials
if test -f $creds_file
  envsource $creds_file
end
bash ~/dotfiles/.config/juush.bash $argv
env-cleanup $_pre_vars
