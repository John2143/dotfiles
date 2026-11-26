//@ pragma ShellId qs-notifs

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

ShellRoot {
    id: root

    // Touching both singletons at startup instantiates them before the first
    // notification arrives, so NotificationServer claims the bus name and the
    // palette is loaded before any card is drawn.
    readonly property int _unread: Notifs.unreadCount
    readonly property bool _dark: Theme.dark

    Component.onCompleted: {
        Quickshell.inhibitReloadPopup();
    }

    ToastStack {}
    HistoryPanel {}

    IpcHandler {
        target: "notifs"

        function toggle(): void {
            Notifs.togglePanel();
        }

        function open(): void {
            Notifs.openPanel();
        }

        function close(): void {
            Notifs.closePanel();
        }

        function toggleDnd(): void {
            Notifs.toggleDnd();
        }

        function setDnd(enabled: bool): void {
            Notifs.setDnd(enabled);
        }

        function isDnd(): bool {
            return Notifs.dnd;
        }

        function count(): int {
            return Notifs.history.length;
        }

        function unread(): int {
            return Notifs.unreadCount;
        }

        function clearToasts(): void {
            Notifs.hideAllToasts();
        }

        function clearHistory(): void {
            Notifs.clearHistory();
        }

        function reload(): void {
            Quickshell.reload(false);
        }
    }

    IpcHandler {
        target: "theme"

        function refresh(): void {
            Theme.reload();
        }
    }
}
