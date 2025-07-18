set -x EMAIL_NAME "john"
set -x EMAIL_DOMAIN "john2143.com"
set HOST (hostname -s)
set NIX false
if test "$HOST" = "office"
    set -x NIX true
end
if test "$HOST" = "closet"
    set -x NIX true
end
if test "$HOST" = "arch"
    set -x NIX true
end


if [ (uname) = "Linux" ]
    function screenshot_location
        date "+$HOME/screenshots/%Yy-%mm-%dd_%0Hh-%Mm-%Ss_.png"
    end

    set -g fish_user_paths "/home/john/.local/bin" $fish_user_paths
    set -g fish_user_paths "/opt/miniconda3/bin/" $fish_user_paths
    alias k="kubecolor"
    if $NIX
        alias nixi="nix-env -iA"
        alias nixq="nix-env -q"
        alias nixe="nix-env -e"

        alias en="fish -c 'cd ~/dotfiles/nixos/ ; nvim "$HOST"-configuration.nix'"
        alias enh="fish -c 'cd ~/dotfiles/nixos/ ; nvim "$HOST"-hardware-configuration.nix'"

        alias ens="fish -c 'cd ~/dotfiles/nixos/ ; nvim shared-cli-configuration.nix'"
        alias ensg="fish -c 'cd ~/dotfiles/nixos/ ; nvim shared-configuration.nix'"
        alias ehm="fish -c 'cd ~/dotfiles/nixos/ ; nvim home-cli.nix'"
        alias ehmg="fish -c 'cd ~/dotfiles/nixos/ ; nvim home.nix'"
        alias enf="fish -c 'cd ~/dotfiles/ ; nvim flake.nix'"

        alias build="sudo nixos-rebuild -v --flake ~/dotfiles"
        alias update="fish -c 'cd ~/dotfiles/; nix flake update'"
        alias optimize="fish -c 'sudo nix-collect-garbage --delete-older-than 14d; sudo nix-store --optimise; rfish'"

        alias pbcopy="wl-copy"
        alias pbpaste="wl-paste"
    else
        alias pbcopy="xclip -sel clip"
        alias pbpaste="xclip -sel clip -o"
        alias pp="paru"
        alias p="sudo pacman -Syu"
    end

    # >>> conda initialize >>>
    # !! Contents within this block are managed by 'conda init' !!
    alias gconda='eval /opt/miniconda3/bin/conda "shell.fish" "hook" $argv | source'
    # <<< conda initialize <<<
    alias ea="fish -c \"cd ~/ts/dotfiles/.config/; vim .\""
    alias ea2="fish -c \"cd ~/dotfiles/.config/; vim .\""

    alias oil="little_oil"

    alias cronerrors="sudo systemctl status cronie"
    alias ls=exa
end

if [ (uname) = "Darwin" ]
    source ~/scripts/disco.fish
    fish_add_path /opt/homebrew/bin/
    fish_add_path /opt/homebrew/sbin/
    fish_add_path /opt/homebrew/opt/openjdk/bin
    fish_add_path /Users/jschmidt/Downloads/jdt-language-server-1.20.0-202302161915/bin/
    fish_add_path ~/.docker/bin/
    source /Users/jschmidt/.docker/init-fish.sh || true # Added by Docker Desktop
    set -x EMAIL_NAME "john_schmidt"
    set -x EMAIL_DOMAIN "discovery.com"
    alias ea="fish -c \"cd ~/dotfiles/.config/; vim .\""
    alias lll="~/scripts/launch.fish; exit"
    alias ptt="pytest -m quick -n 5"
    alias ls=eza
end

alias lat="ls -la --tree"
alias lt="ls --tree"
alias la="ls -la"
alias ll="ls --long --group --header --git"

alias ask="ollama run llama3.2:latest"
alias askbig="ollama run llama3.1:70b"
alias askc="ollama run deepseek-coder-v2:latest"

alias fixfmt="fish -c 'cargo fix --allow-dirty --allow-staged; cargo fmt --all'"

if not $NIX
    alias nvm=fnm
    fnm env | source
end

bind \cq history-pager

set -x EMAIL "$EMAIL_NAME@$EMAIL_DOMAIN"
alias updatednode="npm i -g nyc rollup yarn neovim typescript pyright typescript-language-server"

