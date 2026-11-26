# Offline qmllint gate for the Quickshell notification config.
#
# Quickshell synthesizes a `qmldir` for every directory of the config when it
# loads it (src/core/scan.cpp, QmlScanner::scanDir): the config root becomes
# module `qs`, `services/` becomes `qs.services`, and every [A-Z]*.qml file
# becomes a type — a singleton if the file carries `pragma Singleton`. qmllint
# needs those files to resolve `import qs.services`, so this check rebuilds the
# same tree in a writable temp dir and lints that copy: the config itself is a
# read-only store path.
#
# Only `import` and `missing-property` are escalated; the rest of qmllint's
# warnings stay advisory so a new Qt version does not turn style nits into a
# build failure.
#
# It also pins Theme.qml's Mocha fallback to `palettes.dark` in
# nixos/modules/theme.nix: the QML copy is what renders before the first
# theme-switch run, so a drift there is a visible colour bug.
{
  pkgs,
  configDir,
  themeFile,
}: let
  qtQml = "${pkgs.qt6.qtdeclarative}/lib/qt-6/qml";
  qsQml = "${pkgs.quickshell}/lib/qt-6/qml";
in
  pkgs.runCommandLocal "quickshell-notifs-qmllint" {
    nativeBuildInputs = [pkgs.qt6.qtdeclarative];
  } ''
    set -o errexit -o nounset -o pipefail

    imports="$(mktemp -d)"
    trap 'rm -rf "$imports"' EXIT
    qs="$imports/qs"
    mkdir -p "$qs"
    cp -r ${configDir}/. "$qs/"
    chmod -R u+w "$qs"

    # Mirror QmlScanner::scanDir: `module qs` for the root, `module qs.<sub>`
    # for a subdirectory, with one line per exported file.
    find "$qs" -type d | sort | while IFS= read -r dir; do
      rel="''${dir#"$qs"}"
      {
        printf 'module qs%s\n' "''${rel//\//.}"
        for f in "$dir"/*.qml; do
          [ -f "$f" ] || continue
          base="$(basename "$f")"
          case "$base" in
            [A-Z]*) ;;
            *) continue ;;
          esac
          if grep -q '^pragma Singleton' "$f"; then
            printf 'singleton %s 1.0 %s\n' "''${base%.qml}" "$base"
          else
            printf '%s 1.0 %s\n' "''${base%.qml}" "$base"
          fi
        done
      } > "$dir/qmldir"
    done

    # Lint every file, then fail once: a single build shows all the errors
    # instead of stopping at the first one.
    failed=0
    while IFS= read -r f; do
      echo "qmllint $f"
      qmllint \
        -I ${qtQml} \
        -I ${qsQml} \
        -I "$imports" \
        --import=error \
        --missing-property=error \
        "$f" || failed=1
    done < <(find "$qs" -name '*.qml' | sort)

    if [ "$failed" -ne 0 ]; then
      echo "qmllint reported errors, see the log above" >&2
      exit 1
    fi

    # Verify Theme.qml's Mocha fallback matches palettes.dark in theme.nix.
    theme_mocha="$(awk '/^[[:space:]]*dark = \{/{f=1;next} f && /^[[:space:]]*\};/{exit} f && /= "/{gsub(/[[:space:];"]/, ""); split($0, a, "="); print a[1] "=#" a[2]}' ${themeFile} | sort)"
    qml_mocha="$(awk '/fallback: \(\{/{f=1;next} f && /\}\)/{exit} f && /"#[0-9a-fA-F]{6}"/{gsub(/[[:space:],"]/, ""); split($0, a, ":"); print a[1] "=" a[2]}' "$qs/services/Theme.qml" | sort)"
    if [ -z "$theme_mocha" ] || [ "$theme_mocha" != "$qml_mocha" ]; then
      echo "Theme.qml Mocha fallback does not match palettes.dark in ${themeFile}" >&2
      diff -u <(printf '%s\n' "$theme_mocha") <(printf '%s\n' "$qml_mocha") >&2 || true
      exit 1
    fi

    touch $out
  ''
