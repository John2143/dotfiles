#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p gtk3 gobject-introspection python3Packages.pygobject3 grass-sass
"""Parse-check the eww stylesheet, headlessly.

eww compiles eww.scss with grass, with its config directory on the load path, so
`@import "theme"` resolves to theme.scss beside it - the file theme-switch writes
from nixos/modules/theme.nix. This script reproduces that compile and then hands
the CSS to GTK's own parser.

GTK does not skip rules it cannot understand: one bad property or value discards
the ENTIRE stylesheet, and the only visible symptom is every eww window falling
back to the bare GTK theme (light background, no padding). Running the same parse
here catches that before a rebuild, without a compositor and without opening
windows.

Usage: eww/check-css.py [scss] [theme]
       (defaults: eww.scss beside this script, ~/.config/eww/theme.scss)
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

scss_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("eww.scss")
theme_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.home() / ".config/eww/theme.scss"

if not theme_path.is_file():
    sys.exit(f"{theme_path}: not found - run `theme-switch refresh` first")

with tempfile.TemporaryDirectory() as tmp:
    # grass only resolves `@import "theme"` from a load path, so stage both files
    # under the names eww uses.
    shutil.copy(scss_path, Path(tmp) / "eww.scss")
    shutil.copy(theme_path, Path(tmp) / "theme.scss")
    result = subprocess.run(
        ["grass", "-I", tmp, str(Path(tmp) / "eww.scss")],
        capture_output=True,
        text=True,
    )

if result.returncode != 0:
    sys.exit(f"{scss_path}: {result.stderr.strip()}")

try:
    Gtk.CssProvider().load_from_data(result.stdout.encode())
except Exception as error:  # GLib.Error carries the line and property
    sys.exit(f"{scss_path}: {error}")

print(f"OK: {scss_path} parses cleanly")
