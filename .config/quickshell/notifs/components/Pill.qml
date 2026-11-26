pragma ComponentBehavior: Bound

// Pill.qml — small rounded label used for the history centre's header toggles.
//
// `toggleStyle` pills are stateful switches (DND, Grouped/Flat): they show the
// accent fill while active. Non-toggle pills (Clear All) are plain buttons that
// only highlight on hover.
import QtQuick
import qs.services

Rectangle {
    id: pill

    required property string label

    property bool active: false
    property string accentRole: Theme.accentRole
    property bool toggleStyle: true

    signal clicked()

    implicitWidth: pillLabel.implicitWidth + 16
    implicitHeight: 22
    radius: 11
    border.width: 1
    color: pill.toggleStyle ? (pill.active ? Theme.alpha(pill.accentRole, 0.2) : Theme.col("surface0")) : (pillMouse.containsMouse ? Theme.alpha("surface2", 0.9) : "transparent")
    border.color: pill.toggleStyle && pill.active ? Theme.col(pill.accentRole) : Theme.col("surface1")

    Text {
        id: pillLabel
        anchors.centerIn: parent
        text: pill.label
        color: pill.toggleStyle ? (pill.active ? Theme.col(pill.accentRole) : Theme.col("overlay1")) : Theme.col("subtext0")
        font.family: Theme.fontFamily
        font.pointSize: Theme.fontTiny
        font.bold: pill.toggleStyle && pill.active
    }

    MouseArea {
        id: pillMouse
        anchors.fill: parent
        hoverEnabled: !pill.toggleStyle
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
