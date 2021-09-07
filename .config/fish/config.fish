alias recent="git for-each-ref --color='always' --sort=committerdate refs/heads --format='%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:blue)%(subject)|%(color:magenta)%(authorname)%(color:reset)'|column -ts'|'"
export EDITOR="nvim"

alias vim=nvim
alias vi=nvim
alias vimdiff="nvim -d"
alias cat=bat
alias ls=exa
alias grep=rg

alias rally@="git diff HEAD --name-only | rally @"
alias rallyp="rally config project --set"
alias rallytags="ctags --fields=+l --languages=python --python-kinds=-iv -R -f ./tags ./**/silo-presets/"

alias launchdla="rally asset -e UAT --anon launch --job-name 'DLA Context Creator' --init-data "

alias efish="vim ~/.config/fish/config.fish"

set fish_greeting

set PATH "$HOME/bin:$PATH"
set PATH "$HOME/.cargo/bin:$PATH"

set BAT_THEME "Solarized (dark)"

set SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')

git config --global user.signingkey $SIGNING_KEY

bind \u2022 'backward-kill-bigword'

set -g fish_user_paths "/usr/local/sbin" $fish_user_paths


#nvm use node > /dev/null
