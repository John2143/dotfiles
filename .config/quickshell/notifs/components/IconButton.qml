pragma ComponentBehavior: Bound

// IconButton.qml — round glyph button (close, per-group clear).
import QtQuick
import qs.services

Rectangle {
    id: btn

    property string glyph: "✕"
    property int buttonSize: 18
    property int fontPointSize: Theme.fontSmall
    property color glyphColor: Theme.col("overlay1")
    property color hoverColor: Theme.alpha("surface2", 0.9)

    signal clicked()

    implicitWidth: btn.buttonSize
    implicitHeight: btn.buttonSize
    radius: btn.buttonSize / 2
    color: btnMouse.containsMouse ? btn.hoverColor : "transparent"

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: btn.glyphColor
        font.family: Theme.fontFamily
        font.pointSize: btn.fontPointSize
    }

    MouseArea {
        id: btnMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
