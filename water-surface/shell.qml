import Quickshell
import Quickshell.Wayland

// Entry point for the `water-surface` Quickshell config. Hosts one
// WaterSurface scene per connected screen inside a wlr-layer-shell surface
// pinned to the background layer — the standalone-Hyprland replacement for
// Plasma's per-screen WallpaperItem.
ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            property var modelData
            screen: modelData

            anchors {
                left: true
                top: true
                right: true
                bottom: true
            }
            // Ignore mode both reserves zero space for this surface AND
            // stops it from shrinking to avoid other layers' exclusive zones
            // (e.g. waybar) — without it the background stopped at the bar
            // like a normal window.
            exclusionMode: ExclusionMode.Ignore
            // No keyboard focus is requested (WlrLayershell.keyboardFocus
            // defaults to None), so this never steals focus from other windows.
            color: "#080F2E"

            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "water-surface"

            WaterSurface {
                anchors.fill: parent
                screen: win.screen
            }
        }
    }
}
