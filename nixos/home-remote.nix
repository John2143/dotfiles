{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./modules/fish-functions.nix
  ];

  home.username = "john";
  home.homeDirectory = "/home/john";
  home.stateVersion = "23.11";

  home.packages = with pkgs; [
    # cli essentials
    btop
    choose
    ncdu
    jq
    killall
    file
    unzip
    fastfetch
    nh
    trash-cli
    zip
    websocat
    bind
    systemctl-tui
  ];

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
  };

  programs.tmux = {
    enable = true;
    extraConfig = builtins.readFile ../.tmux.conf;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      tmux-colors-solarized
      catppuccin
      vim-tmux-navigator
      continuum
    ];
  };

  programs.neovim = {
    enable = true;
    withRuby = false;
    withPython3 = false;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraConfig = ''
      source ~/.vimrc

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
      vim-easymotion
      vim-surround
      vim-fugitive
      vim-abolish
      nerdcommenter
      nerdtree
      vim-rooter
      vim-fish
      vim-tmux-navigator
      ctrlp-vim

      vim-toml
      vim-yaml
      vim-markdown

      vim-colors-solarized
      sonokai
      gruvbox-material
      base16-vim
      vim-gruvbox8
      tokyonight-nvim
      catppuccin-nvim

      fzf-vim
    ];
  };

  programs.git = {
    enable = true;
    signing.format = "openpgp";
    settings = {
      user = {
        email = "john@john2143.com";
        name = "John Schmidt";
        signingkey = "/home/john/.ssh/id_github_sign.pub";
      };
      gpg.format = "ssh";
      push.default = "current";
      color.ui = "always";
      alias = {
        tree = "log --oneline --decorate --all --graph";
        hist = "log --pretty=format:'%h %ad | %s%d [%an]' --graph --date=short";
        co = "checkout";
        br = "branch";
        s = "status";
        ci = "commit -S";
        di = "diff";
      };
      pull.ff = "only";
      merge.conflictstyle = "zdiff3";
      rerere.enable = true;
      branch.sort = "-committerdate";
      commit.verbose = true;
      commit.gpgsign = true;
      tag.gpgsign = true;
      url."git@github.com".insteadOf = "gh";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;
      format = "$shell$time$username$hostname$directory$nix_shell$git_branch$git_commit$git_state$git_status$kubernetes$status$cmd_duration$jobs$line_break$character";
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
        ignore_branches = [];
        symbol = "";
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
      shell = {
        disabled = true;
        fish_indicator = "";
        format = "[$indicator ]($style)";
      };
      cmd_duration = {
        format = "[$duration]( $style)";
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
      };
      kubernetes = {
        format = "[⛵$context](dimmed cyan) ";
        disabled = false;
      };
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    defaultOptions = ["--height 40%" "--border"];
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
  };

  programs.bat = {
    enable = true;
    config = {
      style = "numbers,changes,header";
    };
  };

  programs.eza = {
    enable = true;
    enableFishIntegration = true;
    icons = "auto";
    git = true;
  };

  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--hidden"
      "--glob=!.git"
    ];
  };

  programs.fd = {
    enable = true;
    hidden = true;
    ignores = [".git/" "node_modules/" ".direnv/"];
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      editor = "nvim";
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      auto_sync = false;
      search_mode = "fuzzy";
      filter_mode = "directory";
      style = "compact";
    };
  };

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };
}
