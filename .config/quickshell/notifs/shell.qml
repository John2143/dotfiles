//@ pragma ShellId qs-notifs

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.components

ShellRoot {
    id: root

    // Instantiating both singletons at startup means NotificationServer claims
    // org.freedesktop.Notifications and the palette is loaded before the first
    // notification arrives (or any card is drawn).
    Component.onCompleted: {
        Quickshell.inhibitReloadPopup();
        if (Theme.flavor.length === 0)
            Theme.reload();
        if (Notifs.panelOpen)
            Notifs.closePanel();
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
