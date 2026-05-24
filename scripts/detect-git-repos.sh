#!/usr/bin/env bash
# detect-git-repos.sh — find git repos in ~ so you can decide what to move to ~/repos/
set -euo pipefail

TARGET="${1:-$HOME}"

echo "== Scanning $TARGET for git repos =="
echo

for dir in "$TARGET"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"

    # skip obvious non-repos
    case "$name" in
        .*|Downloads|Documents|Music|Pictures|Videos|Desktop|Public|Templates)
            continue ;;
    esac

    # drop trailing / for display
    dir="${dir%/}"

    if git -C "$dir" rev-parse --show-toplevel &>/dev/null; then
        top="$(git -C "$dir" rev-parse --show-toplevel)"
        if [ "$top" = "$dir" ]; then
            if [ "$name" = "dotfiles" ]; then
                echo "  KEEP   $dir  (dotfiles — never move)"
            else
                echo "  REPO   $dir"
            fi
        else
            echo "  SUB    $dir  → tracked by $top"
        fi
    else
        echo "  NOT    $dir"
    fi
done

echo
echo "Legend:"
echo "  REPO  = standalone git repo (candidate for ~/repos/)"
echo "  SUB   = part of a parent git repo (do not move independently)"
echo "  KEEP  = dotfiles (excluded)"
echo "  NOT   = not a git repo at all"
echo
echo "To move all REPOs into ~/repos/:"
echo "  mkdir -p ~/repos"
