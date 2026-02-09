{
  config,
  inputs,
  pkgs,
  lib,
  pkgs-stable,
  ...
}:

let
  vimPluginFromGithub =
    repo: rev:
    pkgs.vimUtils.buildVimPlugin {
      pname = "${lib.strings.sanitizeDerivationName repo}";
      version = "HEAD";
      src = builtins.fetchGit {
        url = "https://github.com/${repo}.git";
        ref = "HEAD";
        rev = rev;
      };
    };
in
{
  _module.args.pkgs-stable = import inputs.nixpkgs-stable {
    inherit (pkgs.stdenv.hostPlatform) system;
    inherit (config.nixpkgs) config;
  };

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
    udiskie # disks
    # neovim

    # cli
    bat # cat replacement
    eza # ls replacement
    ripgrep # grep replacement
    btop # btop++ > bpytop > htop > top
    choose # awk replacement
    dust # df/du replacement
    ncdu # du / disk usage
    fzf
    fd # find replacement
    #update-nix-fetchgit # update fetchgit urls
    yt-dlp # youtube-dl
    delta # pager
    gptfdisk # disk partitioning tool
    killall # like pkill
    gh # github
    timg # image viewer
    jq
    unzip
    unrar
    systemctl-tui
    dive
    bind # network utilities

    # k8s
    # kubectl # from k3s
    kubecolor # kubectl color
    k9s
    k3s

    direnv # nixos env manager: see also (direnv hook fish)
    # clang # compiler
    # rustup # rust compiler
    # bacon # rust build tool
    cargo-generate # rust project generator

    # screenshots
    file # file info

    # embedded programming
    # gcc-arm-embedded # arm compiler
    # openocd # open debugger
    # probe-rs # rust <-> stm32
    # stlink # stm32 programmer
    # stm32cubemx # stm32 ide
    # kicad # PCB Hardware Layout

    # Other / unsorted
    # kubernetes-helm
    nodejs
    nodePackages."@tailwindcss/language-server" # tailwindcss language server for neovim
    nodePackages.yaml-language-server # yaml language server for neovim

    localsend
    fastfetch
    distrobox
    # sage
    nh
    nixd
    postgresql_17 # need psql and stuff
    trash-cli # bound to "rmm"
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    ".vimrc".source = ../.vimrc;

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
      eval (direnv hook fish)
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
        set procs (ps aux | grep $appname | grep -v "0:00 rg" | choose 1)
        set num_procs (echo $procs | wc -l)

        # Echo to stderr so that other scripts can use this command
        echo 1>&2 "Ignoring $appname ($num_procs matches)";
        for pid in $procs;
            echo -n "Split-tunneling $pid ... ";
            mullvad split-tunnel add $pid;
        end
        echo 1>&2 "Done"
      '';
      test-program.body = ''
        set -f program "$argv[1]"
        mkdir -p ~/test/$program
        cd ~/test/$program
        nix flake init --template templates#rust
        nix-shell -p cargo --command "cargo init . --bin --name $program"
        nix-shell -p cargo --command "cargo b"
        echo "/result" >> .gitignore
        echo ".direnv" >> .gitignore
        git add -A
        nix build .
        ./result/bin/$program
        direnv allow
        git add -A
        git commit -m "Initial commit"
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
      #resurrect
      continuum
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
      # use fake shaHash for initial checkout
      (vimPluginFromGithub "derekwyatt/vim-fswitch" "94acdd8bc92458d3bf7e6557df8d93b533564491")
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
      (vimPluginFromGithub "mihaifm/bufstop" "9ae087c74e3f184192c55c8d6bbba3a33e1d8dd6")
      (vimPluginFromGithub "dmmulroy/ts-error-translator.nvim" "47e5ba89f71b9e6c72eaaaaa519dd59bd6897df4")

      lightline-vim

      # " Images in terminal?
      # " Plug 'edluffy/hologram.nvim'

      # Plug 'AndrewRadev/linediff.vim'
      vimspector
      # Plug 'sagi-z/vimspectorpy', { 'do': { -> vimspectorpy#update() } }

      # " :Tab
      # tabular

      ctrlp-vim

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
      vim-colors-solarized
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

      nvim-highlight-colors

      plenary-nvim
      crates-nvim

      copilot-vim

      refactoring-nvim
      plenary-nvim
      rustaceanvim
      vim-which-key
      #(vimPluginFromGithub "frankroeder/parrot.nvim" "c992483dd0cf9d7481b55714d52365d1f7a66f91")
    ];
  };

  programs.git = {
    enable = true;
    settings = {
      user = {
        email = "john@john2143.com";
        name = "John Schmidt";
        signingkey = "/home/john/.ssh/id_github_sign.pub";
      };
      gpg = {
        format = "ssh";
      };
      push = {
        default = "current";
      };
      color = {
        ui = "always";
      };
      alias = {
        tree = "log --oneline --decorate --all --graph";
        hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";

        co = "checkout";
        cod = "checkout develop";
        com = "checkout master";
        coa = "checkout main";
        cos = "checkout staging";

        bb = "checkout -t -b";
        br = "branch";

        s = "status";
        st = "status";
        sts = "status -s";
        ss = "status -s";

        mf = "merge --no-ff";

        adl = "add -A";

        ci = "commit -S";
        cim = "commit -S -m";
        cia = "commit -S -a";
        ciam = "commit -S -a -m";
        caim = "commit -S -a -m";
        cima = "commit -S --amend -m";

        pushb = "push -u origin HEAD";
        psuh = "push";

        dh = "diff HEAD";

        ignore = "!nvim .git/info/exclude";
        unignore = "update-index --no-assume-unchanged";
        ignored = "git ls-files -v | grep '^[[:lower:]]'";
      };
      url = {
        "git@github.com" = {
          insteadOf = "gh";
        };
      };
      core = {
        #excludesfile = "/Users/jschmidt/.gitignore";
        pager = "delta";
      };
      pull = {
        ff = "only";
      };
      merge = {
        tool = "nvimdiff";
        conflictstyle = "zdiff3";
      };
      rerere = {
        enabled = true;
      };
      column = {
        ui = "auto";
      };
      branch = {
        sort = "-committerdate";
      };
      commit = {
        verbose = true;
        gpgsign = true;
      };
      tag = {
        gpgsign = true;
      };
    };
  };

