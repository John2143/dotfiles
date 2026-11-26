pragma ComponentBehavior: Bound

// ToastStack.qml — top-right toast overlay for the focused Hyprland monitor.
//
// Mirrors dunst's `follow = keyboard` / `origin = top-right` / `offset = 10x40`
// / `width = 300` / `gap = 8` geometry. `mask: Region { item: toastColumn }`
// confines the layer surface's input region to the toast column, so the gaps
// between cards and the rest of the surface stay click-through and the desktop
// behind them remains usable.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.components

Item {
    id: root

    Variants {
        model: Quickshell.screens

        // qmllint disable uncreatable-type
        delegate: PanelWindow {
            id: toastWindow
            required property ShellScreen modelData

            // dunst's follow = keyboard: only the focused monitor pops toasts.
            readonly property bool isTargetScreen: Notifs.isFocusedScreen(toastWindow.modelData)

            screen: toastWindow.modelData
            visible: toastWindow.isTargetScreen && Notifs.toasts.length > 0 && !Notifs.panelOpen

            anchors {
                top: true
                right: true
            }
            // Quickshell 0.3.2 marks Margins isTypeOpaque in _Window/quickshell-window.qmltypes
            // (fields live in quickshell-core.qmltypes), so qmllint flags top/right.
            // qmllint disable missing-property
            margins {
                top: Theme.marginTop
                right: Theme.marginRight
            }
            // qmllint enable missing-property

            implicitWidth: Theme.toastWidth
            implicitHeight: Math.min(Math.max(1, toastWindow.modelData ? toastWindow.modelData.height - Theme.marginTop - Theme.marginBottom : 1), Math.max(1, toastColumn.implicitHeight))
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
                width: Theme.toastWidth
                spacing: Theme.toastGap

                Repeater {
                    model: Notifs.toasts

                    delegate: ToastCard {
                        id: toastCard
                        required property var modelData

                        width: Theme.toastWidth
                        entry: toastCard.modelData
                    }
                }
            }
        }
        // qmllint enable uncreatable-type
    }
}
