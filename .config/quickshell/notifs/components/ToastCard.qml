pragma ComponentBehavior: Bound

// ToastCard.qml — one notification card.
//
// Shared by the toast stack (compact: false) and the history centre
// (compact: true). All colours come from the Catppuccin palette exposed by the
// Theme singleton, so light/dark switches are picked up live.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.components

Rectangle {
    id: card

    // Live notification wrapper or inert history record (see Notifs.qml).
    required property var entry

    // Compact rendering for the history centre (thin cards on a base panel).
    property bool compact: false

    // Selection highlight (history centre keyboard navigation).
    property bool selected: false

    readonly property int pad: compact ? 8 : 10

    // ---- entry field access -------------------------------------------------

    function field(name, fallback) {
        if (entry === null || entry === undefined)
            return fallback;
        var value = entry[name];
        return value === undefined || value === null ? fallback : value;
    }

    readonly property string uid: String(field("uid", ""))
    readonly property string summary: String(field("summary", ""))
    readonly property string body: String(field("body", ""))
    readonly property string appName: String(field("appName", ""))
    readonly property string appIcon: String(field("appIcon", ""))
    readonly property string image: String(field("image", ""))
    readonly property int urgency: Number(field("urgency", 1))
    readonly property int progress: Number(field("progress", -1))
    readonly property int duplicateCount: Number(field("duplicateCount", 1))
    readonly property real timestamp: Number(field("timestamp", 0))
    readonly property var liveNotif: field("liveNotif", null)
    readonly property var actions: {
        var list = field("actions", []);
        return list === null || list === undefined ? [] : list;
    }
    readonly property bool hasActions: liveNotif !== null && liveNotif !== undefined && actions.length > 0

    readonly property bool isCritical: Notifs.isCritical(card.urgency)
    readonly property bool isLow: Notifs.isLow(card.urgency)

    // ---- colours ------------------------------------------------------------

    readonly property string accentName: Theme.urgencyRole(card.urgency)
    readonly property color accentColor: Theme.col(card.accentName)

    readonly property color bgColor: {
        if (compact)
            return selected ? Theme.col("surface1") : Theme.col("surface0");
        if (isCritical)
            return Theme.col(Theme.criticalRole);
        if (isLow)
            return Theme.col("mantle");
        return Theme.col("base");
    }

    readonly property color fgColor: {
        if (compact)
            return isCritical ? Theme.col(Theme.criticalRole) : (isLow ? Theme.col("subtext0") : Theme.col("text"));
        if (isCritical)
            return Theme.col("base");
        if (isLow)
            return Theme.col("subtext0");
        return Theme.col("text");
    }

    readonly property color borderColor: {
        if (compact)
            return selected ? accentColor : Theme.col("surface1");
        return accentColor;
    }

    readonly property color metaColor: {
        if (compact)
            return Theme.col("overlay1");
        if (isCritical)
            return Theme.alpha("base", 0.7);
        return Theme.col("overlay1");
    }

    readonly property color chipColor: {
        if (compact)
            return Theme.alpha("surface2", 0.9);
        if (isCritical)
            return Theme.alpha("base", 0.2);
        return Theme.alpha("surface0", 0.9);
    }

    readonly property color trackColor: {
        if (compact)
            return Theme.col("surface1");
        if (isCritical)
            return Theme.alpha("base", 0.25);
        return Theme.alpha("surface1", 0.9);
    }

    readonly property color fillColor: {
        if (compact)
            return Theme.col(Theme.accentRole);
        return isCritical ? Theme.col("base") : Theme.col(Theme.accentRole);
    }

    // ---- text helpers -------------------------------------------------------

    // Relative age of the notification ("now", "5m", "3h", "2d"), kept live by
    // Notifs' clock so cards refresh without a per-card timer.
    readonly property string ageText: card.timestamp > 0 ? Notifs.formatAge(card.timestamp) : ""

    readonly property string metaLabel: {
        var age = card.ageText;
        if (card.appName !== "" && age !== "")
            return card.appName + " · " + age;
        return card.appName !== "" ? card.appName : age;
    }

    readonly property string summaryText: card.summary !== "" ? card.summary : (card.appName !== "" ? card.appName : "Notification")

    // Icon shown at the left of the card (client image first, then app icon).
    // Both fields were validated by Notifs._sanitizeImage/_sanitizeAppIcon.
    readonly property string iconSource: card.image !== "" ? card.image : card.appIcon

    // Full-width client pixmaps are rendered large; icons stay in a small box.
    readonly property bool hasImage: card.image !== "" && card.image.indexOf("image://icon/") !== 0

    // ---- markup sanitising --------------------------------------------------

    // Preserve the tags libnotify clients actually send (b, i, u, s, small, big,
    // tt, br and a-with-http/mailto-href) and escape everything else, so
    // malformed markup can neither break the StyledText renderer nor smuggle a
    // `file://` / `javascript:` link at xdg-open.
    function safeMarkup(text) {
        if (text === null || text === undefined)
            return "";
        var input = String(text);
        var output = "";
        var index = 0;
        while (index < input.length) {
            var ch = input.charAt(index);
            if (ch === "<") {
                var end = input.indexOf(">", index);
                if (end === -1) {
                    output += "&lt;";
                    index += 1;
                    continue;
                }
                var tag = input.substring(index + 1, end);
                output += card.sanitizeTag(tag);
                index = end + 1;
            } else if (ch === ">") {
                output += "&gt;";
                index += 1;
            } else {
                output += ch;
                index += 1;
            }
        }
        return output;
    }

    // Canonical, attribute-free markup for a single `<...>` tag body.
    function sanitizeTag(tag) {
        if (/^\/\s*a\s*$/i.test(tag))
            return "</a>";
        var allowed = tag.match(/^(\/)?\s*(b|i|u|s|small|big|tt|br)\s*(\/)?$/i);
        if (allowed) {
            var name = allowed[2].toLowerCase();
            if (name === "br")
                return "<br/>";
            return allowed[1] ? "</" + name + ">" : "<" + name + ">";
        }
        var anchor = tag.match(/^a\s+([\s\S]+)$/i);
        if (anchor) {
            var attrs = anchor[1];
            var hrefMatch = attrs.match(/\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')/i);
            var href = hrefMatch === null ? "" : (hrefMatch[1] !== undefined ? hrefMatch[1] : hrefMatch[2]);
            href = String(href).trim();
            if (href === "" || /[\x00-\x1f\x7f]/.test(href) || !/^(https?:\/\/|mailto:)/i.test(href))
                return "&lt;" + tag + "&gt;";
            // Escape the html-hostile characters without double-encoding
            // entities the client already wrote (e.g. `?a=1&amp;b=2`).
            var escaped = href.replace(/&(?!(?:amp|lt|gt|quot|apos|nbsp);|#\d+;|#x[0-9a-fA-F]+;)/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            return '<a href="' + escaped + '">';
        }
        return "&lt;" + tag + "&gt;";
    }

    // Identifier used for a plain left click: the default action when the
    // client provided one, otherwise the first available action.
    function defaultActionIdentifier() {
        var list = card.actions;
        if (list.length === 0)
            return "";
        for (var i = 0; i < list.length; i++) {
            var identifier = list[i] && list[i].identifier !== undefined && list[i].identifier !== null ? String(list[i].identifier) : "";
            if (identifier === "default" || identifier === "")
                return identifier;
        }
        var first = list[0] && list[0].identifier !== undefined && list[0].identifier !== null ? String(list[0].identifier) : "";
        return first;
    }

    radius: 12
    color: card.bgColor
    border.width: card.compact ? 1 : 2
    border.color: card.borderColor
    implicitWidth: Theme.toastWidth
    implicitHeight: layout.implicitHeight + 2 * card.pad

    // A delegate rebuilt mid-hover must not leave the watcher paused forever.
    Component.onDestruction: {
        if (!card.compact && cardMouse.containsMouse)
            Notifs.resumeToast(card.uid);
    }

    // Urgency accent bar, only drawn for the compact history cards.
    Rectangle {
        visible: card.compact
        width: 3
        radius: 1.5
        color: card.accentColor
        anchors {
            left: parent.left
            top: parent.top
            bottom: parent.bottom
            leftMargin: 1
            topMargin: 8
            bottomMargin: 8
        }
    }

    // Toast mouse parity with dunst: hover pauses, left does the default
    // action, middle opens the first URL, right hides every toast.
    MouseArea {
        id: cardMouse
        anchors.fill: parent
        enabled: !card.compact
        hoverEnabled: !card.compact
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onEntered: Notifs.pauseToast(card.uid)
        onExited: Notifs.resumeToast(card.uid)
        onClicked: function (ev) {
            if (card.compact)
                return;
            if (ev.button === Qt.LeftButton) {
                if (card.hasActions)
                    Notifs.invokeAction(card.uid, card.defaultActionIdentifier());
                else
                    Notifs.hideToast(card.uid);
            } else if (ev.button === Qt.MiddleButton) {
                Notifs.openFirstUrl(card.uid);
                Notifs.hideToast(card.uid);
            } else if (ev.button === Qt.RightButton) {
                Notifs.hideAllToasts();
            }
        }
    }

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: card.compact ? card.pad + 6 : card.pad
        anchors.rightMargin: card.pad
        anchors.topMargin: card.pad
        anchors.bottomMargin: card.pad
        spacing: card.compact ? 4 : 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                id: iconBox
                visible: iconImage.status === Image.Ready
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: card.hasImage ? 56 : 36
                Layout.preferredHeight: card.hasImage ? 56 : 36
                radius: 8
                clip: true
                color: card.isCritical && !card.compact ? Theme.alpha("base", 0.2) : Theme.alpha("surface1", 0.6)

                Image {
                    id: iconImage
                    anchors.fill: parent
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    source: card.iconSource
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: card.summaryText
                        color: card.fgColor
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSize
                        font.bold: true
                        textFormat: Text.PlainText
                        wrapMode: card.compact ? Text.NoWrap : Text.Wrap
                        maximumLineCount: card.compact ? 1 : 2
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: card.duplicateCount > 1
                        Layout.alignment: Qt.AlignVCenter
                        radius: 7
                        implicitWidth: duplicateLabel.implicitWidth + 10
                        implicitHeight: 16
                        color: card.chipColor

                        Text {
                            id: duplicateLabel
                            anchors.centerIn: parent
                            text: "x" + card.duplicateCount
                            color: card.metaColor
                            font.family: Theme.fontFamily
                            font.pointSize: Theme.fontTiny
                            font.bold: true
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: text !== ""
                        text: card.metaLabel
                        color: card.metaColor
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontTiny
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        buttonSize: 18
                        fontPointSize: Theme.fontSmall
                        glyphColor: card.metaColor
                        hoverColor: Theme.alpha("surface2", 0.6)
                        onClicked: {
                            if (card.compact)
                                Notifs.removeHistory(card.uid);
                            else
                                Notifs.hideToast(card.uid);
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: card.body !== ""
                    text: card.safeMarkup(card.body)
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: card.compact ? 4 : 8
                    elide: Text.ElideRight
                    color: card.fgColor
                    font.family: Theme.fontFamily
                    font.pointSize: Theme.fontSize
                    linkColor: card.isCritical && !card.compact ? Theme.col("base") : Theme.col("blue")
                    onLinkActivated: function (link) {
                        Notifs.openUrl(link);
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            visible: card.progress >= 0
            radius: 3
            color: card.trackColor

            Rectangle {
                height: parent.height
                radius: 3
                color: card.fillColor
                width: parent.width * Math.max(0, Math.min(1, card.progress / 100))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: card.hasActions
            spacing: 6

            Repeater {
                model: card.hasActions ? card.actions : []

                delegate: Rectangle {
                    id: actionButton
                    required property var modelData

                    readonly property string actionId: actionButton.modelData && actionButton.modelData.identifier !== undefined && actionButton.modelData.identifier !== null ? String(actionButton.modelData.identifier) : ""

                    radius: 8
                    implicitWidth: actionLabel.implicitWidth + 20
                    implicitHeight: 24
                    color: actionMouse.containsMouse ? Theme.alpha("surface2", 0.8) : card.chipColor
                    border.width: 1
                    border.color: Theme.alpha(card.accentName, 0.5)

                    Text {
                        id: actionLabel
                        anchors.centerIn: parent
                        text: actionButton.modelData && actionButton.modelData.text !== undefined && actionButton.modelData.text !== null && String(actionButton.modelData.text) !== "" ? String(actionButton.modelData.text) : "Open"
                        color: card.fgColor
                        font.family: Theme.fontFamily
                        font.pointSize: Theme.fontSmall
                        font.bold: true
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.invokeAction(card.uid, actionButton.actionId)
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }
}
