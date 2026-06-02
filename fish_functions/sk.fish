# DESCRIPTION: Set the GPG signing key for git commits
set -x SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep $EMAIL -B 3 | grep "(work|github|disco|1E7452EAEE)" -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')
echo "Set Signing key to $SIGNING_KEY"
git config --global user.signingkey $SIGNING_KEY > /dev/null
