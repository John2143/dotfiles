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
    # cli
    starship #prompt
    bat # cat replacement
    eza # ls replacement
    ripgrep # grep replacement
    # btop # btop++ > bpytop > htop > top
    choose # awk replacement
    du-dust # df/du replacement
    fzf
    killall

    # k8s
    kubectl
    k9s

    # fnm # node version manager # TODO switch to nixos
    clang # compiler
    rustup # rust compiler

  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    ".vimrc".source = ../../.vimrc;
    ".tmux.conf".source = ../../.tmux.conf;
    ".gitconfig".source = ../../.gitconfig;
    # ".xprofile.fish".source = ../../.xprofile.fish;
    # ".xprofile".source = ../../.xprofile;

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
    plugins = [
    ];
  };



  programs.tmux = {
    enable = true;
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
      tabular

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

      # copilot-vim-nvim

    ];
  };
}
