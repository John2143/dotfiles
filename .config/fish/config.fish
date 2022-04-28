alias recent="git for-each-ref --color='always' --sort=committerdate refs/heads --format='%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:magenta)%(authorname)%(color:reset)'|column -ts'|'"
alias recenta="git for-each-ref --color='always' --sort=committerdate --format='%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:magenta)%(authorname)%(color:reset)'|column -ts'|'"
alias gb="git checkout (recent | nl | sort -nr | cut -f 2- | fzf --ansi | cut -d \" \" -f 2)"
alias gba="git checkout (recenta | nl | sort -nr | cut -f 2- | fzf --ansi | cut -d \" \" -f 2 | tr '/' '\n' | tail -n 1)"

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

alias efish="vim ~/.config/fish/config.fish ; rfish"
alias rfish="source ~/.config/fish/config.fish"
alias ath="alacritty-themes"
alias nn="nvm use node"

function d
    daily $argv | bash
end

complete -c d -f
complete -c d -a "(ls -D ~)"

set fish_greeting

set PATH "$HOME/bin:$PATH"
set PATH "$HOME/.cargo/bin:$PATH"
set -x HOMEBREW_NO_AUTO_UPDATE 1
set BAT_THEME "Solarized (dark)"

set SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep john@john2143 -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')

git config --global user.signingkey $SIGNING_KEY > /dev/null

bind \u2022 'backward-kill-bigword'

set -g fish_user_paths "/usr/local/sbin" $fish_user_paths

if [ (uname) = "Linux" ]
    #nvm use node > /dev/null
    alias p="paru"
end