alias recent="git for-each-ref --color='always' --sort=committerdate refs/heads --format='%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:magenta)%(authorname)%(color:reset)'|column -ts'|'"
alias recenta="git for-each-ref --color='always' --sort=committerdate --format='%(HEAD)%(color:yellow)%(refname:short)|%(color:bold green)%(committerdate:relative)|%(color:magenta)%(authorname)%(color:reset)'|column -ts'|'"
alias gb="git checkout (recent | nl | sort -nr | cut -f 2- | fzf --ansi | cut -d \" \" -f 2)"
alias gba="git checkout (recenta | nl | sort -nr | cut -f 2- | fzf --ansi | cut -d \" \" -f 2 | sed -e \"s/origin\\///g\")"

export EDITOR="nvim"

alias vim=nvim
alias vi=nvim
alias vimdiff="nvim -d"
alias cat=bat
alias grep=rg

alias sl=ls
alias rn="tmux rename-window (basename (pwd))"
alias rnn="tmux rename-window "

alias rally@="git diff HEAD --name-only | rally @"
alias rallyp="rally config project --set"
alias rallytags="ctags --fields=+l --languages=python --python-kinds=-iv -R -f ./tags ./**/silo-presets/"

alias launchdla="rally asset -e UAT --anon launch --job-name 'DLA Context Creator' --init-data "

alias efish="fish -c 'cd ~/dotfiles/.config/fish/; vim config.fish; rfish'"
alias ehypr="fish -c 'cd ~/dotfiles/.config/hypr/; vim hyprland.conf'; hyprctl reload"
alias eprompt="vim ~/dotfiles/.config/starship.toml"
alias exprofile="vim ~/dotfiles/.xprofile.fish"
alias etmux="vim ~/dotfiles/.tmux.conf"
alias rfish="source ~/dotfiles/.config/fish/config.fish"
# alias ath="alacritty-themes"
# alias ebinds="vim ~/.config/sxhkd/sxhkdrc; rbinds"
# alias rbinds="pkill -USR1 -x sxhkd"

alias note="fish -c 'cd ~/Work/ ; vim ~/Work/Periodic/Daily/(date \"+%Y-%m-%d\").md'"
alias notep="fish -c 'cd ~/Personal/ ; vim ~/Personal/Periodic/Daily/(date \"+%Y-%m-%d\").md'"

alias a8=". ./venv/bin/activate.fish"
alias ctx="awsctx -g | ."

set -x CARGO_UNSTABLE_SPARSE_REGISTRY "true"

function d
    daily $argv | bash
end

complete -c d -f
complete -c d -a "(ls -D ~)"
complete --command aws --no-files --arguments '(begin; set --local --export COMP_SHELL fish; set --local --export COMP_LINE (commandline); aws_completer | sed \'s/ $//\'; end)'

alias tmux_daily="daily \
    ONRAMP_WORKFLOW_PYTHON:OWR:n \
    node-rally-tools:rt:cd \
    rally-congere:congere:cd \
    cjarvis-api:cj-api:cd \
    unified-qc-ui:cj-ui:n \
    :vault:n \
| tail -n +2"

alias vpnip='mullvad status | rg \'(\d[^ ]+):\' -o -r \'$1\' --color=never'
alias watchleaks="sudo tcpdump -n -i 1 '(not host ' (vpnip) 'and not net 192.168.1.0/24 and not net 169.254.0.0/16)' | grep IP"

set fish_greeting

fish_add_path "$HOME/bin"
fish_add_path "$HOME/.cargo/bin"
fish_add_path "$HOME/go/bin/"

set -x HOMEBREW_NO_AUTO_UPDATE 1
set BAT_THEME "Solarized (dark)"

# git config --global user.email $EMAIL > /dev/null

bind \u2022 'backward-kill-bigword'

set -g fish_user_paths "/usr/local/sbin" $fish_user_paths

starship init fish | source

[ -f ~/.inshellisense/key-bindings.fish ] && source ~/.inshellisense/key-bindings.fish


if [ (uname) = "Linux" ]
    # if we are tty 1
    if [ (tty) = "/dev/tty1" ];
        # and hyprland is not running (the search will count itsself in ps so add +1)
        if [ (ps aux | grep Hyprland | wc -l) = "1" ];
            if test "$HOST" = "office"
                # Hyprland &;
            end
        end
    end
end
