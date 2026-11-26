import QtQuick
import Quickshell.Services.Notifications

// One live notification: expiry bookkeeping plus change coalescing.
//
// Created dynamically by Notifs._attachWatcher() for every tracked
// Notification, and torn down by Notifs._destroyWatcher() as soon as the
// notification is closed on D-Bus, evicted, or capped out. Nothing here writes
// to disk.
//
// A single `replaces_id` Notify() call emits several property change signals
// synchronously; syncTimer has a 0 ms interval and is only restarted, so the
// controller sees one update per D-Bus call instead of one per property.
QtObject {
    id: watcher

    property string uid: ""
    property Notification notif
    property var controller: null
    property real deadline: 0
    property real remaining: 0
    property bool paused: false

    readonly property Timer expiryTimer: Timer {
        repeat: false
        onTriggered: {
            if (watcher.controller)
                watcher.controller._handleExpiry(watcher.uid);
        }
    }

    readonly property Timer syncTimer: Timer {
        interval: 0
        repeat: false
        onTriggered: {
            if (watcher.controller)
                watcher.controller._onNotifUpdated(watcher.uid);
        }
    }

    readonly property Connections conn: Connections {
        target: watcher.notif

        function onSummaryChanged(): void {
            watcher.syncTimer.restart();
        }
        function onBodyChanged(): void {
            watcher.syncTimer.restart();
        }
        function onAppNameChanged(): void {
            watcher.syncTimer.restart();
        }
        function onAppIconChanged(): void {
            watcher.syncTimer.restart();
        }
        function onImageChanged(): void {
            watcher.syncTimer.restart();
        }
        function onUrgencyChanged(): void {
            watcher.syncTimer.restart();
        }
        function onHintsChanged(): void {
            watcher.syncTimer.restart();
        }
        function onActionsChanged(): void {
            watcher.syncTimer.restart();
        }
        function onExpireTimeoutChanged(): void {
            watcher.syncTimer.restart();
        }
        function onClosed(): void {
            watcher.syncTimer.stop();
            watcher.expiryTimer.stop();
            if (watcher.controller)
                watcher.controller._onLiveClosed(watcher.uid);
        }
    }

    // Start (or restart) the expiry countdown from scratch.
    function startTimer(ms: real): void {
        if (ms <= 0) {
            watcher.paused = false;
            watcher.deadline = 0;
            watcher.remaining = 0;
            watcher.expiryTimer.stop();
            return;
        }

        const duration = Math.max(1, Math.round(ms));
        watcher.paused = false;
        watcher.remaining = duration;
        watcher.deadline = Date.now() + duration;
        watcher.expiryTimer.interval = duration;
        watcher.expiryTimer.restart();
    }

    // Refresh the timeout on a `replaces_id` update. A hovered (paused) toast
    // stays paused but receives the full refreshed timeout for when the cursor
    // leaves it.
    function resetTimer(ms: real): void {
        if (ms <= 0) {
            watcher.stopTimer();
            return;
        }

        if (watcher.paused) {
            watcher.remaining = Math.max(1, Math.round(ms));
            watcher.deadline = 0;
            return;
        }

        watcher.startTimer(ms);
    }

    function stopTimer(): void {
        watcher.expiryTimer.stop();
        watcher.paused = false;
        watcher.deadline = 0;
        watcher.remaining = 0;
    }

    function pause(): void {
        if (watcher.paused || watcher.deadline <= 0)
            return;
        watcher.remaining = Math.max(0, watcher.deadline - Date.now());
        watcher.expiryTimer.stop();
        watcher.paused = true;
    }

    function resume(): void {
        if (!watcher.paused)
            return;
        watcher.paused = false;
        if (watcher.remaining <= 0) {
            if (watcher.controller)
                watcher.controller._handleExpiry(watcher.uid);
            return;
        }
        watcher.deadline = Date.now() + watcher.remaining;
        watcher.expiryTimer.interval = Math.max(1, Math.round(watcher.remaining));
        watcher.expiryTimer.restart();
    }

    // Detach from the controller before the object is destroyed so a signal
    // that is already queued cannot call back into a dying watcher.
    function teardown(): void {
        watcher.conn.enabled = false;
        watcher.syncTimer.stop();
        watcher.stopTimer();
        watcher.controller = null;
    }
}
