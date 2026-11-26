pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification daemon + history store.
//
// One NotificationServer owns org.freedesktop.Notifications. Live notifications
// are held by tracked Notification objects (so `replaces_id` updates flow in
// place); the history list is an inert JSON record set that is flushed to
// $XDG_STATE_HOME/quickshell-notifs/history.json with a 1 s debounce.
Singleton {
    id: root

    // ---------------------------------------------------------------------
    // Public state
    // ---------------------------------------------------------------------

    property bool panelOpen: false
    property bool dnd: false
    property bool grouped: true
    property int unreadCount: 0
    property list<var> toasts: []
    property list<var> history: []

    readonly property string stateHome: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        if (xdg && String(xdg).length > 0)
            return String(xdg);
        const home = Quickshell.env("HOME");
        return (home ? String(home) : "/tmp") + "/.local/state";
    }

    readonly property string stateDir: root.stateHome + "/quickshell-notifs"

    // Internal bookkeeping (not persisted).
    property bool _loaded: false
    property int _seq: 0
    property var _watchers: ({})
    property var _dismissQueue: []
    property int _dismissIndex: 0

    onPanelOpenChanged: {
        if (root.panelOpen)
            root.unreadCount = 0;
    }
    onHistoryChanged: root._scheduleSave()
    onDndChanged: root._scheduleSave()
    onGroupedChanged: root._scheduleSave()

    // ---------------------------------------------------------------------
    // Contract API
    // ---------------------------------------------------------------------

    function togglePanel(): void {
        root.panelOpen = !root.panelOpen;
    }

    function openPanel(): void {
        root.panelOpen = true;
        root.unreadCount = 0;
    }

    function closePanel(): void {
        root.panelOpen = false;
    }

    function toggleDnd(): void {
        root.dnd = !root.dnd;
    }

    function setDnd(v: bool): void {
        root.dnd = v;
    }

    function hideToast(uid: string): void {
        const watcher = root._watchers[uid];
        if (watcher)
            watcher.stopTimer();
        root._removeToast(uid);
    }

    function hideAllToasts(): void {
        const arr = root._asArray(root.toasts);
        for (let i = 0; i < arr.length; i++) {
            const watcher = root._watchers[arr[i].uid];
            if (watcher)
                watcher.stopTimer();
        }
        root.toasts = [];
    }

    function dismissEntry(uid: string): void {
        const notif = root._liveNotifOf(uid);
        if (notif)
            notif.dismiss();
        root._removeToast(uid);
    }

    function removeHistory(uid: string): void {
        root.dismissEntry(uid);
        root._removeHistory(uid);
        root._scheduleSave();
    }

    function clearHistory(): void {
        const queue = [];
        for (const uid in root._watchers) {
            const watcher = root._watchers[uid];
            if (watcher && watcher.notif)
                queue.push(watcher.notif);
            root._destroyWatcher(uid);
        }

        root.history = [];
        root.toasts = [];
        root.unreadCount = 0;

        // Dismissing a few hundred notifications synchronously would block the
        // UI thread; the timer drains one per tick.
        root._dismissQueue = queue;
        root._dismissIndex = 0;
        if (queue.length > 0)
            dismissBatchTimer.restart();
    }

    function invokeAction(uid: string, identifier: string): void {
        const notif = root._liveNotifOf(uid);
        if (!notif)
            return;

        const want = identifier.length === 0 ? "default" : identifier;
        const actions = notif.actions;
        if (!actions)
            return;

        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            if (String(action.identifier) === want) {
                action.invoke();
                return;
            }
        }
    }

    function openFirstUrl(uid: string): void {
        const entry = root._entryOf(uid);
        if (!entry)
            return;

        const text = String(entry.body || "") + "\n" + String(entry.summary || "");
        const match = text.match(/https?:\/\/[^\s<>"')\]]+/);
        if (match)
            Quickshell.execDetached(["xdg-open", match[0]]);
    }

    function openUrl(url: string): void {
        if (url.length === 0)
            return;
        Quickshell.execDetached(["xdg-open", url]);
    }

    function pauseToast(uid: string): void {
        const watcher = root._watchers[uid];
        if (watcher)
            watcher.pause();
    }

    function resumeToast(uid: string): void {
        const watcher = root._watchers[uid];
        if (watcher)
            watcher.resume();
    }

    function formatAge(ts: real): string {
        // Reading the clock keeps the binding live without per-row timers.
        const now = clock.date.getTime();
        const diff = Math.max(0, now - Number(ts));
        const mins = Math.floor(diff / 60000);
        if (mins < 1)
            return "now";
        if (mins < 60)
            return mins + "m";
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h";
        return Math.floor(hours / 24) + "d";
    }

    // ---------------------------------------------------------------------
    // Notification server
    // ---------------------------------------------------------------------

    NotificationServer {
        id: server

        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        persistenceSupported: true
        actionIconsSupported: false
        inlineReplySupported: false
        extraHints: ["x-dunst-stack-tag"]

        onNotification: n => {
            root._ingest(n);
        }
    }

    // ---------------------------------------------------------------------
    // Ingestion / coalescing
    // ---------------------------------------------------------------------

    function _ingest(n): void {
        if (!n)
            return;

        const summary = String(n.summary || "");
        // Bastion "base station connected" notifications (dunstrc skip_display
        // + history_ignore) are dropped before anything else happens.
        if (/^LHB-/.test(summary)) {
            n.dismiss();
            return;
        }

        // Must be synchronous: untracked notifications are destroyed when the
        // server returns from Notify().
        n.tracked = true;

        const stackTag = root._stackTagOf(n);
        const appName = String(n.appName || "");
        const body = String(n.body || "");
        const urgency = Number(n.urgency);

        // x-dunst-stack-tag coalescing: replace the prior card/history slot.
        if (stackTag.length > 0) {
            const uids = root._asArray(root.toasts);
            let uid = "";
            for (let i = 0; i < uids.length; i++) {
                if (uids[i].stackTag === stackTag) {
                    uid = uids[i].uid;
                    break;
                }
            }
            if (uid.length === 0) {
                const records = root._asArray(root.history);
                for (let i = 0; i < records.length; i++) {
                    if (records[i].stackTag === stackTag) {
                        uid = records[i].uid;
                        break;
                    }
                }
            }

            if (uid.length > 0) {
                const oldNotif = root._liveNotifOf(uid);
                root._destroyWatcher(uid);
                if (oldNotif && oldNotif !== n)
                    oldNotif.dismiss();

                const entry = root._makeEntry(n, uid);
                const record = root._makeEntry(n, uid);
                const existing = root._findEntry(uid);

                if (root._shouldShowToast(urgency))
                    root._putToast(entry);
                else
                    root._removeToast(uid);

                if (!record.transient) {
                    if (existing)
                        record.duplicateCount = Math.max(1, Number(existing.duplicateCount) || 1);
                    root._putHistoryRecord(record);
                }

                root._attachWatcher(uid, n);
                if (!root.panelOpen && !record.transient)
                    root.unreadCount += 1;
                root._scheduleSave();
                return;
            }
        }

        // idempotent duplicate stacking (same app/summary/body within 10 s)
        const candidates = root._asArray(root.toasts);
        for (let i = 0; i < candidates.length; i++) {
            const t = candidates[i];
            if (t.appName === appName && t.summary === summary && t.body === body
                    && Number(t.urgency) === urgency && (Date.now() - Number(t.timestamp)) < 10000) {
                const bumped = root._asArray(root.toasts).slice();
                const toast = bumped[i];
                toast.duplicateCount = Math.max(1, Number(toast.duplicateCount) || 1) + 1;
                bumped[i] = toast;
                root.toasts = bumped;

                const recordIndex = root._historyIndex(toast.uid);
                if (recordIndex >= 0) {
                    const records = root._asArray(root.history).slice();
                    const record = records[recordIndex];
                    record.duplicateCount = toast.duplicateCount;
                    records[recordIndex] = record;
                    root.history = records;
                }

                const watcher = root._watchers[toast.uid];
                if (watcher)
                    watcher.startTimer(root._timeoutMs(n));

                if (!root.panelOpen)
                    root.unreadCount += 1;
                n.dismiss();
                root._scheduleSave();
                return;
            }
        }

        // Fresh notification.
        const uid = root._nextUid();
        const entry = root._makeEntry(n, uid);
        const record = root._makeEntry(n, uid);

        if (!record.transient)
            root._putHistoryRecord(record);
        if (root._shouldShowToast(urgency))
            root._putToast(entry);

        root._attachWatcher(uid, n);
        if (!root.panelOpen && !record.transient)
            root.unreadCount += 1;
        root._scheduleSave();
    }

    function _shouldShowToast(urgency: int): bool {
        if (!root.dnd)
            return true;
        return urgency >= NotificationUrgency.Critical;
    }

    function _attachWatcher(uid: string, n): void {
        root._destroyWatcher(uid);
        const watcher = liveWatcherComponent.createObject(root, {
                "uid": uid,
                "notif": n,
                "controller": root
            });
        if (!watcher)
            return;
        root._watchers[uid] = watcher;
        watcher.startTimer(root._timeoutMs(n));
    }

    function _destroyWatcher(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher)
            return;
        watcher.stopTimer();
        if (watcher.conn)
            watcher.conn.enabled = false;
        delete root._watchers[uid];
        watcher.destroy();
    }

    // ---------------------------------------------------------------------
    // Live notification changes (replaces_id lands here, not in _ingest)
    // ---------------------------------------------------------------------

    function _syncLive(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher || !watcher.notif)
            return;
        root._syncFromNotif(uid, watcher.notif);
    }

    function _syncFromNotif(uid: string, n): void {
        let toastChanged = false;
        const toasts = root._asArray(root.toasts).slice();
        for (let i = 0; i < toasts.length; i++) {
            if (toasts[i].uid !== uid)
                continue;
            const entry = toasts[i];
            root._applyNotif(entry, n);
            toasts[i] = entry;
            toastChanged = true;
        }
        if (toastChanged)
            root.toasts = root._sortToasts(toasts);

        let historyChanged = false;
        const records = root._asArray(root.history).slice();
        for (let i = 0; i < records.length; i++) {
            if (records[i].uid !== uid)
                continue;
            const record = records[i];
            root._applyNotif(record, n);
            records[i] = record;
            historyChanged = true;
        }
        if (historyChanged)
            root.history = records;

        root._scheduleSave();
    }

    function _onLiveClosed(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher)
            return;

        const n = watcher.notif;
        if (n)
            root._syncFromNotif(uid, n);

        root._removeToast(uid);

        const index = root._historyIndex(uid);
        if (index >= 0) {
            const records = root._asArray(root.history).slice();
            const record = records[index];
            record.liveNotif = null;
            record.dbusId = 0;
            record.actions = [];
            if (typeof record.image === "string" && record.image.indexOf("image://qsimage") === 0)
                record.image = "";
            records[index] = record;
            root.history = records;
        }

        if (watcher.conn)
            watcher.conn.enabled = false;
        watcher.stopTimer();
        delete root._watchers[uid];
        watcher.destroy();
        root._scheduleSave();
    }

    function _handleExpiry(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher)
            return;

        const index = root._toastIndex(uid);
        const entry = index >= 0 ? root._asArray(root.toasts)[index] : root._findEntry(uid);
        const transient = entry ? entry.transient === true
                                : (watcher.notif ? watcher.notif.transient === true : false);

        if (transient) {
            // Transient notifications are never persisted; let the server tell
            // the client it expired.
            root._removeToast(uid);
            if (watcher.notif)
                watcher.notif.expire();
            return;
        }

        // Timeout only hides the popup. The notification stays tracked so the
        // history row keeps its live actions; D4 forbids dismiss() here.
        root._removeToast(uid);
    }

    function _resetTimer(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher || !watcher.notif)
            return;
        watcher.startTimer(root._timeoutMs(watcher.notif));
    }

    // ---------------------------------------------------------------------
    // Entry helpers
    // ---------------------------------------------------------------------

    function _makeEntry(n, uid: string): var {
        return {
            "uid": uid,
            "dbusId": Number(n.id) || 0,
            "stackTag": root._stackTagOf(n),
            "appName": String(n.appName || ""),
            "appIcon": String(n.appIcon || ""),
            "image": String(n.image || ""),
            "summary": String(n.summary || ""),
            "body": String(n.body || ""),
            "urgency": Number(n.urgency),
            "progress": root._progressOf(n),
            "timestamp": Date.now(),
            "duplicateCount": 1,
            "transient": n.transient === true,
            "actions": root._actionsOf(n),
            "liveNotif": n
        };
    }

    function _applyNotif(entry, n): void {
        entry.dbusId = Number(n.id) || 0;
        entry.stackTag = root._stackTagOf(n);
        entry.appName = String(n.appName || "");
        entry.appIcon = String(n.appIcon || "");
        entry.image = String(n.image || "");
        entry.summary = String(n.summary || "");
        entry.body = String(n.body || "");
        entry.urgency = Number(n.urgency);
        entry.progress = root._progressOf(n);
        entry.transient = n.transient === true;
        entry.actions = root._actionsOf(n);
    }

    function _actionsOf(n): var {
        const out = [];
        const actions = n.actions;
        if (!actions)
            return out;
        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            out.push({
                    "identifier": String(action.identifier),
                    "text": String(action.text)
                });
        }
        return out;
    }

    function _stackTagOf(n): string {
        const hints = n.hints;
        if (!hints)
            return "";
        const value = hints["x-dunst-stack-tag"];
        if (value === undefined || value === null)
            return "";
        return String(value);
    }

    function _progressOf(n): int {
        const hints = n.hints;
        if (!hints)
            return -1;
        const value = hints["value"];
        if (value === undefined || value === null)
            return -1;
        const number = Number(value);
        if (isNaN(number))
            return -1;
        return Math.max(0, Math.min(100, Math.round(number)));
    }

    // Expire timeout arrives in milliseconds despite the docstring saying
    // seconds (the D-Bus value is passed through verbatim).
    function _timeoutMs(n): int {
        const timeout = Number(n.expireTimeout);
        if (timeout < 0)
            return Number(n.urgency) === NotificationUrgency.Critical ? 0 : 10000;
        if (timeout === 0)
            return 0;
        return Math.max(0, Math.round(timeout));
    }

    function _nextUid(): string {
        root._seq += 1;
        return "n" + Date.now().toString(36) + "-" + root._seq;
    }

    function _asArray(value): var {
        if (!value)
            return [];
        if (Array.isArray(value))
            return value;
        const out = [];
        for (let i = 0; i < value.length; i++)
            out.push(value[i]);
        return out;
    }

    function _sortToasts(list): var {
        const sorted = root._asArray(list).slice();
        sorted.sort((a, b) => {
            const ua = Number(a.urgency);
            const ub = Number(b.urgency);
            if (ua !== ub)
                return ub - ua;
            return Number(b.timestamp) - Number(a.timestamp);
        });
        return sorted.slice(0, 20);
    }

    function _toastIndex(uid: string): int {
        const arr = root._asArray(root.toasts);
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].uid === uid)
                return i;
        }
        return -1;
    }

    function _historyIndex(uid: string): int {
        const arr = root._asArray(root.history);
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].uid === uid)
                return i;
        }
        return -1;
    }

    function _findEntry(uid: string): var {
        let index = root._toastIndex(uid);
        if (index >= 0)
            return root._asArray(root.toasts)[index];
        index = root._historyIndex(uid);
        if (index >= 0)
            return root._asArray(root.history)[index];
        return null;
    }

    function _entryOf(uid: string): var {
        return root._findEntry(uid);
    }

    function _liveNotifOf(uid: string): var {
        const watcher = root._watchers[uid];
        if (watcher && watcher.notif)
            return watcher.notif;
        const entry = root._findEntry(uid);
        return entry ? entry.liveNotif : null;
    }

    function _putToast(entry): void {
        const arr = root._asArray(root.toasts).slice();
        let replaced = false;
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].uid === entry.uid) {
                arr[i] = entry;
                replaced = true;
                break;
            }
        }
        if (!replaced)
            arr.unshift(entry);
        root.toasts = root._sortToasts(arr);
    }

    function _putHistoryRecord(record): void {
        const arr = root._asArray(root.history).slice();
        let replaced = false;
        for (let i = 0; i < arr.length; i++) {
            if (arr[i].uid === record.uid) {
                arr[i] = record;
                replaced = true;
                break;
            }
        }
        if (!replaced)
            arr.unshift(record);
        root.history = arr.slice(0, 200);
    }

    function _removeToast(uid: string): void {
        const arr = root._asArray(root.toasts);
        const filtered = arr.filter(entry => entry.uid !== uid);
        if (filtered.length !== arr.length)
            root.toasts = filtered;
    }

    function _removeHistory(uid: string): void {
        const arr = root._asArray(root.history);
        const filtered = arr.filter(record => record.uid !== uid);
        if (filtered.length !== arr.length)
            root.history = filtered;
    }

    // ---------------------------------------------------------------------
    // Persistence
    // ---------------------------------------------------------------------

    function _scheduleSave(): void {
        if (!root._loaded)
            return;
        saveTimer.restart();
    }

    function _persist(): void {
        if (!root._loaded)
            return;

        stateAdapter.dnd = root.dnd;
        stateAdapter.grouped = root.grouped;
        stateAdapter.entries = root._asArray(root.history).slice(0, 200).map(record => ({
                "uid": String(record.uid),
                "dbusId": 0,
                "stackTag": String(record.stackTag || ""),
                "appName": String(record.appName || ""),
                "appIcon": String(record.appIcon || ""),
                "image": (typeof record.image === "string"
                    && record.image.indexOf("image://qsimage") !== 0) ? record.image : "",
                "summary": String(record.summary || ""),
                "body": String(record.body || ""),
                "urgency": Number(record.urgency) || 0,
                "progress": typeof record.progress === "number" ? record.progress : -1,
                "timestamp": Number(record.timestamp) || Date.now(),
                "duplicateCount": Math.max(1, Number(record.duplicateCount) || 1),
                "transient": false,
                "actions": []
            }));
        stateFile.writeAdapter();
    }

    function _restore(): void {
        const cutoff = Date.now() - 14 * 24 * 60 * 60 * 1000;
        const records = root._asArray(stateAdapter.entries);
        const live = root._asArray(root.history);
        const restored = [];
        const seen = new Set(live.map(record => record.uid));

        for (let i = 0; i < records.length; i++) {
            const raw = records[i];
            if (!raw || typeof raw !== "object")
                continue;
            const timestamp = Number(raw.timestamp);
            if (!isFinite(timestamp) || timestamp < cutoff)
                continue;
            const uid = raw.uid ? String(raw.uid) : root._nextUid();
            if (seen.has(uid))
                continue;
            seen.add(uid);
            restored.push({
                    "uid": uid,
                    "dbusId": 0,
                    "stackTag": String(raw.stackTag || ""),
                    "appName": String(raw.appName || ""),
                    "appIcon": String(raw.appIcon || ""),
                    "image": (typeof raw.image === "string"
                        && raw.image.indexOf("image://qsimage") !== 0) ? raw.image : "",
                    "summary": String(raw.summary || ""),
                    "body": String(raw.body || ""),
                    "urgency": Number(raw.urgency) || 0,
                    "progress": typeof raw.progress === "number" ? raw.progress : -1,
                    "timestamp": timestamp,
                    "duplicateCount": Math.max(1, Number(raw.duplicateCount) || 1),
                    "transient": false,
                    "actions": [],
                    "liveNotif": null
                });
        }

        restored.sort((a, b) => b.timestamp - a.timestamp);
        root.history = live.concat(restored).slice(0, 200);
        root.dnd = stateAdapter.dnd === true;
        root.grouped = stateAdapter.grouped !== false;
        root._loaded = true;
        root._scheduleSave();
    }

    function _onLoadFailed(): void {
        root._loaded = true;
        root._scheduleSave();
    }

    // ---------------------------------------------------------------------
    // Children
    // ---------------------------------------------------------------------

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    FileView {
        id: stateFile
        path: root.stateDir + "/history.json"
        blockLoading: true
        watchChanges: false
        printErrors: false
        onLoaded: root._restore()
        onLoadFailed: root._onLoadFailed()

        JsonAdapter {
            id: stateAdapter
            property bool dnd: false
            property bool grouped: true
            property var entries: []
        }
    }

    Timer {
        id: saveTimer
        interval: 1000
        repeat: false
        onTriggered: root._persist()
    }

    Timer {
        id: dismissBatchTimer
        interval: 10
        repeat: true
        onTriggered: {
            if (root._dismissIndex >= root._dismissQueue.length) {
                dismissBatchTimer.stop();
                root._dismissQueue = [];
                root._dismissIndex = 0;
                return;
            }
            const notif = root._dismissQueue[root._dismissIndex];
            root._dismissIndex += 1;
            if (notif)
                notif.dismiss();
            if (root._dismissIndex >= root._dismissQueue.length) {
                dismissBatchTimer.stop();
                root._dismissQueue = [];
                root._dismissIndex = 0;
            }
        }
    }

    Component {
        id: liveWatcherComponent

        QtObject {
            id: watcher

            property string uid: ""
            property Notification notif
            property var controller: null
            property real deadline: 0
            property real remaining: 0
            property bool paused: false

            readonly property Timer expiryTimer: Timer {
                interval: 1000
                repeat: false
                onTriggered: {
                    if (watcher.controller)
                        watcher.controller._handleExpiry(watcher.uid);
                }
            }

            readonly property Connections conn: Connections {
                target: watcher.notif

                function onSummaryChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onBodyChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onAppNameChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onAppIconChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onImageChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onUrgencyChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onHintsChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onActionsChanged(): void {
                    if (watcher.controller)
                        watcher.controller._syncLive(watcher.uid);
                }
                function onExpireTimeoutChanged(): void {
                    if (watcher.controller) {
                        watcher.controller._syncLive(watcher.uid);
                        watcher.controller._resetTimer(watcher.uid);
                    }
                }
                function onClosed(): void {
                    if (watcher.controller)
                        watcher.controller._onLiveClosed(watcher.uid);
                }
            }

            function startTimer(ms: real): void {
                if (ms <= 0) {
                    paused = false;
                    deadline = 0;
                    remaining = 0;
                    expiryTimer.stop();
                    return;
                }

                const duration = Math.max(1, Math.round(ms));
                paused = false;
                deadline = Date.now() + duration;
                remaining = duration;
                expiryTimer.interval = duration;
                expiryTimer.restart();
            }

            function stopTimer(): void {
                expiryTimer.stop();
                paused = false;
                deadline = 0;
                remaining = 0;
            }

            function pause(): void {
                if (paused || deadline <= 0)
                    return;
                remaining = Math.max(0, deadline - Date.now());
                expiryTimer.stop();
                paused = true;
            }

            function resume(): void {
                if (!paused)
                    return;
                paused = false;
                if (remaining <= 0) {
                    if (watcher.controller)
                        watcher.controller._handleExpiry(watcher.uid);
                    return;
                }
                deadline = Date.now() + remaining;
                expiryTimer.interval = Math.max(1, Math.round(remaining));
                expiryTimer.restart();
            }
        }
    }

    Component.onCompleted: {
        // FileView also creates parents on write; doing it up front keeps the
        // first save from racing a writable-path check.
        Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
    }
}
