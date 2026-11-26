// ToastStack.qml — top-right toast overlay for the focused Hyprland monitor.
//
// Mirrors dunst's `follow = keyboard` / `origin = top-right` / `offset = 10x40`
// / `width = 300` / `gap = 8` geometry. The layer surface is click-through
// everywhere except the cards themselves (Region mask), so the desktop behind
// the gaps stays usable.
import QtQuick
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
            id: toastWindow
            property var modelData

            // dunst's follow = keyboard: only the focused monitor pops toasts.
            readonly property bool isTargetScreen: {
                var focused = Hyprland.focusedMonitor;
                if (focused !== null && focused !== undefined && focused.name !== undefined)
                    return modelData.name === focused.name;
                return Quickshell.screens.length > 0 && modelData === Quickshell.screens[0];
            }

            screen: modelData
            visible: isTargetScreen && Notifs.toasts.length > 0 && !Notifs.panelOpen

            anchors {
                top: true
                right: true
            }
            // Quickshell 0.3.2 marks Margins isTypeOpaque in _Window/quickshell-window.qmltypes
            // (fields live in quickshell-core.qmltypes), so qmllint flags top/right.
            // qmllint disable missing-property
            margins {
                top: 40
                right: 10
            }
            // qmllint enable missing-property

            implicitWidth: 300
            implicitHeight: Math.min(Math.max(1, modelData ? modelData.height - 60 : 1), Math.max(1, toastColumn.implicitHeight))
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: false

            WlrLayershell.namespace: "qs-notifs-toasts"
            WlrLayershell.layer: WlrLayer.Overlay

            mask: Region {
                item: toastColumn
            }

            Column {
                id: toastColumn
                width: 300
                spacing: 8

                Repeater {
                    model: Notifs.toasts

                    delegate: ToastCard {
                        required property var modelData
                        width: 300
                        entry: modelData
                    }
                }
            }
        }
        // qmllint enable uncreatable-type
    }
}
