# Water Surface — Quickshell background layer for Hyprland

An interactive water surface simulation for the desktop background. Ripples respond to mouse movement and clicks in real time; the physics run entirely on the GPU via Qt Quick `ShaderEffect`. Originally a KDE Plasma 6 wallpaper plugin, now a standalone [Quickshell](https://quickshell.org) config with no Plasma/plasmashell dependency — built for Hyprland on NixOS.

---

## How it's hosted

`water-surface/shell.qml` creates one `PanelWindow` per connected screen (via `Quickshell.screens`), each a `wlr-layer-shell` surface pinned to `WlrLayer.Background`, `exclusiveZone: 0`, anchored fullscreen. It doesn't request keyboard focus, so it never steals focus from other windows.

> **Verify on your system:** whether a `Background`-layer surface receives pointer motion/clicks under your Hyprland version should be confirmed after installing (move the mouse over bare desktop — ripples should appear). If it doesn't, change `WlrLayershell.layer` in `shell.qml` to `WlrLayer.Bottom` and retest.

## Features

- **GPU physics** — ping-pong height-field simulation compiled to `.qsb` (Vulkan GLSL 440, OpenGL, OpenGL ES)
- **Mouse interaction** — hover trails and clicks disturb the surface
- **Random droplets** — configurable rate of ambient raindrops
- **Specular highlights** — Phong shading on the water surface
- **Smart pause** — automatically pauses when a maximised or fullscreen window covers a monitor, with a per-app exclusion list (uses the `wlr-foreign-toplevel-management` protocol via Quickshell's `ToplevelManager`, so it works with any wlroots compositor)
- **Configurable background** — a global image, per-monitor image overrides, or a built-in dark-blue fallback
- **Ambient wind chop** — continuous low-amplitude wave layer, independent of interaction

---

## Running it

This is a **named** Quickshell config (not the default one), so it won't interfere with any other Quickshell setup (e.g. a bar) you run separately.

```bash
quickshell -c water-surface
```

Quickshell resolves named configs from `~/.config/quickshell/water-surface/`. Either symlink/copy this repo's `water-surface/` directory there, or install it via the Nix flake (below).

## Configuration

Settings live in a plain JSON file, created automatically on first run at:

```
${XDG_DATA_HOME:-~/.local/share}/quickshell/by-shell/water-surface/config.json
```

(the last path segment is Quickshell's per-shell data directory, keyed by the
`-c water-surface` config name; if your Quickshell version keys it differently,
`Config.qml`'s `configPath` property reflects whatever path is actually used —
check `quickshell -c water-surface`'s log output on first run to confirm it).

Edit it while the shell is running — changes are picked up live, no restart needed.

```jsonc
{
  "background": {
    "imagePath": "",              // global fallback image; "" = dark-blue fallback
    "perMonitor": {                // optional per-output overrides
      "DP-1": "/home/you/Pictures/wall1.jpg"
    }
  },
  "physics": { "waveSpeed": 0.5, "damping": 0.999 },
  "visual": { "distortionStrength": 0.04, "specularIntensity": 0.6 },
  "droplets": { "enabled": false, "ratePerMinute": 120 },
  "interaction": {
    "hoverStrength": 0.3,
    "clickStrengthMultiplier": 1.0,
    "dropletStrengthMultiplier": 1.0
  },
  "ambientWaves": {
    "enabled": false,
    "amplitude": 0.02,
    "scale": 6.0,
    "speed": 0.15,
    "direction": 30.0,
    "complexity": 3
  },
  "simulationResolution": 512,
  "performance": {
    "simulationFPS": 60,
    "smartPause": true,
    "pauseOnAnyWindow": false,
    "pauseExcludeList": ["kitty"]
  }
}
```

`pauseExcludeList` entries are matched against each window's Wayland `app_id` (case-insensitive) — usually the same string you'd see in KDE, but sourced from the app itself rather than KWin, so a few IDs may differ from the old Plasma exclusion list.

| Setting | Default | Range | Description |
|---|---|---|---|
| `background.imagePath` | *(none)* | — | Path to any image file. Empty = dark-blue fallback. |
| `background.perMonitor` | `{}` | — | Output-name → image path overrides. |
| `physics.waveSpeed` | 0.5 | 0.1 – 1.0 | Propagation speed of ripples. |
| `physics.damping` | 0.999 | 0.95 – 0.999 | Energy retained per frame. |
| `visual.distortionStrength` | 0.04 | 0.0 – 0.05 | How strongly the height field warps the background image. |
| `visual.specularIntensity` | 0.6 | 0.0 – 1.0 | Brightness of the Phong specular highlight. |
| `droplets.enabled` | false | — | Toggle ambient random droplets. |
| `droplets.ratePerMinute` | 120 | 1 – 1920 | Rate of random droplets. |
| `interaction.hoverStrength` | 0.3 | — | Height amplitude of each mouse-hover trail stamp. |
| `interaction.clickStrengthMultiplier` | 1.0 | — | Multiplies the click ripple's randomised amplitude. |
| `interaction.dropletStrengthMultiplier` | 1.0 | — | Multiplies the droplet ripple's randomised amplitude. |
| `ambientWaves.enabled` | false | — | Toggle the continuous wind-chop overlay, independent of interaction. |
| `ambientWaves.amplitude` | 0.02 | 0.0 – 0.05 | Height of the ambient chop. |
| `ambientWaves.scale` | 6.0 | 1 – 20 | Spatial frequency — roughly how many waves fit across the screen width. |
| `ambientWaves.speed` | 0.15 | 0.0 – 1.0 | Animation speed of the chop. |
| `ambientWaves.direction` | 30.0 | 0 – 360 | Wind direction in degrees. |
| `ambientWaves.complexity` | 3 | 1 – 4 | Number of stacked sine octaves — higher looks choppier/less repetitive. |
| `performance.simulationFPS` | 60 | 30 / 60 / 120 | Active simulation frame rate cap. |
| `performance.smartPause` | true | — | Pause when a maximised/fullscreen window covers the monitor. |
| `performance.pauseOnAnyWindow` | false | — | If true, pause for *any* non-excluded window on the monitor's active workspace, even non-maximised/non-fullscreen ones. |
| `performance.pauseExcludeList` | `[]` | — | App IDs ignored by smart pause. |

---

## Nix / home-manager

```nix
{
  inputs.water-surface.url = "github:you/plasma-watersurface";

  outputs = { self, home-manager, water-surface, ... }: {
    homeConfigurations.you = home-manager.lib.homeManagerConfiguration {
      modules = [
        water-surface.homeManagerModules.default
        {
          services.waterSurfaceWallpaper.enable = true;
        }
      ];
    };
  };
}
```

This installs the config to `~/.config/quickshell/water-surface/` and creates a `water-surface-wallpaper.service` systemd user unit (`quickshell -c water-surface`, `PartOf=graphical-session.target`) so it starts with your graphical session. `config.json` is intentionally left alone by this module — it's created and owned by Quickshell at runtime, not managed declaratively.

Run `nix develop` for a shell with `cmake` + Qt's `qsb` if you need to rebuild the `.qsb` shaders after editing the `.vert`/`.frag` sources.

## Building shaders

The compiled `.qsb` files are already checked in under `water-surface/shaders/`. Only rebuild if you modify the GLSL sources:

```bash
cmake -B build
cmake --build build
```

---

## License

[LICENSE](LICENSE)
