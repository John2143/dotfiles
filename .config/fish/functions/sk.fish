function sk --description 'update my github signing key'
    set -x SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep $EMAIL -B 3 | grep "(work|github|disco|1E7452EAEE)" -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')
    git config --global user.signingkey $SIGNING_KEY > /dev/null
end
