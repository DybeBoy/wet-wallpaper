pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Settings source for the water-surface shell — replaces Plasma's KConfig
// dialog. Backed by a plain JSON file the user can hand-edit; changes on
// disk are picked up live (watchChanges), no restart required.
Singleton {
    id: root

    // Kept outside the (Nix-store-managed, read-only) shell root so the file
    // can actually be written to on first run and edited afterwards.
    readonly property string configPath: Quickshell.dataDir + "/config.json"

    // Flattened accessors used by WaterSurface.qml / WindowWatcher.qml.
    readonly property real    waveSpeed:           adapter.physics.waveSpeed
    readonly property real    damping:             adapter.physics.damping
    readonly property real    distortionStrength:  adapter.visual.distortionStrength
    readonly property real    specularIntensity:   adapter.visual.specularIntensity
    readonly property bool    dropletsEnabled:     adapter.droplets.enabled
    readonly property int     dropletsRate:        adapter.droplets.ratePerMinute
    readonly property real    hoverStrength:            adapter.interaction.hoverStrength
    readonly property real    clickStrengthMultiplier:  adapter.interaction.clickStrengthMultiplier
    readonly property real    dropletStrengthMultiplier: adapter.interaction.dropletStrengthMultiplier
    readonly property bool    ambientWavesEnabled:      adapter.ambientWaves.enabled
    readonly property real    ambientAmplitude:         adapter.ambientWaves.amplitude
    readonly property real    ambientScale:             adapter.ambientWaves.scale
    readonly property real    ambientSpeed:             adapter.ambientWaves.speed
    readonly property real    ambientDirection:         adapter.ambientWaves.direction
    readonly property int     ambientComplexity:        adapter.ambientWaves.complexity
    readonly property int     simulationResolution: adapter.simulationResolution
    readonly property int     simulationFPS:       adapter.performance.simulationFPS
    readonly property bool    smartPause:          adapter.performance.smartPause
    readonly property bool    pauseOnAnyWindow:    adapter.performance.pauseOnAnyWindow
    readonly property var     pauseExcludeList:    adapter.performance.pauseExcludeList
    readonly property string  transitionAnimation: adapter.transition.animation
    readonly property real    transitionDuration:  adapter.transition.duration
    readonly property int     transitionFps:       adapter.transition.fps
    readonly property string  transitionDirection: adapter.transition.direction

    readonly property var validAnimations: ["crossfade", "ripple", "iris", "wipe"]
    readonly property var validDirections: ["left", "right", "up", "down"]

    // Resolves the per-monitor override (keyed by output name, e.g. "DP-1"),
    // falling back to the single global image path.
    function imagePathFor(screenName) {
        var per = adapter.background.perMonitor
        if (screenName && per && per[screenName])
            return per[screenName]
        return adapter.background.imagePath
    }

    function setImage(path) {
        adapter.background.imagePath = path
        return "ok"
    }

    // perMonitor is a plain JS object — reassigning it (rather than mutating
    // a key in place) is required for the JsonObject's change signal to fire.
    function setImageForMonitor(monitor, path) {
        var per = Object.assign({}, adapter.background.perMonitor)
        per[monitor] = path
        adapter.background.perMonitor = per
        return "ok"
    }

    function setTransition(animation, duration, fps, direction) {
        if (root.validAnimations.indexOf(animation) === -1)
            return "error: unknown animation '" + animation + "', expected one of: " + root.validAnimations.join(", ")
        if (root.validDirections.indexOf(direction) === -1)
            return "error: unknown direction '" + direction + "', expected one of: " + root.validDirections.join(", ")
        if (!(duration > 0))
            return "error: duration must be > 0"
        if (!(fps > 0))
            return "error: fps must be > 0"

        adapter.transition.animation = animation
        adapter.transition.duration  = duration
        adapter.transition.fps       = fps
        adapter.transition.direction = direction
        return "ok"
    }

    // Sets the transition preferences and then the target image in one call —
    // the single entry point the wallpaper-switching CLI uses.
    function change(monitor, path, animation, duration, fps, direction) {
        var status = root.setTransition(animation, duration, fps, direction)
        if (status !== "ok")
            return status
        return (monitor && monitor.length > 0)
            ? root.setImageForMonitor(monitor, path)
            : root.setImage(path)
    }

    // Real-time control surface: `qs ipc call -c wet-wallpaper wallpaper ...`
    IpcHandler {
        target: "wallpaper"

        function change(monitor: string, path: string, animation: string, duration: real, fps: int, direction: string): string {
            return root.change(monitor, path, animation, duration, fps, direction)
        }
        function setTransition(animation: string, duration: real, fps: int, direction: string): string {
            return root.setTransition(animation, duration, fps, direction)
        }
        function setImage(path: string): string {
            return root.setImage(path)
        }
        function setImageForMonitor(monitor: string, path: string): string {
            return root.setImageForMonitor(monitor, path)
        }
    }

    FileView {
        id: file
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        // First run: no config file yet — materialise the defaults below.
        // Deferred with callLater so the write doesn't start while the
        // failed-read operation is still being torn down (avoided a
        // "dropped operation" warning from firing it synchronously here).
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                Qt.callLater(writeAdapter)
        }

        adapter: JsonAdapter {
            id: adapter

            property JsonObject background: JsonObject {
                property string imagePath: ""
                property var    perMonitor: ({})
            }
            property JsonObject physics: JsonObject {
                property real waveSpeed: 0.5
                property real damping: 0.999
            }
            property JsonObject visual: JsonObject {
                property real distortionStrength: 0.04
                property real specularIntensity: 0.6
            }
            property JsonObject droplets: JsonObject {
                property bool enabled: false
                property int  ratePerMinute: 120
            }
            property JsonObject interaction: JsonObject {
                // Height amplitude of each hover-trail stamp.
                property real hoverStrength: 0.3
                // Multiplies the click ripple's randomised 0.55–1.05 amplitude range.
                property real clickStrengthMultiplier: 1.0
                // Multiplies the droplet ripple's randomised 0.2–0.6 amplitude range.
                property real dropletStrengthMultiplier: 1.0
            }
            // Continuous low-amplitude "wind chop" layer, independent of interaction.
            property JsonObject ambientWaves: JsonObject {
                property bool enabled: false
                property real amplitude: 0.02
                property real scale: 6.0
                property real speed: 0.15
                property real direction: 30.0
                property int  complexity: 3
            }
            property int simulationResolution: 512
            property JsonObject performance: JsonObject {
                property int         simulationFPS: 60
                property bool        smartPause: true
                property bool        pauseOnAnyWindow: false
                property list<string> pauseExcludeList: []
            }
            // Real-time wallpaper-switching animation, driven by the "wallpaper" IPC target.
            property JsonObject transition: JsonObject {
                property string animation: "crossfade"
                property real   duration: 1.0
                property int    fps: 30
                property string direction: "left"
            }
        }
    }
}
