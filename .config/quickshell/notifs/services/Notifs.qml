pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Hyprland
import qs.services

// Notification daemon + RAM-only history.
//
// One NotificationServer owns org.freedesktop.Notifications. Live notifications
// are held by tracked Notification objects, so a `replaces_id` Notify() arrives
// as property changes on the existing object instead of a second card. History
// lives in memory only (dunst parity); the sole thing that survives a restart
// is the dnd/grouped pair persisted by PrefsStore.
//
// The D-Bus lifecycle also mirrors dunst: a timed-out notification is closed
// with expire() (NotificationClosed reason 1), a hidden or evicted toast is
// closed with dismiss() (reason 2). Both land in _onLiveClosed(), which strips
// the live handle from the history row and destroys its LiveWatcher, so no
// tracked notification leaks and `notify-send --wait` never hangs.
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

    // ---------------------------------------------------------------------
    // Tunables
    // ---------------------------------------------------------------------

    readonly property int defaultTimeoutMs: 10000
    readonly property int duplicateWindowMs: 10000
    readonly property int maxToasts: 20
    readonly property int maxHistory: 200
    readonly property int maxLiveWatchers: 50
    readonly property int maxSummaryLen: 512
    readonly property int maxBodyLen: 4096
    readonly property int maxAppNameLen: 128

    // Internal bookkeeping (never persisted).
    property int _seq: 0
    property var _watchers: ({})
    property var _watcherOrder: []
    property var _dismissQueue: []
    property int _dismissIndex: 0

    onPanelOpenChanged: {
        if (root.panelOpen)
            root.unreadCount = 0;
    }

    onDndChanged: prefs.scheduleSave(root.dnd, root.grouped)
    onGroupedChanged: prefs.scheduleSave(root.dnd, root.grouped)

    // ---------------------------------------------------------------------
    // Contract API
    // ---------------------------------------------------------------------

    function togglePanel(): void {
        root.panelOpen = !root.panelOpen;
    }

    function openPanel(): void {
        // unreadCount is cleared by onPanelOpenChanged.
        root.panelOpen = true;
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
        root._removeToast(uid);
        const notif = root._liveNotifOf(uid);
        if (notif)
            notif.dismiss();
        else
            root._destroyWatcher(uid);
    }

    function hideAllToasts(): void {
        const arr = root._asArray(root.toasts);
        const notifs = [];
        for (let i = 0; i < arr.length; i++) {
            const notif = root._liveNotifOf(arr[i].uid);
            if (notif)
                notifs.push(notif);
            else
                root._destroyWatcher(arr[i].uid);
        }
        root.toasts = [];
        root._enqueueDismiss(notifs);
    }

    function dismissEntry(uid: string): void {
        root.hideToast(uid);
    }

    function removeHistory(uid: string): void {
        root.hideToast(uid);
        root._removeHistory(uid);
    }

    function clearHistory(): void {
        const queue = [];
        const uids = Object.keys(root._watchers);
        for (let i = 0; i < uids.length; i++) {
            const watcher = root._watchers[uids[i]];
            if (watcher && watcher.notif)
                queue.push(watcher.notif);
            root._destroyWatcher(uids[i]);
        }

        root.history = [];
        root.toasts = [];
        root.unreadCount = 0;

        // Dismissing hundreds of notifications synchronously would block the UI
        // thread; the batch timer drains them one per tick.
        root._enqueueDismiss(queue);
    }

    function invokeAction(uid: string, identifier: string): void {
        const notif = root._liveNotifOf(uid);
        if (!notif)
            return;

        const actions = notif.actions;
        if (!actions || actions.length === 0)
            return;

        if (identifier.length > 0) {
            for (let i = 0; i < actions.length; i++) {
                if (String(actions[i].identifier) === identifier) {
                    actions[i].invoke();
                    return;
                }
            }
            return;
        }

        // No explicit identifier: prefer the spec's default action, then the
        // "no identifier" action, then the first one offered.
        for (let i = 0; i < actions.length; i++) {
            const id = String(actions[i].identifier);
            if (id === "default" || id === "") {
                actions[i].invoke();
                return;
            }
        }
        actions[0].invoke();
    }

    function openFirstUrl(uid: string): void {
        const entry = root._findEntry(uid);
        if (!entry)
            return;

        const text = String(entry.body || "") + "\n" + String(entry.summary || "");
        const match = text.match(/https?:\/\/[^\s<>"')\]]+/);
        if (match)
            root.openUrl(match[0]);
    }

    // Only http(s)/mailto ever reach xdg-open: a notification is untrusted
    // input, and `file://` or `javascript:` would be a live local file read or
    // handler hijack.
    function openUrl(url: string): bool {
        const trimmed = String(url || "").trim();
        if (trimmed.length === 0)
            return false;
        if (/[\x00-\x1f\x7f]/.test(trimmed))
            return false;
        if (!/^(https?:\/\/|mailto:)/i.test(trimmed))
            return false;
        Quickshell.execDetached(["xdg-open", trimmed]);
        return true;
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
    // Shared view helpers
    // ---------------------------------------------------------------------

    // dunst's `follow = keyboard`: toasts/panel only exist on the focused
    // monitor, falling back to the first screen when Hyprland has no answer.
    function isFocusedScreen(screen: ShellScreen): bool {
        const focused = Hyprland.focusedMonitor;
        if (screen && focused && focused.name !== undefined)
            return String(screen.name) === String(focused.name);
        const screens = Quickshell.screens;
        return screens !== null && screens !== undefined
                && screens.length > 0 && screen === screens[0];
    }

    function isCritical(urgency: int): bool {
        return urgency >= NotificationUrgency.Critical;
    }

    function isLow(urgency: int): bool {
        return urgency <= NotificationUrgency.Low;
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

        onNotification: function (n): void {
            root._ingest(n);
        }
    }

    // ---------------------------------------------------------------------
    // Ingestion / coalescing
    // ---------------------------------------------------------------------

    function _ingest(n): void {
        if (!n)
            return;

        // Bastion "base station connected" notifications (dunstrc skip_display
        // + history_ignore) are dropped before anything else happens.
        if (/^LHB-/.test(String(n.summary || ""))) {
            n.dismiss();
            return;
        }

        // Must be synchronous: untracked notifications are destroyed when the
        // server returns from Notify().
        n.tracked = true;

        const stackTag = root._stackTagOf(n);
        const appName = root._truncate(n.appName, root.maxAppNameLen);
        const summary = root._truncate(n.summary, root.maxSummaryLen);
        const body = root._truncate(n.body, root.maxBodyLen);
        const urgency = Number(n.urgency);

        // x-dunst-stack-tag coalescing: replace the prior card/history slot.
        // The tag is matched together with the app name so two different
        // applications cannot spoof each other's slot.
        if (stackTag.length > 0) {
            let uid = "";
            const toasts = root._asArray(root.toasts);
            for (let i = 0; i < toasts.length; i++) {
                if (toasts[i].stackTag === stackTag && toasts[i].appName === appName) {
                    uid = toasts[i].uid;
                    break;
                }
            }
            if (uid.length === 0) {
                const records = root._asArray(root.history);
                for (let i = 0; i < records.length; i++) {
                    if (records[i].stackTag === stackTag && records[i].appName === appName) {
                        uid = records[i].uid;
                        break;
                    }
                }
            }

            if (uid.length > 0) {
                const existing = root._findEntry(uid);
                const oldNotif = root._liveNotifOf(uid);
                root._destroyWatcher(uid);
                if (oldNotif && oldNotif !== n)
                    oldNotif.dismiss();

                // One entry feeds both lists so their duplicateCount and
                // timestamp can never drift apart.
                const entry = root._buildEntry(n, uid, existing);
                entry.timestamp = Date.now();

                if (!entry.transient) {
                    // A refreshed stack slot is the newest event in history, so
                    // it moves to the front instead of keeping the old index.
                    const rest = root._removeByUid(root.history, uid);
                    root.history = root._upsertByUid(rest, Object.assign({}, entry)).slice(0, root.maxHistory);
                }

                if (root._shouldShowToast(urgency))
                    root._putToast(Object.assign({}, entry));
                else
                    root._removeToast(uid);

                root._attachWatcher(uid, n);
                return;
            }
        }

        // Idempotent duplicate stacking (same app/summary/body within 10 s).
        const candidates = root._asArray(root.toasts);
        for (let i = 0; i < candidates.length; i++) {
            const toast = candidates[i];
            if (toast.appName === appName && toast.summary === summary && toast.body === body
                    && Number(toast.urgency) === urgency
                    && (Date.now() - Number(toast.timestamp)) < root.duplicateWindowMs) {
                const nextCount = Math.max(1, Number(toast.duplicateCount) || 1) + 1;

                const toastsNow = root._asArray(root.toasts).slice();
                toastsNow[i] = Object.assign({}, toastsNow[i], { "duplicateCount": nextCount });
                root.toasts = toastsNow;

                const recordIndex = root._indexOfUid(root.history, toast.uid);
                if (recordIndex >= 0) {
                    const records = root._asArray(root.history).slice();
                    records[recordIndex] = Object.assign({}, records[recordIndex], { "duplicateCount": nextCount });
                    root.history = records;
                }

                const watcher = root._watchers[toast.uid];
                if (watcher)
                    watcher.resetTimer(root._timeoutMs(n));

                n.dismiss();
                return;
            }
        }

        // Fresh notification.
        const uid = root._nextUid();
        const entry = root._buildEntry(n, uid, null);

        if (!entry.transient)
            root._putHistoryRecord(Object.assign({}, entry));
        if (root._shouldShowToast(urgency))
            root._putToast(Object.assign({}, entry));

        root._attachWatcher(uid, n);

        if (!root.panelOpen && !entry.transient)
            root.unreadCount += 1;
    }

    function _shouldShowToast(urgency: int): bool {
        if (!root.dnd)
            return true;
        return urgency >= NotificationUrgency.Critical;
    }

    // ---------------------------------------------------------------------
    // Live watcher lifecycle (dunst parity, FIFO capped)
    // ---------------------------------------------------------------------

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
        if (root._watcherOrder.indexOf(uid) === -1)
            root._watcherOrder = root._asArray(root._watcherOrder).concat([uid]);

        watcher.startTimer(root._timeoutMs(n));
        root._enforceWatcherCap();
    }

    function _destroyWatcher(uid: string): void {
        const order = root._asArray(root._watcherOrder);
        if (order.indexOf(uid) !== -1)
            root._watcherOrder = order.filter(item => item !== uid);

        const watcher = root._watchers[uid];
        if (!watcher)
            return;

        watcher.teardown();
        delete root._watchers[uid];
        watcher.destroy();
    }

    // Tracked notifications are retained by the server until they are closed,
    // so the live set is bounded: the oldest handle is expired and its history
    // row goes inert.
    function _enforceWatcherCap(): void {
        while (root._watcherOrder.length > root.maxLiveWatchers) {
            const uid = String(root._watcherOrder[0]);
            root._watcherOrder = root._watcherOrder.slice(1);

            const watcher = root._watchers[uid];
            const notif = watcher && watcher.notif ? watcher.notif : null;

            root._markHistoryInert(uid);
            root._removeToast(uid);
            root._destroyWatcher(uid);
            if (notif)
                notif.expire();
        }
    }

    // Replace a history row with an inert clone: no live handle, no D-Bus id,
    // no actions, and no pixmap URI (those only exist while tracked).
    function _markHistoryInert(uid: string): void {
        const index = root._indexOfUid(root.history, uid);
        if (index < 0)
            return;

        const records = root._asArray(root.history).slice();
        const record = records[index];
        const image = typeof record.image === "string"
                && record.image.indexOf("image://qsimage/") === 0 ? "" : record.image;
        records[index] = Object.assign({}, record, {
                "liveNotif": null,
                "dbusId": 0,
                "actions": [],
                "image": image
            });
        root.history = records;
    }

    function _handleExpiry(uid: string): void {
        root._removeToast(uid);

        const watcher = root._watchers[uid];
        if (!watcher)
            return;

        if (watcher.notif) {
            // Both transient and non-transient notifications are closed on the
            // bus; onClosed then marks the history row inert.
            watcher.notif.expire();
            return;
        }

        root._markHistoryInert(uid);
        root._destroyWatcher(uid);
    }

    function _onLiveClosed(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher)
            return;

        // Pick up anything the notification changed just before closing, then
        // strip the live handle so the row stays a pure history record.
        const notif = watcher.notif;
        if (notif)
            root._syncFromNotif(uid, notif);

        root._markHistoryInert(uid);
        root._removeToast(uid);
        root._destroyWatcher(uid);
    }

    // The server (and once-cancelled notify-send --wait) must see a close for
    // everything we drop, so dismissals are queued instead of dropped or run
    // in one blocking burst.
    function _enqueueDismiss(notifs): void {
        const items = root._asArray(notifs);
        const queue = [];
        for (let i = 0; i < items.length; i++) {
            if (items[i])
                queue.push(items[i]);
        }
        if (queue.length === 0)
            return;

        root._dismissQueue = root._asArray(root._dismissQueue).concat(queue);
        if (!dismissBatchTimer.running)
            dismissBatchTimer.start();
    }

    // ---------------------------------------------------------------------
    // Live notification changes (replaces_id lands here, not in _ingest)
    // ---------------------------------------------------------------------

    function _onNotifUpdated(uid: string): void {
        const watcher = root._watchers[uid];
        if (!watcher || !watcher.notif)
            return;
        root._syncFromNotif(uid, watcher.notif);
        watcher.resetTimer(root._timeoutMs(watcher.notif));
    }

    function _syncFromNotif(uid: string, n): void {
        let toastChanged = false;
        const toasts = root._asArray(root.toasts).slice();
        for (let i = 0; i < toasts.length; i++) {
            if (toasts[i].uid !== uid)
                continue;
            toasts[i] = root._buildEntry(n, uid, toasts[i]);
            toastChanged = true;
        }
        if (toastChanged)
            root.toasts = root._sortToasts(toasts);

        let historyChanged = false;
        const records = root._asArray(root.history).slice();
        for (let i = 0; i < records.length; i++) {
            if (records[i].uid !== uid)
                continue;
            records[i] = root._buildEntry(n, uid, records[i]);
            historyChanged = true;
        }
        if (historyChanged)
            root.history = records;
    }

    // ---------------------------------------------------------------------
    // Entry construction / sanitizing
    // ---------------------------------------------------------------------

    function _buildEntry(n, uid: string, prev): var {
        return {
            "uid": uid,
            "dbusId": Number(n.id) || 0,
            "stackTag": root._stackTagOf(n),
            "appName": root._truncate(n.appName, root.maxAppNameLen),
            "appIcon": root._sanitizeAppIcon(n.appIcon),
            "image": root._sanitizeImage(n.image),
            "summary": root._truncate(n.summary, root.maxSummaryLen),
            "body": root._truncate(n.body, root.maxBodyLen),
            "urgency": Number(n.urgency),
            "progress": root._progressOf(n),
            "timestamp": prev && prev.timestamp ? Number(prev.timestamp) : Date.now(),
            "duplicateCount": prev ? Math.max(1, Number(prev.duplicateCount) || 1) : 1,
            "transient": n.transient === true,
            "actions": root._actionsOf(n),
            "liveNotif": n
        };
    }

    function _truncate(value, maxLen: int): string {
        return String(value || "").slice(0, maxLen);
    }

    // Only a small set of browser-side paths may ever be handed to the image
    // loader: pixmaps from the bus arrive as image://qsimage/, icons are looked
    // up through Quickshell.iconPath(), and a file:// URL must point at a
    // scratch/cache/store location with no traversal.
    function _isSafeLocalFile(url: string): bool {
        const s = String(url || "");
        if (s.indexOf("file://") !== 0)
            return false;

        let path = "";
        try {
            path = decodeURIComponent(s.slice("file://".length));
        } catch (e) {
            return false;
        }

        if (/[\x00-\x1f\x7f]/.test(path))
            return false;
        if (path.indexOf("/../") !== -1 || path.slice(-3) === "/.." || path === "..")
            return false;

        const prefixes = ["/tmp/", "/run/user/", "/nix/store/", "/usr/share/", "/run/current-system/sw/share/"];
        const home = String(Quickshell.env("HOME") || "");
        const xdgCache = String(Quickshell.env("XDG_CACHE_HOME") || "");
        if (home.length > 0)
            prefixes.push(home + "/.cache/");
        if (xdgCache.length > 0)
            prefixes.push(xdgCache + "/");

        for (let i = 0; i < prefixes.length; i++) {
            if (path.indexOf(prefixes[i]) === 0)
                return true;
        }
        return false;
    }

    function _sanitizeImage(raw): string {
        const s = String(raw || "");
        if (s.length === 0)
            return "";

        // Live D-Bus pixmap; valid only while the notification is tracked.
        if (s.indexOf("image://qsimage/") === 0)
            return s;

        // An image://icon/?path=/etc/... URL is a file-read vector, and a name
        // that resolves to nothing renders as the magenta/black checkerboard.
        if (s.indexOf("image://icon/") === 0) {
            const name = s.slice("image://icon/".length);
            if (name.length === 0 || name.indexOf("?") !== -1
                    || name.indexOf("/") !== -1 || name.indexOf("..") !== -1)
                return "";
            return String(Quickshell.iconPath(name, true) || "");
        }

        if (s.indexOf("file://") === 0)
            return root._isSafeLocalFile(s) ? s : "";

        if (s.indexOf("?") !== -1 || s.indexOf("/") !== -1 || s.indexOf("..") !== -1)
            return "";
        return String(Quickshell.iconPath(s, true) || "");
    }

    function _sanitizeAppIcon(raw): string {
        const s = String(raw || "");
        if (s.length === 0)
            return "";

        if (s.indexOf("file://") === 0)
            return root._isSafeLocalFile(s) ? s : "";

        if (s.charAt(0) === "/") {
            const url = "file://" + s;
            return root._isSafeLocalFile(url) ? url : "";
        }

        if (s.indexOf("?") !== -1 || s.indexOf("..") !== -1)
            return "";
        return String(Quickshell.iconPath(s, true) || "");
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
            return root.isCritical(Number(n.urgency)) ? 0 : root.defaultTimeoutMs;
        if (timeout === 0)
            return 0;
        return Math.max(0, Math.round(timeout));
    }

    function _nextUid(): string {
        root._seq += 1;
        return "n" + Date.now().toString(36) + "-" + root._seq;
    }

    // ---------------------------------------------------------------------
    // List helpers
    // ---------------------------------------------------------------------

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

    function _indexOfUid(arr, uid: string): int {
        const items = root._asArray(arr);
        for (let i = 0; i < items.length; i++) {
            if (items[i].uid === uid)
                return i;
        }
        return -1;
    }

    function _removeByUid(arr, uid: string): var {
        const items = root._asArray(arr);
        const out = [];
        for (let i = 0; i < items.length; i++) {
            if (items[i].uid !== uid)
                out.push(items[i]);
        }
        return out;
    }

    function _upsertByUid(arr, item): var {
        const items = root._asArray(arr).slice();
        if (!item)
            return items;
        const index = root._indexOfUid(items, item.uid);
        if (index >= 0)
            items[index] = item;
        else
            items.unshift(item);
        return items;
    }

    function _findEntry(uid: string): var {
        let index = root._indexOfUid(root.toasts, uid);
        if (index >= 0)
            return root._asArray(root.toasts)[index];
        index = root._indexOfUid(root.history, uid);
        if (index >= 0)
            return root._asArray(root.history)[index];
        return null;
    }

    function _liveNotifOf(uid: string): var {
        const watcher = root._watchers[uid];
        if (watcher && watcher.notif)
            return watcher.notif;
        const entry = root._findEntry(uid);
        return entry && entry.liveNotif ? entry.liveNotif : null;
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

        if (sorted.length <= root.maxToasts)
            return sorted;

        // Overflow is dismissed, not silently dropped: each evicted card closes
        // its notification on the bus, which also makes its history row inert.
        const evicted = sorted.slice(root.maxToasts);
        const notifs = [];
        for (let i = 0; i < evicted.length; i++) {
            const notif = root._liveNotifOf(evicted[i].uid);
            if (notif)
                notifs.push(notif);
            else
                root._destroyWatcher(evicted[i].uid);
        }
        root._enqueueDismiss(notifs);
        return sorted.slice(0, root.maxToasts);
    }

    function _putToast(entry): void {
        root.toasts = root._sortToasts(root._upsertByUid(root.toasts, entry));
    }

    function _putHistoryRecord(record): void {
        root.history = root._upsertByUid(root.history, record).slice(0, root.maxHistory);
    }

    function _removeToast(uid: string): void {
        if (root._indexOfUid(root.toasts, uid) < 0)
            return;
        root.toasts = root._removeByUid(root.toasts, uid);
    }

    function _removeHistory(uid: string): void {
        if (root._indexOfUid(root.history, uid) < 0)
            return;
        root.history = root._removeByUid(root.history, uid);
    }

    // ---------------------------------------------------------------------
    // Children
    // ---------------------------------------------------------------------

    PrefsStore {
        id: prefs
        onRestored: function (savedDnd, savedGrouped) {
            root.dnd = savedDnd;
            root.grouped = savedGrouped;
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
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

        LiveWatcher {}
    }
}
