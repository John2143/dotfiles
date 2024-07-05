{ config, pkgs, lib, ... }:

let
  fromGitHub = ref: repo: pkgs.vimUtils.buildVimPlugin {
    pname = "${lib.strings.sanitizeDerivationName repo}";
    version = ref;
    src = builtins.fetchGit {
      url = "https://github.com/${repo}.git";
      ref = ref;
    };
  };
in

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "john";
  home.homeDirectory = "/home/john";

  nixpkgs.config = {
    allowUnfree = true;
  };

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    firefox # browser

    # graphical
    hyprland
    waybar # status bar
    wofi # "start menu" / program browser
    dolphin # file browser
    alacritty # terminal

    mullvad-vpn # vpn

    wl-clipboard # copy-paste via cli
    nerdfonts # fonts, idk how many this is
    jetbrains-mono # font


    udiskie # disks
    # neovim

    # cli
    starship #prompt
    bat # cat replacement
    eza # ls replacement
    ripgrep # grep replacement
    # btop # btop++ > bpytop > htop > top
    choose # awk replacement
    du-dust # df/du replacement
    fzf

    gh # github

    pulseaudio # pactl

    # k8s
    kubectl
    k9s

    # fnm # node version manager # TODO switch to nixos
    clang # compiler
    rustup # rust compiler

    # screenshots
    slurp
    grim
    file
    bind

    # Other / unsorted
    pwvucontrol
    cliphist
    wl-clipboard-x11
    dunst
    libnotify
    gthumb

    spotifyd
    gammastep
    killall


    amdgpu_top
    bacon
    cargo-generate
    fd
    gcc-arm-embedded
    hyprlock
    mpv
    openocd
    probe-rs
    spotify
    stlink

    temurin-jre-bin-21
    wine-wayland


    stm32cubemx
    kicad

    chatgpt-cli
    plex-media-player
    normcap
    prismlauncher
  ];

  xdg.configFile = {
    "alacritty".source = config.lib.file.mkOutOfStoreSymlink ../.config/alacritty;
    "dunst".source = config.lib.file.mkOutOfStoreSymlink ../.config/dunst;
    "hypr".source = config.lib.file.mkOutOfStoreSymlink ../.config/hypr;
    "waybar".source = config.lib.file.mkOutOfStoreSymlink ../.config/waybar;

    "get_sunset.fish".source = config.lib.file.mkOutOfStoreSymlink ../.config/get_sunset.fish;
    "starship.toml".source = config.lib.file.mkOutOfStoreSymlink ../.config/starship.toml;
  };

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    ".vimrc".source = ../.vimrc;
    # ".tmux.conf".source = /home/john/dotfiles/.tmux.conf;
    # ".gitconfig".source = ../.gitconfig;
    ".xprofile.fish".source = ../.xprofile.fish;
    ".xprofile".source = ../.xprofile;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/john/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.fish = {
    enable = true;
    shellInit = builtins.readFile ../.config/fish/config.fish;
    interactiveShellInit = ''
      function __get_program_names
          ps aux | choose 10 | sort | uniq
      end

      complete -r -c mullvad-split-tunnel -a "(__get_program_names)"
    '';
    functions = {
      hostname.body = "/usr/bin/env cat /etc/hostname";
      kc.body = ''
        set -f new_env (kubectl config get-contexts -o name | fzf)
        if test "A$new_env" = "A"
            exit 1
        end
        kubectl config use-context $new_env
      '';
      mullvad-split-tunnel.body = ''
        set appname "$argv[1]";
        set procs (ps aux | grep $appname | grep -v "0:00 rg" | choose 0)
        set num_procs (echo $procs | wc -l)

        # Echo to stderr so that other scripts can use this command
        echo 1>&2 "Ignoring $appname ($num_procs matches)";
        for pid in $procs;
            echo -n "Split-tunneling $pid ... ";
            mullvad split-tunnel add $pid;
        end
        echo 1>&2 "Done"
      '';
      replace-all.body = ''
        set -f find $argv[1]
        set -f rep $argv[2]
        set -f filter $argv[3]
        if test $filter
            echo "Replacing /$find/ with /$rep/ with extra $filter"
            rg --files-with-matches $filter | rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
        else
            echo "Replacing /$find/ with /$rep/"
            rg $find --files-with-matches | xargs sed -i "s/$find/$rep/g"
        end
      '';
      sk.body = ''
        set -x SIGNING_KEY (gpg --list-secret-keys --keyid-format long | grep $EMAIL -B 3 | grep "(work|github|disco|1E7452EAEE)" -B 3 | grep sec | string split "/" | tail -n 1 | string match -r '[0-9A-F]+')
        echo "Set Signing key to $SIGNING_KEY"
        git config --global user.signingkey $SIGNING_KEY > /dev/null
      '';
      envsource.body = ''
        set -f envfile "$argv"
        if not test -f "$envfile"
            echo "Unable to load $envfile"
            return 1
        end
        while read line
            if not string match -qr '^#|^$' "$line" # skip empty lines and comments
                if string match -qr '=' "$line" # if `=` in line assume we are setting variable.
                    set item (string split -m 1 '=' $line)
                    set item[2] (eval echo $item[2]) # expand any variables in the value
                    set -gx $item[1] $item[2]
                    echo "Exported key: $item[1]" # could say with $item[2] but that might be a secret
                else
                    eval $line # allow for simple commands to be run e.g. cd dir/mamba activate env
                end
            end
        end < "$envfile"
      '';
    };
    plugins = [
    ];
  };

  programs.tmux = {
    enable = true;
    extraConfig = builtins.readFile ../.tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      tmux-colors-solarized
      # tokyo-night-tmux
      catppuccin
      # tmux-battery
      vim-tmux-navigator
      # set -g @plugin 'tmux-plugins/tmux-sensible'
      # set -g @plugin 'seebi/tmux-colors-solarized'
      # #set -g @plugin 'janoamaral/tokyo-night-tmux'
      # set -g @plugin 'catppuccin/tmux'
      # set -g @plugin 'tmux-plugins/tmux-battery'
      # set -g @plugin 'christoomey/vim-tmux-navigator'
    ];
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      source ~/.vimrc

      " yramagicman on reddit:
      " https://www.reddit.com/r/neovim/comments/qh7f3u/fzf_integration_on_nix_os_solution/
      function! NixosPluginPath()
        let seen = {}
        for p in reverse(split($NIX_PROFILES))
            for d in split(glob(p . '/share/vim-plugins/*'))
                let pluginname = substitute(d, ".*/", "", "")
                if !has_key(seen, pluginname)
                    exec 'set runtimepath^='.d
                    let after = d."/after"
                    if isdirectory(after)
                        exec 'set runtimepath^='.after
                    endif
                    let seen[pluginname] = 1
                endif
            endfor
        endfor
      endfunction
      execute NixosPluginPath()
    '';
    plugins = with pkgs.vimPlugins; [
      nvim-lspconfig
      nvim-treesitter.withAllGrammars
      # Plug 'easymotion/vim-easymotion'
      vim-easymotion
      # " niche things I use once a year
      vim-surround
      vim-fugitive
      vim-abolish
      # " useful for a work specific setup (metadata files + source files)
      # (fromGitHub "HEAD" "derekwyatt/vim-fswitch")
      # " <leader>c<Space> is the only thing I know about this but it sure does work
      nerdcommenter
      # " not sure what these two do /exactly/ just know they work
      # rust.vim
      webapi-vim

      nvim-treesitter
      # " silent but deadly
      vim-rooter
      # " kinda don't like this but I keep it around
      # vim-json
      # " better than the default, worse than fzf for browsing stuff
      nerdtree
      # " just syntax highlighting for vue/js/c
      vim-vue
      vim-javascript
      # TagHighlight
      # " fish told me to use this
      vim-fish
      # " useful for self-interrogation
      blamer-nvim
      # " make my tab do something useful when theres no LSP
      # " NOTE: don't use with neovim
      # "let g:neocomplete#enable_at_startup = 1
      # "Plug 'Shougo/neocomplete.vim'
      # "Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }

      # Plug 'mihaifm/bufstop'

      lightline-vim

      # " Images in terminal?
      # " Plug 'edluffy/hologram.nvim'

      # Plug 'AndrewRadev/linediff.vim'
      vimspector
      # Plug 'sagi-z/vimspectorpy', { 'do': { -> vimspectorpy#update() } }

      # " :Tab
      # tabular

      ctrlp

      # " allows ctrl hjkl to work between both vim and tmux (also install tmux plugin)
      vim-tmux-navigator

      # " file explorer (:NvimTreeToggle)
      nvim-tree-lua

      # " fzf is very cool. Use a LOT of [:Files, :Buf, :Rg]
      # if has("mac")
      #     set rtp+=/usr/local/opt/fzf
      # end
      # Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
      # Plug 'junegunn/fzf.vim'
      fzf-vim

      # " colorschemes
      # Plug 'altercation/vim-colors-solarized'
      solarized
      sonokai
      gruvbox-material
      base16-vim
      vim-gruvbox8
      tokyonight-nvim
      catppuccin-nvim

      # " rainbow parens
      {
        plugin = rainbow;
        config = "let g:rainbow_active = 1";
      }

      # " Semantic language support
      nvim-lspconfig
      lsp_extensions-nvim
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      nvim-cmp
      lsp_signature-nvim
      # " Only because nvim-cmp _requires_ snippets
      cmp-vsnip
      vim-vsnip
      # " Syntactic language support
      vim-toml
      vim-yaml
      rust-vim
      vim-clang-format
      nvim-jdtls
      # if has("mac")
      #     Plug 'tpope/vim-dispatch'
      #     Plug 'Shougo/vimproc.vim', {'do' : 'make'}
      #     Plug 'OmniSharp/omnisharp-vim' " c#
      #     let g:OmniSharp_selector_ui = 'fzf'
      #     let g:OmniSharp_server_stdio = 1
      #     let g:OmniSharp_popup = 0
      #     "let g:OmniSharp_server_path = 
      # endif
      vim-go
      vim-markdown
      lsp-status-nvim

      plenary-nvim
      null-ls-nvim
      crates-nvim

      copilot-vim

    ];
  };
}