## # https://starship.rs/config
## "$schema" = 'https://starship.rs/config-schema.json'
## format = """
## $shell$time\
## $username$hostname\
## $directory$nix_shell\
## $git_branch$git_commit$git_state$git_status\
## $python\
## $kubernetes\
## $aws\
## $status$cmd_duration$jobs\
## $line_break\
## $character
## """
## 
## #add_newline = true
## 
## # Replace the '❯' symbol in the prompt with '➜'
## [character] # The name of the module we are configuring is 'character'
## success_symbol = '[\$](bold green)' # The 'success_symbol' segment is being set to '➜' with the color 'bold green'
## error_symbol = '[\$](bold red)' # The 'success_symbol' segment is being set to '➜' with the color 'bold green'
## vimcmd_symbol = '[\$](bold white bg:#ff1493)' 
## 
## [directory]
## truncation_length = 3
## truncate_to_repo = false
## fish_style_pwd_dir_length = 2
## style = "green"
## 
## [git_branch]
## format = '[$symbol$branch(:$remote_branch)]($style)'
## style = 'purple'
## ignore_branches = []
## #symbol = ' '
## symbol = ''
## 
## [git_commit]
## format = '[#$hash$tag]($style) '
## tag_symbol = ''
## style = 'purple'
## 
## [git_status]
## style = 'purple'
## stashed = ''
## 
## [hostname]
## ssh_only = false
## format = '[@](fg:#666666)[$hostname](bold white) '
## trim_at = ''
## 
## [status]
## format = '[$status](bold red) '
## disabled = false
## 
## [username]
## style_user = 'bold white'
## format = '[$user]($style)'
## show_always = true
## 
## [python]
## format = '([🐍](yellow)[$virtualenv]($style) )'
## style = "cyan"
## 
## [shell]
## disabled = true
## fish_indicator = ''
## format = '[$indicator ]($style)'
## 
## [cmd_duration]
## format = '[$duration]($style) '
## min_time = 5000
## 
## [jobs]
## number_threshold = 1
## 
## [time]
## disabled = false
## style = "fg:#777777"
## format = '[$time]($style) '
## 
## [nix_shell]
## format = '[$symbol$state]($style) '
## #symbol = '❄️'
## symbol = '*'
## style = 'bold blue'
## impure_msg = ''
## pure_msg = ''
## unknown_msg = ''
## 
## 
## [kubernetes]
## format = '[⛵$context](dimmed cyan) '
## disabled = false
## 
## [aws]
## format = '[$symbol($profile )(\($region\) )]($style)'
## style = 'bold blue'
## symbol = ''#'🅰 '
## [aws.region_aliases]
## us-east-1 = 'ue1'
## [aws.profile_aliases]
## "wbd-syndication-dev-/wbd-syndication-developer" = 'wbd-synd-dev'
## "aws-aio-eks-poc2-/AWSAdmin" = 'eks-poc2'
## "aws-aio-eks-poc1-/AWSAdmin" = 'eks-poc1'
## "wbd-ms-rally-dev-/ms-rally-developer" = 'ms-rally-dev'
## 
## 
## [[kubernetes.contexts]]
## context_pattern = "kind-(?P<cluster>.+)"
## context_alias = "kind-$cluster"
## 
## [[kubernetes.contexts]]
## context_pattern = "(?P<cluster>[\\w-]+):(?P<account>\\d+):(?P<name>[\\w-]+)"
## context_alias = "aws-$cluster"
## 
## [[kubernetes.contexts]]
## context_pattern = "default"
## context_alias = "home"
## 
## #[[kubernetes.contexts]]
## #context_pattern = ".+"
## #context_alias = "yipee"
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      format = "$shell$time$username$hostname$directory$nix_shell$git_branch$git_commit$git_state$git_status$python$kubernetes$aws$status$cmd_duration$jobs$line_break$character";
        character = {
            success_symbol = "[\\$](bold green)";
            error_symbol = "[\\$](bold red)";
            vimcmd_symbol = "[\\$](bold white bg:#ff1493)";
        };
        directory = {
            truncation_length = 3;
            truncate_to_repo = false;
            fish_style_pwd_dir_length = 2;
            style = "green";
        };
        git_branch = {
            format = "[$symbol$branch(:$remote_branch)]($style)";
            style = "purple";
            ignore_branches = [ ];
            symbol = "";
        };
        git_commit = {
            format = "[#$hash$tag]($style) ";
            tag_symbol = "";
            style = "purple";
        };
        git_status = {
            style = "purple";
            stashed = "";
        };
        hostname = {
            ssh_only = false;
            format = "[@](fg:#666666)[$hostname](bold white) ";
            trim_at = "";
        };
        status = {
            format = "[$status](bold red) ";
            disabled = false;
        };
        username = {
            style_user = "bold white";
            format = "[$user]($style)";
            show_always = true;
        };
        python = {
            format = "([🐍](yellow)[$virtualenv]($style) )";
            style = "cyan";
        };
        shell = {
            disabled = true;
            fish_indicator = "";
            format = "[$indicator ]($style)";
        };
        cmd_duration = {
            format = "[$duration]($style) ";
            min_time = 5000;
        };
        jobs = {
            number_threshold = 1;
        };
        time = {
            disabled = false;
            style = "fg:#777777";
            format = "[$time]($style) ";
        };
        nix_shell = {
            format = "[$symbol$state]($style) ";
            symbol = "*";
            style = "bold blue";
            impure_msg = "";
            pure_msg = "";
            unknown_msg = "";
        };
        kubernetes = {
            format = "[⛵$context](dimmed cyan) ";
            disabled = false;
        };
        aws = {
            format = "[$symbol($profile )(\($region\) )]($style)";
            style = "bold blue";
            symbol = "";
            region_aliases = {
              "us-east-1" = "ue1";
            };
            profile_aliases = {
              "wbd-syndication-dev-/wbd-syndication-developer" = "wbd-synd-dev";
              "aws-aio-eks-poc2-/AWSAdmin" = "eks-poc2";
              "aws-aio-eks-poc1-/AWSAdmin" = "eks-poc1";
              "wbd-ms-rally-dev-/ms-rally-developer" = "ms-rally-dev";
            };
        };
      };
    };
}
