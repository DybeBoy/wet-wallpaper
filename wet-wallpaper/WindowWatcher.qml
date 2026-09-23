import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Smart-pause helper — replaces the Plasma TaskManager-based WindowModel.qml.
// Uses the wlr-foreign-toplevel-management protocol (Quickshell.Wayland
// ToplevelManager) instead of KDE's AbstractTasksModel, so it works on any
// wlroots compositor. Workspace visibility (below) is Hyprland-specific,
// since the generic protocol has no concept of workspaces.
Item {
    id: root

    // Screen this instance's simulation runs on; only toplevels visible on
    // this screen count towards shouldPause.
    property ShellScreen screen
    // Comma-separated app IDs to ignore (case-insensitive), e.g. a transparent terminal.
    property string excludeList: ""
    // When true, any non-excluded window on the screen pauses the simulation,
    // not just fullscreen/maximized ones.
    property bool pauseOnAnyWindow: false

    readonly property var excludeSet: {
        var set = {}
        excludeList.split(",").forEach(function (e) {
            var t = e.trim().toLowerCase()
            if (t.length > 0) set[t] = true
        })
        return set
    }

    property bool shouldPause: false

    function isExcluded(appId) {
        return !!root.excludeSet[(appId || "").toLowerCase()]
    }

    function recompute() {
        var toplevels = ToplevelManager.toplevels.values
        for (var i = 0; i < toplevels.length; i++) {
            var t = toplevels[i]
            if (t.minimized) continue
            if (!root.pauseOnAnyWindow && !t.fullscreen && !t.maximized) continue
            if (t.screens.indexOf(root.screen) === -1) continue
            // Hyprland keeps reporting a window's monitor via `screens`
            // even while its workspace is switched away from — only count
            // it if its workspace is the one actually visible right now.
            // `HyprlandToplevel` itself is just a resolver; the live,
            // IPC-populated data lives on its `.handle`.
            var hw = t.HyprlandToplevel
            var handle = hw ? hw.handle : null
            if (handle && handle.workspace && !handle.workspace.active) continue
            if (root.isExcluded(t.appId)) continue
            root.shouldPause = true
            return
        }
        root.shouldPause = false
    }

    onExcludeSetChanged: Qt.callLater(root.recompute)
    onScreenChanged: Qt.callLater(root.recompute)
    onPauseOnAnyWindowChanged: Qt.callLater(root.recompute)

    // Workspace switches don't change any Toplevel property we already watch
    // below, so recompute on every Hyprland IPC event too (cheap: Qt.callLater
    // collapses bursts, and recompute() itself is a short scan).
    Connections {
        target: Hyprland
        function onRawEvent(event) { Qt.callLater(root.recompute) }
    }

    // Forwards per-window property changes (fullscreen/maximized/minimized/
    // closed) into a debounced recompute — mirrors the original's use of
    // Qt.callLater to collapse bursts of signals into one recomputation.
    Instantiator {
        model: ToplevelManager.toplevels
        delegate: QtObject {
            id: watcher
            required property var modelData

            // QtObject has no default property, so Connections must be
            // assigned to a named property rather than nested as a child.
            property Connections _conn: Connections {
                target: watcher.modelData
                function onFullscreenChanged() { Qt.callLater(root.recompute) }
                function onMaximizedChanged()  { Qt.callLater(root.recompute) }
                function onMinimizedChanged()  { Qt.callLater(root.recompute) }
                function onClosed()            { Qt.callLater(root.recompute) }
            }

            Component.onCompleted: Qt.callLater(root.recompute)
        }

        onObjectAdded: Qt.callLater(root.recompute)
        onObjectRemoved: Qt.callLater(root.recompute)
    }
}
