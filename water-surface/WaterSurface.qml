import QtQuick

// Ported from the Plasma wallpaper's main.qml. Root is now a plain Item
// sized via anchors.fill by the PanelWindow in shell.qml, instead of a
// WallpaperItem. Config reads come from the Config singleton (JSON-backed)
// instead of wallpaper.configuration.*, and smart-pause is driven by
// WindowWatcher (wlr-foreign-toplevel-management) instead of TaskManager.
Item {
    id: root

    // Screen this instance renders on — needed for per-monitor background
    // image lookup and to scope smart-pause to windows on this monitor.
    property var screen

    // -------------------------------------------------------------------------
    // Configuration shortcuts
    // -------------------------------------------------------------------------
    readonly property int    simRes:              Config.simulationResolution
    // Height of the physics grid: simRes wide, aspect-ratio-scaled tall so each
    // texel covers the same physical area in both axes (isotropic simulation).
    readonly property int    simHeight:           Math.max(1, Math.round(simRes / Math.max(1.0, root.width / root.height)))
    readonly property real   texelSz:             1.0 / simRes
    readonly property real   cfgWaveSpeed:        Config.waveSpeed
    readonly property real   cfgDamping:          Config.damping
    readonly property real   cfgDistortion:       Config.distortionStrength
    readonly property real   cfgSpecular:         Config.specularIntensity
    readonly property bool   cfgDroplets:         Config.dropletsEnabled
    readonly property int    cfgDropletsRate:     Config.dropletsRate
    readonly property real   cfgHoverStrength:    Config.hoverStrength
    readonly property real   cfgClickMultiplier:  Config.clickStrengthMultiplier
    readonly property real   cfgDropletMultiplier: Config.dropletStrengthMultiplier
    readonly property bool   cfgAmbientEnabled:    Config.ambientWavesEnabled
    readonly property real   cfgAmbientAmplitude:  Config.ambientAmplitude
    readonly property real   cfgAmbientScale:      Config.ambientScale
    readonly property real   cfgAmbientSpeed:      Config.ambientSpeed
    readonly property real   cfgAmbientDirection:  Config.ambientDirection
    readonly property int    cfgAmbientComplexity: Config.ambientComplexity
    readonly property string cfgImagePath:        Config.imagePathFor(root.screen ? root.screen.name : "")
    readonly property bool   cfgSmartPause:       Config.smartPause
    readonly property bool   cfgPauseOnAnyWindow: Config.pauseOnAnyWindow
    readonly property int    cfgFPS:              Config.simulationFPS
    readonly property var    cfgPauseExcludeList: Config.pauseExcludeList
    readonly property string cfgTransitionAnimation: Config.transitionAnimation
    readonly property real   cfgTransitionDuration:  Config.transitionDuration
    readonly property int    cfgTransitionFps:       Config.transitionFps
    readonly property string cfgTransitionDirection: Config.transitionDirection

    // Derived: true when the simulation should be paused
    readonly property bool simPaused: root.cfgSmartPause && windowWatcher.shouldPause

    // Seconds of simulated time, driven by simulationTimer so ambient waves
    // pause/slow down along with the rest of the effect.
    property real elapsedTime: 0.0

    // Droplet slot alternator (cycles 0→1→0→…)
    property int dropletSlot: 0

    // Interpolated hover trail: CPU-side path interpolation enqueues positions
    // at fixed UV spacing; the sim tick flushes them into 16 shader slots.
    property var  hoverQueue:  []
    property real hoverLastU: -1.0   // UV of last queued stamp; -1 = unset
    property real hoverLastV: -1.0

    // Pre-computed constants — allocated once at startup, reused every tick.
    // Avoids per-tick GC pressure that causes Alt+Tab stutter at high FPS.
    readonly property var      hoverSlotNames:         ["hover0","hover1","hover2","hover3","hover4","hover5",
                                                        "hover6","hover7","hover8","hover9","hover10","hover11",
                                                        "hover12","hover13","hover14","hover15"]
    readonly property vector4d zeroVec4:               Qt.vector4d(0, 0, 0, 0)
    // How many slots were written last tick — only those need zeroing this tick.
    property int               hoverSlotsWrittenLastTick: 0

    // -------------------------------------------------------------------------
    // Background: dark-blue fallback (always available, not shown directly)
    // -------------------------------------------------------------------------
    Rectangle {
        id: bgFallback
        width:  root.width
        height: root.height
        color:  "#080F2E"
        visible: false
    }

    // -------------------------------------------------------------------------
    // Background: user image (not shown directly, captured into a texture)
    // -------------------------------------------------------------------------
    Image {
        id: bgImage
        anchors.fill: parent
        source:       root.cfgImagePath !== "" ? root.cfgImagePath : ""
        fillMode:     Image.PreserveAspectCrop
        asynchronous: true
        visible:      false
    }

    // Captures whichever background is active into a sampler2D for the render
    // shader.  Switches automatically when the image finishes loading.
    ShaderEffectSource {
        id: bgCapture
        sourceItem: (bgImage.status === Image.Ready) ? bgImage : bgFallback
        live:       true
        visible:    false
    }

    // -------------------------------------------------------------------------
    // Wallpaper transitions — animates bgImage swaps triggered by the
    // "wallpaper" IPC target (see Config.qml). Steady-state cost is
    // unchanged: the incoming image and transition shader only exist for the
    // duration of a switch, via incomingLoader below.
    //
    // Guards against animating the very first (startup) image assignment —
    // only set once the whole tree, including bgImage's initial binding, has
    // settled.
    // -------------------------------------------------------------------------
    property bool   bgInitialized:        false
    property bool   transitioning:        false   // timer is actively blending
    property bool   awaitingSwapBack:     false   // waiting for bgImage to reload the finished path
    property string pendingTransitionPath: ""
    property string queuedTransitionPath:  ""     // change requested while busy finishing another
    property real   transitionProgress:   0.0
    property int    transitionSteps:      1

    Component.onCompleted: root.bgInitialized = true

    onCfgImagePathChanged: {
        if (root.bgInitialized) root.beginTransition(root.cfgImagePath)
    }

    function animationModeFor(name) {
        if (name === "ripple") return 1.0
        if (name === "iris")   return 2.0
        if (name === "wipe")   return 3.0
        return 0.0 // crossfade
    }

    function directionValueFor(name) {
        if (name === "right") return 1.0
        if (name === "up")    return 2.0
        if (name === "down")  return 3.0
        return 0.0 // left
    }

    // Only one transition runs at a time; a request that arrives while one is
    // finishing up is queued and started as soon as the previous one settles.
    function beginTransition(newPath) {
        if (root.transitioning) {
            root.queuedTransitionPath = newPath
            root.finishTransition()
            return
        }
        if (root.awaitingSwapBack) {
            root.queuedTransitionPath = newPath
            return
        }
        root.startTransitionTo(newPath)
    }

    function startTransitionTo(path) {
        root.pendingTransitionPath = path
        incomingLoader.active = true
    }

    function handleIncomingReady() {
        if (root.transitioning || !incomingLoader.item) return
        root.transitioning      = true
        root.transitionProgress = 0.0
        root.transitionSteps    = Math.max(1, Math.round(root.cfgTransitionDuration * root.cfgTransitionFps))
        transitionTimer.interval = Math.max(1, Math.round(1000.0 / root.cfgTransitionFps))

        var shader = incomingLoader.item.shader
        shader.mode      = root.animationModeFor(root.cfgTransitionAnimation)
        shader.direction = root.directionValueFor(root.cfgTransitionDirection)
        shader.progress  = 0.0

        renderShader.bgSource = incomingLoader.item.output
        transitionTimer.start()
    }

    function handleIncomingError() {
        console.warn("WaterSurface: failed to load wallpaper image:", root.pendingTransitionPath)
        incomingLoader.active = false
        root.pendingTransitionPath = ""
        root.dequeueTransition()
    }

    function finishTransition() {
        transitionTimer.stop()
        root.transitioning = false
        var finishedPath = root.pendingTransitionPath
        root.pendingTransitionPath = ""
        if (finishedPath === "") {
            incomingLoader.active = false
            return
        }
        // Freeze on the transition's final frame until bgImage has reloaded
        // the same (now cached) path, so the swap back to bgCapture is
        // invisible instead of flashing the previous background for a frame.
        root.awaitingSwapBack = true
        bgImage.source = finishedPath
        root.checkSwapBack()
    }

    function checkSwapBack() {
        if (!root.awaitingSwapBack) return
        if (bgImage.status !== Image.Ready && bgImage.status !== Image.Error) return
        renderShader.bgSource  = bgCapture
        incomingLoader.active  = false
        root.awaitingSwapBack  = false
        root.dequeueTransition()
    }

    function dequeueTransition() {
        if (root.queuedTransitionPath === "") return
        var next = root.queuedTransitionPath
        root.queuedTransitionPath = ""
        root.startTransitionTo(next)
    }

    Connections {
        target: bgImage
        function onStatusChanged() { root.checkSwapBack() }
    }

    Timer {
        id:       transitionTimer
        interval: 33
        repeat:   true
        running:  false
        onTriggered: {
            root.transitionProgress = Math.min(1.0, root.transitionProgress + 1.0 / root.transitionSteps)
            if (incomingLoader.item) {
                incomingLoader.item.shader.progress = root.transitionProgress
                incomingLoader.item.output.scheduleUpdate()
            }
            if (root.transitionProgress >= 1.0) root.finishTransition()
        }
    }

    // Transient incoming-image + blend-shader stack, only instantiated while
    // a transition is actually running.
    Loader {
        id:     incomingLoader
        active: false

        sourceComponent: Component {
            Item {
                width:  root.width
                height: root.height

                property alias image:   incImg
                property alias capture: incCap
                property alias shader:  transShader
                property alias output:  transCap

                Image {
                    id:           incImg
                    anchors.fill: parent
                    source:       root.pendingTransitionPath
                    fillMode:     Image.PreserveAspectCrop
                    asynchronous: true
                    visible:      false
                    onStatusChanged: {
                        if (status === Image.Ready) root.handleIncomingReady()
                        else if (status === Image.Error) root.handleIncomingError()
                    }
                }

                ShaderEffectSource {
                    id:         incCap
                    sourceItem: (incImg.status === Image.Ready) ? incImg : bgFallback
                    live:       true
                    visible:    false
                }

                ShaderEffect {
                    id:           transShader
                    anchors.fill: parent
                    visible:      false
                    blending:     false

                    property var  bgFrom:      bgCapture
                    property var  bgTo:        incCap
                    property real progress:    0.0
                    property real mode:        0.0
                    property real direction:   0.0
                    property real aspectRatio: root.width / root.height

                    fragmentShader: "shaders/water_transition.frag.qsb"
                    vertexShader:   "shaders/water_transition.vert.qsb"
                }

                ShaderEffectSource {
                    id:         transCap
                    sourceItem: transShader
                    live:       false
                    hideSource: true
                    visible:    false
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Physics pass — runs the wave simulation
    //
    // This item is never shown on screen; it renders only into waterStateSrc
    // via ShaderEffectSource below.  The ping-pong loop is:
    //   physicsShader reads waterStateSrc → ShaderEffectSource captures output
    //   → waterStateSrc feeds physicsShader on the next frame.
    // -------------------------------------------------------------------------
    ShaderEffect {
        id:       physicsShader
        width:    root.simRes
        height:   root.simHeight
        visible:  false
        blending: false          // raw data output — never alpha-blend

        // Ping-pong: reads the ShaderEffectSource that captures this shader's
        // own previous output (recursive: true makes this legal in Qt Quick).
        property var  prevState: waterStateSrc

        // Physics uniforms — matched by name to GLSL UBO members
        property real waveSpeed:   root.cfgWaveSpeed
        property real damping:     root.cfgDamping
        property real texelSize:   root.texelSz
        property real aspectRatio: root.width / root.height
        // dtScale = actualInterval / (1000/60). Using a fixed 60fps reference
        // means the wave propagation speed is independent of cfgFPS — changing
        // the FPS setting only affects smoothness, not simulation speed.
        property real dtScale: simulationTimer.interval * 0.06

        // Hover trail: 16 slots, flushed from the interpolation queue each tick
        property vector4d hover0:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover1:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover2:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover3:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover4:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover5:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover6:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover7:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover8:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover9:  Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover10: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover11: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover12: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover13: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover14: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d hover15: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        // ripple1: mouse click
        // ripple2/3: random droplets
        property vector4d ripple1: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d ripple2: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
        property vector4d ripple3: Qt.vector4d(0.0, 0.0, 0.0, 0.0)

        fragmentShader: "shaders/water_physics.frag.qsb"
        vertexShader:   "shaders/water_physics.vert.qsb"
    }

    // Ping-pong render target: captures physicsShader's output each frame and
    // feeds it back as prevState for the next frame.
    ShaderEffectSource {
        id:          waterStateSrc
        sourceItem:  physicsShader
        recursive:   true
        live:        false          // driven manually by simulationTimer below
        textureSize: Qt.size(root.simRes, root.simHeight)
        hideSource:  true
    }

    // Drives the simulation at the configured FPS.
    // Calling scheduleUpdate() triggers exactly one capture of physicsShader.
    Timer {
        id:       simulationTimer
        interval: Math.round(1000.0 / Math.max(1, root.cfgFPS))
        running:  !root.simPaused
        repeat:   true
        onTriggered: {
            root.elapsedTime += simulationTimer.interval / 1000.0

            // Flush up to 16 queued hover stamps into shader slots.
            // Only zero the slots that were written last tick (not always 16)
            // and skip the slice when the queue is already empty — eliminating
            // all JS heap allocations at idle (fixes Alt+Tab GC stutter).
            var q     = root.hoverQueue
            var n     = Math.min(q.length, 16)
            var names = root.hoverSlotNames
            var zero  = root.zeroVec4
            var prev  = root.hoverSlotsWrittenLastTick

            for (var i = 0; i < n; i++)
                physicsShader[names[i]] = Qt.vector4d(q[i].x, q[i].y, root.cfgHoverStrength, 0.022)
            for (var j = n; j < prev; j++)
                physicsShader[names[j]] = zero

            root.hoverSlotsWrittenLastTick = n
            if (n > 0) root.hoverQueue = q.slice(n)
            waterStateSrc.scheduleUpdate()
        }
    }

    // -------------------------------------------------------------------------
    // Smart-pause: monitors maximised/fullscreen windows on this screen
    // -------------------------------------------------------------------------
    WindowWatcher {
        id: windowWatcher
        screen:          root.screen
        excludeList:     root.cfgPauseExcludeList.join(",")
        pauseOnAnyWindow: root.cfgPauseOnAnyWindow
    }

    // -------------------------------------------------------------------------
    // Render pass — composites water effect over the background image
    //
    // Reads the current wave heights (waterStateSrc), distorts the background
    // UV, adds a specular highlight, and fills the screen.
    // -------------------------------------------------------------------------
    ShaderEffect {
        id:           renderShader
        anchors.fill: parent
        blending:     false         // fully opaque wallpaper, skip blend stage

        property var  waterState:         waterStateSrc
        property var  bgSource:           bgCapture
        property real distortionStrength: root.cfgDistortion
        property real specularIntensity:  root.cfgSpecular
        property real texelSize:          root.texelSz
        property real aspectRatio:        root.width / root.height

        // Ambient wind-chop overlay — zeroed here (not in-shader) so no
        // separate enabled/bool uniform is needed.
        property real ambientAmplitude: root.cfgAmbientEnabled ? root.cfgAmbientAmplitude : 0.0
        property real ambientScale:     root.cfgAmbientScale
        property real ambientSpeed:     root.cfgAmbientSpeed
        property real ambientDirection: root.cfgAmbientDirection * Math.PI / 180.0
        property real ambientComplexity: root.cfgAmbientComplexity
        property real time:             root.elapsedTime

        fragmentShader: "shaders/water_render.frag.qsb"
        vertexShader:   "shaders/water_render.vert.qsb"
    }

    // -------------------------------------------------------------------------
    // Mouse interaction
    // -------------------------------------------------------------------------

    // HoverHandler uses Qt 6's low-level pointer event system and directly
    // requests hover tracking from the window, unlike MouseArea.hoverEnabled
    // which relies on the parent item accepting hover events. This makes it
    // work on non-primary screens where the containing window may not
    // forward hover events to a MouseArea.
    HoverHandler {
        id: hoverHandler

        onPointChanged: {
            var cx = hoverHandler.point.position.x / root.width
            var cy = hoverHandler.point.position.y / root.height

            // First event after entering/re-entering — seed start point only.
            if (root.hoverLastU < 0.0) {
                root.hoverLastU = cx
                root.hoverLastV = cy
                return
            }

            // Walk from the last stamped UV to the current cursor, enqueuing
            // one position every 'spacing' UV units. This gives a uniform dot
            // density regardless of mouse speed or OS polling rate.
            var dx      = cx - root.hoverLastU
            var dy      = cy - root.hoverLastV
            var dist    = Math.sqrt(dx * dx + dy * dy)
            var spacing = 0.015
            if (dist < spacing * 0.5) return  // cursor barely moved

            var nx = root.hoverLastU
            var ny = root.hoverLastV
            var q  = root.hoverQueue
            while (dist >= spacing && q.length < 64) {
                nx   += (dx / dist) * spacing
                ny   += (dy / dist) * spacing
                q.push({x: nx, y: ny})
                dx    = cx - nx
                dy    = cy - ny
                dist  = Math.sqrt(dx * dx + dy * dy)
            }
            root.hoverLastU = nx
            root.hoverLastV = ny
        }

        onHoveredChanged: {
            if (!hovered) {
                // Reset so the next entry doesn't interpolate across the gap.
                root.hoverLastU = -1.0
                root.hoverLastV = -1.0
            }
        }
    }

    // Click handler — hoverEnabled false so it doesn't interfere with HoverHandler.
    MouseArea {
        id:           mouseArea
        anchors.fill: parent
        hoverEnabled: false

        onPressed: function(mouse) {
            // Randomise size so each click feels unique and distinct from droplets.
            var clickStrength = (0.55 + Math.random() * 0.5) * root.cfgClickMultiplier   // 0.55 – 1.05 × multiplier
            var clickRadius   = 0.02 + Math.random() * 0.01 // 0.02 – 0.03
            physicsShader.ripple1 = Qt.vector4d(
                mouse.x / width,
                mouse.y / height,
                clickStrength,
                clickRadius
            )
            clickDecayTimer.restart()
        }
    }

    // Zero out the click ripple — slightly longer so the splash feels punchy.
    Timer {
        id:       clickDecayTimer
        interval: 80
        onTriggered: physicsShader.ripple1 = Qt.vector4d(
                         physicsShader.ripple1.x, physicsShader.ripple1.y, 0.0, 0.0)
    }

    // -------------------------------------------------------------------------
    // Random water droplets
    // -------------------------------------------------------------------------
    Timer {
        id:       dropletTimer
        interval: Math.round(60000.0 / root.cfgDropletsRate)
        running:  root.cfgDroplets && !root.simPaused
        repeat:   true

        onTriggered: {
            var x        = Math.random()
            var y        = Math.random()
            var strength = (0.3 + Math.random() * 0.4) * root.cfgDropletMultiplier   // 0.2 – 0.6 × multiplier (lighter than clicks)
            var radius   = 0.01 + Math.random() * 0.01 // 0.01 – 0.02

            if (root.dropletSlot % 2 === 0) {
                physicsShader.ripple2 = Qt.vector4d(x, y, strength, radius)
            } else {
                physicsShader.ripple3 = Qt.vector4d(x, y, strength, radius)
            }
            root.dropletSlot++
            dropletDecayTimer.restart()
        }
    }

    // Zero out both droplet slots after 200 ms (the impulse has been injected
    // by then; keeping it active would add energy every frame).
    Timer {
        id:       dropletDecayTimer
        interval: 200
        onTriggered: {
            physicsShader.ripple2 = Qt.vector4d(
                physicsShader.ripple2.x, physicsShader.ripple2.y, 0.0, 0.0)
            physicsShader.ripple3 = Qt.vector4d(
                physicsShader.ripple3.x, physicsShader.ripple3.y, 0.0, 0.0)
        }
    }
}
