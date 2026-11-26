// HistoryPanel.qml — the wider right-anchored notification centre.
//
// 440 px card on the focused Hyprland monitor, opened with SUPER+SHIFT+N
// (`qs ipc call notifs toggle`). Supports grouped and flat history views,
// keyboard navigation, do-not-disturb, and per-notification actions while a
// notification is still live.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.components

Item {
    id: root

    Variants {
        model: Quickshell.screens

        // qmllint disable uncreatable-type
        delegate: PanelWindow {
            id: panelWindow
            property var modelData

            // Same focused-monitor rule as the toast stack.
            readonly property bool isTargetScreen: {
                var focused = Hyprland.focusedMonitor;
                if (focused !== null && focused !== undefined && focused.name !== undefined)
                    return modelData.name === focused.name;
                return Quickshell.screens.length > 0 && modelData === Quickshell.screens[0];
            }

            readonly property int historyCount: {
                var history = Notifs.history;
                return history ? history.length : 0;
            }

            // App names whose groups are collapsed (reassigned, never mutated,
            // so the bindings below re-evaluate).
            property var collapsedApps: []

            property int selectedIndex: -1

            // Bumped periodically so relative ages in the cards stay fresh.
            property int ageTick: 0

            // [{ key, entries, latest }], newest group first.
            readonly property var groups: {
                if (!Notifs.grouped)
                    return [];
                var history = Notifs.history;
                if (!history)
                    return [];
                var map = ({});
                var order = [];
                for (var i = 0; i < history.length; i++) {
                    var item = history[i];
                    var label = item && item.appName !== undefined && item.appName !== null && String(item.appName) !== "" ? String(item.appName) : "General";
                    if (map[label] === undefined) {
                        map[label] = {
                            key: label,
                            entries: [],
                            latest: 0
                        };
                        order.push(label);
                    }
                    map[label].entries.push(item);
                    var stamp = item && item.timestamp !== undefined && item.timestamp !== null ? Number(item.timestamp) : 0;
                    if (stamp > map[label].latest)
                        map[label].latest = stamp;
                }
                var result = [];
                for (var j = 0; j < order.length; j++)
                    result.push(map[order[j]]);
                result.sort(function (a, b) {
                    return b.latest - a.latest;
                });
                return result;
            }

            // Flattened list of what the panel currently shows, in render
            // order — this is what j/k walks through.
            readonly property var visibleEntries: {
                var output = [];
                var history = Notifs.history;
                if (!history)
                    return output;
                if (!Notifs.grouped) {
                    for (var i = 0; i < history.length; i++)
                        output.push(history[i]);
                    return output;
                }
                var groupList = groups;
                for (var g = 0; g < groupList.length; g++) {
                    if (collapsedApps.indexOf(groupList[g].key) !== -1)
                        continue;
                    var entries = groupList[g].entries;
                    for (var k = 0; k < entries.length; k++)
                        output.push(entries[k]);
                }
                return output;
            }

            readonly property string selectedUid: {
                var list = visibleEntries;
                if (selectedIndex < 0 || selectedIndex >= list.length)
                    return "";
                return entryUid(list[selectedIndex]);
            }

            function entryUid(item) {
                if (!item || item.uid === undefined || item.uid === null)
                    return "";
                return String(item.uid);
            }

            function isSelected(item) {
                var uid = entryUid(item);
                return uid !== "" && uid === selectedUid;
            }

            function toggleGroup(key) {
                var next = collapsedApps.slice();
                var at = next.indexOf(key);
                if (at === -1)
                    next.push(key);
                else
                    next.splice(at, 1);
                collapsedApps = next;
            }

            function clearGroup(entries) {
                if (!entries)
                    return;
                for (var i = 0; i < entries.length; i++) {
                    var uid = entryUid(entries[i]);
                    if (uid !== "")
                        Notifs.removeHistory(uid);
                }
                selectedIndex = -1;
            }

            function moveSelection(delta) {
                var list = visibleEntries;
                if (list.length === 0) {
                    selectedIndex = -1;
                    return;
                }
                var next = selectedIndex < 0 ? (delta > 0 ? 0 : list.length - 1) : selectedIndex + delta;
                if (next < 0)
                    next = 0;
                if (next > list.length - 1)
                    next = list.length - 1;
                selectedIndex = next;
            }

            function activateSelected() {
                var list = visibleEntries;
                if (selectedIndex < 0 || selectedIndex >= list.length)
                    return;
                var item = list[selectedIndex];
                var uid = entryUid(item);
                if (uid === "")
                    return;
                if (item.liveNotif !== undefined && item.liveNotif !== null)
                    Notifs.invokeAction(uid, "");
                else
                    Notifs.openFirstUrl(uid);
            }

            function removeSelected() {
                var uid = selectedUid;
                if (uid === "")
                    return;
                Notifs.removeHistory(uid);
                var list = visibleEntries;
                if (selectedIndex > list.length - 1)
                    selectedIndex = list.length - 1;
            }

            screen: modelData
            visible: isTargetScreen && Notifs.panelOpen

            anchors {
                top: true
                bottom: true
                right: true
            }
            // Quickshell 0.3.2 marks Margins isTypeOpaque in _Window/quickshell-window.qmltypes
            // (fields live in quickshell-core.qmltypes), so qmllint flags top/bottom/right.
            // qmllint disable missing-property
            margins {
                top: 40
                bottom: 12
                right: 10
            }
            // qmllint enable missing-property

            implicitWidth: 440
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true

            WlrLayershell.namespace: "qs-notifs-panel"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: Notifs.panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            onVisibleChanged: {
                if (!visible)
                    selectedIndex = -1;
            }

            HyprlandFocusGrab {
                id: focusGrab
                windows: [panelWindow]
                active: panelWindow.visible
                onCleared: Notifs.closePanel()
            }

            Timer {
                interval: 30000
                repeat: true
                running: panelWindow.visible
                onTriggered: panelWindow.ageTick += 1
            }

            FocusScope {
                id: focusScope
                anchors.fill: parent
                focus: panelWindow.visible

                Keys.onPressed: function (event) {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        Notifs.closePanel();
                        event.accepted = true;
                        break;
                    case Qt.Key_J:
                    case Qt.Key_Down:
                        panelWindow.moveSelection(1);
                        event.accepted = true;
                        break;
                    case Qt.Key_K:
                    case Qt.Key_Up:
                        panelWindow.moveSelection(-1);
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        panelWindow.activateSelected();
                        event.accepted = true;
                        break;
                    case Qt.Key_X:
                    case Qt.Key_Delete:
                        panelWindow.removeSelected();
                        event.accepted = true;
                        break;
                    case Qt.Key_D:
                        Notifs.toggleDnd();
                        event.accepted = true;
                        break;
                    case Qt.Key_G:
                        Notifs.grouped = !Notifs.grouped;
                        panelWindow.selectedIndex = -1;
                        event.accepted = true;
                        break;
                    case Qt.Key_C:
                        if (event.modifiers & Qt.ShiftModifier) {
                            Notifs.clearHistory();
                            panelWindow.selectedIndex = -1;
                            event.accepted = true;
                        }
                        break;
                    }
                }

                Rectangle {
                    id: card
                    anchors.fill: parent
                    radius: 12
                    color: Theme.col("base")
                    border.width: 2
                    border.color: Theme.col("mauve")

                    // ---- header -------------------------------------------------
                    Rectangle {
                        id: header
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                            topMargin: card.border.width
                            leftMargin: card.border.width
                            rightMargin: card.border.width
                        }
                        height: 46
                        radius: 11
                        color: Theme.col("mantle")

                        // Square off the bottom corners of the header.
                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            height: parent.radius
                            color: parent.color
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Notifications"
                                color: Theme.col("text")
                                font.family: Theme.fontFamily
                                font.pointSize: Theme.fontSize + 1
                                font.bold: true
                            }

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                radius: 8
                                implicitWidth: countLabel.implicitWidth + 12
                                implicitHeight: 18
                                color: Theme.alpha("mauve", 0.2)

                                Text {
                                    id: countLabel
                                    anchors.centerIn: parent
                                    text: String(panelWindow.historyCount)
                                    color: Theme.col("mauve")
                                    font.family: Theme.fontFamily
                                    font.pointSize: Math.max(8, Theme.fontSize - 2)
                                    font.bold: true
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            // Do-not-disturb pill
                            Rectangle {
                                id: dndPill
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: dndLabel.implicitWidth + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: Notifs.dnd ? Theme.alpha("peach", 0.2) : Theme.col("surface0")
                                border.width: 1
                                border.color: Notifs.dnd ? Theme.col("peach") : Theme.col("surface1")

                                Text {
                                    id: dndLabel
                                    anchors.centerIn: parent
                                    text: "DND"
                                    color: Notifs.dnd ? Theme.col("peach") : Theme.col("overlay1")
                                    font.family: Theme.fontFamily
                                    font.pointSize: Math.max(8, Theme.fontSize - 2)
                                    font.bold: Notifs.dnd
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.toggleDnd()
                                }
                            }

                            // Grouped / flat pill
                            Rectangle {
                                id: groupPill
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: groupLabel.implicitWidth + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: Notifs.grouped ? Theme.alpha("mauve", 0.2) : Theme.col("surface0")
                                border.width: 1
                                border.color: Notifs.grouped ? Theme.col("mauve") : Theme.col("surface1")

                                Text {
                                    id: groupLabel
                                    anchors.centerIn: parent
                                    text: Notifs.grouped ? "Grouped" : "Flat"
                                    color: Notifs.grouped ? Theme.col("mauve") : Theme.col("overlay1")
                                    font.family: Theme.fontFamily
                                    font.pointSize: Math.max(8, Theme.fontSize - 2)
                                    font.bold: Notifs.grouped
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Notifs.grouped = !Notifs.grouped;
                                        panelWindow.selectedIndex = -1;
                                    }
                                }
                            }

                            // Clear all
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: clearLabel.implicitWidth + 16
                                Layout.preferredHeight: 22
                                radius: 11
                                color: clearMouse.containsMouse ? Theme.alpha("surface2", 0.9) : "transparent"
                                border.width: 1
                                border.color: Theme.col("surface1")

                                Text {
                                    id: clearLabel
                                    anchors.centerIn: parent
                                    text: "Clear All"
                                    color: Theme.col("subtext0")
                                    font.family: Theme.fontFamily
                                    font.pointSize: Math.max(8, Theme.fontSize - 2)
                                }

                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Notifs.clearHistory();
                                        panelWindow.selectedIndex = -1;
                                    }
                                }
                            }

                            // Close
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 11
                                color: closeMouse.containsMouse ? Theme.alpha("red", 0.25) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "✕"
                                    color: Theme.col("overlay2")
                                    font.family: Theme.fontFamily
                                    font.pointSize: Theme.fontSize
                                }

                                MouseArea {
                                    id: closeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.closePanel()
                                }
                            }
                        }
                    }

                    // ---- body ---------------------------------------------------
                    Flickable {
                        id: bodyFlick
                        anchors {
                            top: header.bottom
                            left: parent.left
                            right: parent.right
                            bottom: footer.top
                            topMargin: 8
                            bottomMargin: 6
                            leftMargin: 10
                            rightMargin: 10
                        }
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: bodyColumn.implicitHeight

                        Column {
                            id: bodyColumn
                            width: bodyFlick.width
                            spacing: 6

                            // Grouped by application, newest group first.
                            Column {
                                id: groupedColumn
                                width: parent.width
                                visible: Notifs.grouped
                                spacing: 8

                                Repeater {
                                    model: panelWindow.groups

                                    delegate: Column {
                                        id: groupBlock
                                        required property var modelData

                                        readonly property var groupData: modelData
                                        readonly property bool collapsed: panelWindow.collapsedApps.indexOf(groupData.key) !== -1

                                        width: groupedColumn.width
                                        spacing: 4

                                        Rectangle {
                                            width: parent.width
                                            height: 24
                                            radius: 6
                                            color: groupHeaderMouse.containsMouse ? Theme.alpha("surface1", 0.9) : "transparent"

                                            MouseArea {
                                                id: groupHeaderMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                onClicked: panelWindow.toggleGroup(groupBlock.groupData.key)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 6
                                                anchors.rightMargin: 4
                                                spacing: 6

                                                Text {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: groupBlock.collapsed ? "▸" : "▾"
                                                    color: Theme.col("overlay1")
                                                    font.family: Theme.fontFamily
                                                    font.pointSize: Math.max(8, Theme.fontSize - 1)
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.alignment: Qt.AlignVCenter
                                                    text: groupBlock.groupData.key + "  ·  " + groupBlock.groupData.entries.length
                                                    color: Theme.col("subtext0")
                                                    font.family: Theme.fontFamily
                                                    font.pointSize: Math.max(8, Theme.fontSize - 1)
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    maximumLineCount: 1
                                                }

                                                Rectangle {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    Layout.preferredWidth: 18
                                                    Layout.preferredHeight: 18
                                                    radius: 9
                                                    color: groupClearMouse.containsMouse ? Theme.alpha("surface2", 0.9) : "transparent"

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✕"
                                                        color: Theme.col("overlay1")
                                                        font.family: Theme.fontFamily
                                                        font.pointSize: Math.max(8, Theme.fontSize - 2)
                                                    }

                                                    MouseArea {
                                                        id: groupClearMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: panelWindow.clearGroup(groupBlock.groupData.entries)
                                                    }
                                                }
                                            }
                                        }

                                        Column {
                                            width: groupBlock.width
                                            spacing: 4
                                            visible: !groupBlock.collapsed

                                            Repeater {
                                                model: groupBlock.groupData.entries

                                                delegate: ToastCard {
                                                    required property var modelData

                                                    width: groupBlock.width
                                                    compact: true
                                                    entry: modelData
                                                    selected: panelWindow.isSelected(modelData)
                                                    tick: panelWindow.ageTick
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Flat chronological (newest first).
                            Column {
                                id: flatColumn
                                width: parent.width
                                visible: !Notifs.grouped
                                spacing: 6

                                Repeater {
                                    model: Notifs.history

                                    delegate: ToastCard {
                                        required property var modelData

                                        width: flatColumn.width
                                        compact: true
                                        entry: modelData
                                        selected: panelWindow.isSelected(modelData)
                                        tick: panelWindow.ageTick
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: emptyState
                        anchors.centerIn: bodyFlick
                        text: Notifs.dnd ? "Do Not Disturb is on" : "No notifications"
                        color: Theme.col("overlay1")
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize
                        visible: panelWindow.historyCount === 0
                    }

                    // ---- footer -------------------------------------------------
                    Rectangle {
                        id: footer
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                            leftMargin: card.border.width
                            rightMargin: card.border.width
                            bottomMargin: card.border.width
                        }
                        height: 24
                        radius: 9
                        color: Theme.col("mantle")

                        // Square off the top corners of the footer.
                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                            }
                            height: parent.radius
                            color: parent.color
                        }

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 20
                            horizontalAlignment: Text.AlignHCenter
                            text: "j/k nav · Enter action · x del · d DND · g group · C clear · Esc close"
                            color: Theme.col("overlay1")
                            font.family: Theme.fontFamily
                            font.pointSize: 9
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
        // qmllint enable uncreatable-type
    }
}
