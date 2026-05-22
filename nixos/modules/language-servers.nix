{ pkgs, pkgs-stable, ... }:

{
  home.packages = with pkgs; [
    # ── Rust (.rs) ──────────────────────────────────────────────────
    rust-analyzer

    # ── TypeScript / JavaScript (.ts, .tsx, .js, .jsx, .mjs, .cjs,
    #   .html, .css, .scss, .sass, .less, .json, .jsonc) ────────────
    typescript-language-server
    vscode-langservers-extracted  # html/css/json/eslint langservers
    biome                         # linter + formatter (ts/js/json)
    tailwindcss-language-server   # tailwind intellisense
    emmet-language-server         # html/css completions

    # ── Python (.py, .pyi) ──────────────────────────────────────────
    pyright
    basedpyright
    pkgs-stable.python3Packages.python-lsp-server  # pylsp
    ruff                               # linter

    # ── Shell (.sh, .bash, .zsh) ────────────────────────────────────
    bash-language-server

    # ── Nix (.nix) ──────────────────────────────────────────────────
    # nixd is installed in home-cli.nix
    nil

    # ── Markdown (.md, .markdown) ───────────────────────────────────
    marksman

    # ── YAML (.yaml, .yml) ──────────────────────────────────────────
    yaml-language-server

    # ── Go (.go, .mod, .sum) ────────────────────────────────────────
    gopls

    # ── Docker (Dockerfile, .dockerfile) ────────────────────────────
    dockerfile-language-server

    # ── C / C++ (.c, .cpp, .cc, .cxx, .h, .hpp, .hxx, .m, .mm) ────
    clang-tools  # provides clangd
  ];
}
