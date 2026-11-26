pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Catppuccin palette for the notification shell.
//
// `theme-switch` writes `~/.local/state/theme/current/palette.json`; this
// singleton watches that exact path (not a config symlink) so an atomic rename
// is picked up by the file watcher and every colour binding re-evaluates.
Singleton {
    id: root

    readonly property string stateHome: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        if (xdg && String(xdg).length > 0)
            return String(xdg);
        const home = Quickshell.env("HOME");
        return (home ? String(home) : "/tmp") + "/.local/state";
    }

    readonly property string palettePath: root.stateHome + "/theme/current/palette.json"

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 11

    // Catppuccin Mocha, used until the first theme-switch run has produced a
    // palette file (or if it is unreadable).
    readonly property var fallback: ({
            "rosewater": "#f5e0dc",
            "flamingo": "#f2cdcd",
            "pink": "#f5c2e7",
            "mauve": "#cba6f7",
            "red": "#f38ba8",
            "maroon": "#eba0ac",
            "peach": "#fab387",
            "yellow": "#f9e2af",
            "green": "#a6e3a1",
            "teal": "#94e2d5",
            "sky": "#89dceb",
            "sapphire": "#74c7ec",
            "blue": "#89b4fa",
            "lavender": "#b4befe",
            "text": "#cdd6f4",
            "subtext1": "#bac2de",
            "subtext0": "#a6adc8",
            "overlay2": "#9399b2",
            "overlay1": "#7f849c",
            "overlay0": "#6c7086",
            "surface2": "#585b70",
            "surface1": "#45475a",
            "surface0": "#313244",
            "base": "#1e1e2e",
            "mantle": "#181825",
            "crust": "#11111b"
        })

    readonly property var parsed: {
        const raw = paletteFile.text();
        if (!raw || raw.length === 0)
            return null;
        try {
            return JSON.parse(raw);
        } catch (e) {
            return null;
        }
    }

    readonly property var colors: root.parsed && root.parsed.colors ? root.parsed.colors : root.fallback
    readonly property string flavor: root.parsed && root.parsed.flavor ? String(root.parsed.flavor) : "dark"
    readonly property bool dark: root.flavor !== "light"

    function col(name: string): color {
        const palette = root.colors;
        const value = palette ? palette[name] : undefined;
        if (value === undefined || value === null)
            return Qt.rgba(0, 0, 0, 0);
        return value;
    }

    // QML colours are `#AARRGGBB`, so blend through Qt.rgba instead of string
    // concatenation to keep the alpha where callers expect it.
    function alpha(name: string, a: real): color {
        const c = root.col(name);
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function reload(): void {
        paletteFile.reload();
    }

    FileView {
        id: paletteFile
        path: root.palettePath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: paletteFile.reload()
    }
}
