if [ (uname) = "Linux" ]
    set -g fish_user_paths "/home/john/.local/bin" $fish_user_paths
    set -g fish_user_paths "/opt/miniconda3/bin/" $fish_user_paths
    alias p="paru"
    if [ $TMUX ]
        set -x DISPLAY ":0"
    end

    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    alias gconda='eval /opt/miniconda3/bin/conda "shell.fish" "hook" $argv | source'
    # <<< conda initialize <<<
end
if [ (uname) = "Darwin" ]
    source ~/scripts/disco.fish
    alias updatednode="npm i -g nyc rollup yarn neovim typescript pyright typescript-language-server"
    fish_add_path /opt/homebrew/bin/
    fish_add_path /opt/homebrew/sbin/
    source /Users/jschmidt/.docker/init-fish.sh || true # Added by Docker Desktop
end

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
alias nvm=fnm

alias rally@="git diff HEAD --name-only | rally @"
alias rallyp="rally config project --set"
alias rallytags="ctags --fields=+l --languages=python --python-kinds=-iv -R -f ./tags ./**/silo-presets/"

alias launchdla="rally asset -e UAT --anon launch --job-name 'DLA Context Creator' --init-data "

alias efish="vim ~/.config/fish/config.fish ; rfish"
alias eprompt="vim ~/.config/starship.toml"
alias rfish="source ~/.config/fish/config.fish"
alias ath="alacritty-themes"
alias nn="nvm use node"

set -x CARGO_UNSTABLE_SPARSE_REGISTRY "true"

function d
    daily $argv | bash
end

complete -c d -f
complete -c d -a "(ls -D ~)"

alias tmux_daily="daily \
    ONRAMP_WORKFLOW_PYTHON:OWR:n \
    node-rally-tools:rt:cd \
    rally-congere:congere:cd \
    :vault:n \
| tail -n +2"

alias vpnip='mullvad status | rg \'(\d[^ ]+):\' -o -r \'$1\' --color=never'
alias watchleaks="sudo tcpdump -n -i 1 '(not host ' (vpnip) 'and not net 192.168.1.0/24 and not net 169.254.0.0/16)' | grep IP"

set fish_greeting

fish_add_path "$HOME/bin"
fish_add_path "$HOME/.cargo/bin"

fnm env | source
set -x HOMEBREW_NO_AUTO_UPDATE 1
set BAT_THEME "Solarized (dark)"

set SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep john@john2143 -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')

git config --global user.signingkey $SIGNING_KEY > /dev/null

bind \u2022 'backward-kill-bigword'

set -g fish_user_paths "/usr/local/sbin" $fish_user_paths

starship init fish | source
