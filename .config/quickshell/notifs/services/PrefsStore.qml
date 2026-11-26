pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Persists the two notification-shell preferences that may survive a restart.
//
// Notification *content* is deliberately RAM-only (dunst parity): this store
// never reads or writes a history file, only
// $XDG_STATE_HOME/quickshell-notifs/prefs.json holding { dnd, grouped }.
//
// Parsing goes through FileView.text()/setText() (the same pattern Theme.qml
// uses for palette.json) rather than a JsonAdapter child, which Quickshell
// 0.3.2 leaves unexported in its qmltypes. A missing or corrupt file leaves the
// defaults in place and does not create anything until a preference changes.
Scope {
    id: root

    readonly property bool loaded: root._loaded

    signal restored(bool dnd, bool grouped)

    property bool _loaded: false
    property bool _savedDnd: false
    property bool _savedGrouped: true
    property bool _pendingDnd: false
    property bool _pendingGrouped: true

    // Coalesces DND/grouped toggles into a single write. A no-op before the
    // file has been read (so restoring never rewrites the file it just loaded)
    // and when there is nowhere to persist to.
    function scheduleSave(dnd: bool, grouped: bool): void {
        if (!root._loaded || prefsFile.path === "")
            return;
        if (dnd === root._savedDnd && grouped === root._savedGrouped)
            return;
        root._pendingDnd = dnd;
        root._pendingGrouped = grouped;
        saveTimer.restart();
    }

    FileView {
        id: prefsFile
        path: Theme.stateHome !== "" ? Theme.stateHome + "/quickshell-notifs/prefs.json" : ""
        blockLoading: true
        watchChanges: false
        printErrors: false

        onLoaded: {
            let parsed = null;
            try {
                parsed = JSON.parse(prefsFile.text());
            } catch (e) {
                parsed = null;
            }

            if (parsed !== null && typeof parsed === "object") {
                root._savedDnd = parsed.dnd === true;
                root._savedGrouped = parsed.grouped !== false;
            } else {
                root._savedDnd = false;
                root._savedGrouped = true;
            }

            root._pendingDnd = root._savedDnd;
            root._pendingGrouped = root._savedGrouped;
            root._loaded = true;
            root.restored(root._savedDnd, root._savedGrouped);
        }

        onLoadFailed: {
            // First boot, no usable state home, or unreadable file: start from
            // the defaults and leave the filesystem alone.
            root._loaded = true;
        }
    }

    Timer {
        id: saveTimer
        interval: 500
        repeat: false
        onTriggered: {
            root._savedDnd = root._pendingDnd;
            root._savedGrouped = root._pendingGrouped;
            prefsFile.setText(JSON.stringify({
                    "dnd": root._savedDnd,
                    "grouped": root._savedGrouped
                }, null, 2) + "\n");
        }
    }
}
