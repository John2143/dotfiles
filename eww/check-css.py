#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p gtk3 gobject-introspection python3Packages.pygobject3
"""Parse-check the eww stylesheet with GTK's own CSS parser, headlessly.

eww substitutes $vars and hands the result to GtkCssProvider. GTK does not skip
rules it cannot understand: one bad property or value discards the ENTIRE
stylesheet, and the only visible symptom is every eww window falling back to the
bare GTK theme (light background, no padding). Running the same parse here
catches that before a rebuild, without a compositor and without opening windows.

Usage: eww/check-css.py [file]   (default: eww.scss beside this script)
"""
import re
import sys
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("eww.scss")
css = path.read_text()
variables = dict(re.findall(r"^(\$[\w-]+):\s*(.+?);", css, re.M))
# Drop the definitions themselves: eww consumes them, and leaving them in
# produces a selector like "#1e1e2e: #1e1e2e;".
css = re.sub(r"^\s*\$[\w-]+\s*:.*?;\s*$", "", css, flags=re.M)
css = re.sub(r"\$[\w-]+", lambda m: variables.get(m.group(0), m.group(0)), css)

try:
    Gtk.CssProvider().load_from_data(css.encode())
except Exception as error:  # GLib.Error carries the line and property
    sys.exit(f"{path}: {error}")

print(f"OK: {path} parses cleanly")
