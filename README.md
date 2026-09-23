# Wet-Wallpaper

An interactive water surface wallpaper for Hyprland. Ripples respond to your mouse as you move it and click, and the whole simulation runs on the GPU.

It runs as a [Quickshell](https://quickshell.org) config.

## Features

* GPU powered physics, compiled to `.qsb` shaders that work on Vulkan, OpenGL, and OpenGL ES.
* Ripples from mouse movement and clicks.
* Optional ambient raindrops falling at a rate you control.
* Specular highlights on the water for a glossy look.
* Automatically pauses when a fullscreen or maximized window covers the screen, so it never wastes GPU time you don't see. You can exclude specific apps from this behavior.
* Use any image as the background, set a different image per monitor, or fall back to a built in dark blue color.
* An optional gentle wind chop animation that plays even without any interaction.

## Before you start

You will need:

* Hyprland, or another wlroots based Wayland compositor.
* [Quickshell](https://quickshell.org) installed and working.

If you are on NixOS, the instructions below can install Quickshell for you as part of the flake.

## Installation

Choose the guide that matches your setup.

### Option 1: NixOS with home-manager

1. Add this repository as a flake input in your `flake.nix`:

   ```nix
   {
     inputs.wet-wallpaper.url = "github:DybeBoy/wet-wallpaper";
   }
   ```

2. Pass the flake input through to home-manager and enable the module:

   ```nix
   {
     outputs = { self, home-manager, wet-wallpaper, ... }: {
       homeConfigurations.you = home-manager.lib.homeManagerConfiguration {
         modules = [
           wet-wallpaper.homeManagerModules.default
           {
             services.wetWallpaper.enable = true;
           }
         ];
       };
     };
   }
   ```

3. Rebuild your home-manager configuration:

   ```bash
   home-manager switch --flake .
   ```

4. Done. The wallpaper starts automatically with your graphical session, using a systemd user service. If it does not start right away, log out and back in.

This method installs Quickshell for you, copies the config to `~/.config/quickshell/wet-wallpaper/`, and creates a `wet-wallpaper` systemd user service. It also installs a small `wet-wallpaper` command you can use to change the wallpaper on the fly (see below).

The `config.json` settings file is left alone by this module. It is created by Quickshell the first time it runs, and you are free to edit it by hand at any point.

### Option 2: Manual install

Use this if you are not on NixOS, or prefer not to use home-manager.

1. Install Quickshell first. Follow the instructions on the [Quickshell website](https://quickshell.org) for your distribution.

2. Clone this repository:

   ```bash
   git clone https://github.com/DybeBoy/wet-wallpaper
   cd wet-wallpaper
   ```

3. Copy or symlink the `wet-wallpaper` folder into Quickshell's config directory:

   ```bash
   mkdir -p ~/.config/quickshell
   ln -s "$(pwd)/wet-wallpaper" ~/.config/quickshell/wet-wallpaper
   ```

   A symlink is recommended so future `git pull` updates apply automatically without copying files again.

4. Start it manually to make sure everything works:

   ```bash
   quickshell -c wet-wallpaper
   ```

   If a watery background appears on your screen, it worked. Press Ctrl+C in the terminal to stop it.

5. To have it start automatically with Hyprland, add this line to your `~/.config/hypr/hyprland.conf`:

   ```
   exec-once = quickshell -c wet-wallpaper
   ```

That's it. The wallpaper will now start every time Hyprland starts.

## Changing the wallpaper without restarting

Once the shell is running, you can swap the background image live, with an animated transition, using the included `wet-wallpaper` command:

```bash
wet-wallpaper ~/Pictures/lake.jpg
```

A few more examples:

```bash
# Use a ripple transition over 2 seconds at 60 fps
wet-wallpaper ~/Pictures/sunset.jpg --animation ripple --duration 2.0 --fps 60

# Only change the wallpaper on a specific monitor
wet-wallpaper ~/Pictures/mountains.jpg --monitor DP-1 --animation wipe --direction up
```

Run `wet-wallpaper --help` to see every option.

If you installed manually rather than through home-manager, the script lives at [wet-wallpaper/bin/wet-wallpaper](wet-wallpaper/bin/wet-wallpaper). Add it to your `PATH`, or call it using its full path.

## Configuration

All settings live in one plain JSON file. Quickshell creates it automatically the first time you run the shell, at:

```
${XDG_DATA_HOME:-~/.local/share}/quickshell/by-shell/wet-wallpaper/config.json
```

You can edit this file while the shell is running. Changes apply immediately.

If that path doesn't exist on your system, check the log output printed when you run `quickshell -c wet-wallpaper`. It will show the exact path Quickshell used.

Here is a full example with every option and its default value:

```jsonc
{
  "background": {
    "imagePath": "",              // Global fallback image. Leave empty for the dark blue fallback color.
    "perMonitor": {                // Optional: use a different image on specific monitors.
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

`pauseExcludeList` entries are matched against each window's Wayland `app_id`, without case sensitivity. This is usually the same string you'd recognize from your compositor's window rules, though it can occasionally differ from names used in other tools.

| Setting | Default | Range | What it does |
|---|---|---|---|
| `background.imagePath` | *(empty)* | any file path | Path to the background image. Leave empty to use the dark blue fallback color. |
| `background.perMonitor` | `{}` | | Maps a monitor name to its own image path, overriding `imagePath` on that monitor. |
| `physics.waveSpeed` | 0.5 | 0.1 to 1.0 | How fast ripples travel across the water. |
| `physics.damping` | 0.999 | 0.95 to 0.999 | How much energy ripples keep each frame. Lower values make ripples fade faster. |
| `visual.distortionStrength` | 0.04 | 0.0 to 0.05 | How strongly ripples visually warp the background image. |
| `visual.specularIntensity` | 0.6 | 0.0 to 1.0 | Brightness of the glossy highlight on the water. |
| `droplets.enabled` | false | | Turns ambient random raindrops on or off. |
| `droplets.ratePerMinute` | 120 | 1 to 1920 | How many random droplets fall per minute. |
| `interaction.hoverStrength` | 0.3 | | How strong a ripple your mouse leaves as it moves over the water. |
| `interaction.clickStrengthMultiplier` | 1.0 | | Multiplies how strong a click ripple is. |
| `interaction.dropletStrengthMultiplier` | 1.0 | | Multiplies how strong a droplet ripple is. |
| `ambientWaves.enabled` | false | | Turns the gentle wind chop animation on or off, independent of mouse interaction. |
| `ambientWaves.amplitude` | 0.02 | 0.0 to 0.05 | Height of the wind chop waves. |
| `ambientWaves.scale` | 6.0 | 1 to 20 | Roughly how many waves fit across your screen width. |
| `ambientWaves.speed` | 0.15 | 0.0 to 1.0 | How fast the wind chop animation moves. |
| `ambientWaves.direction` | 30.0 | 0 to 360 | Wind direction, in degrees. |
| `ambientWaves.complexity` | 3 | 1 to 4 | Number of overlapping wave patterns. Higher looks choppier and less repetitive. |
| `performance.simulationFPS` | 60 | 30, 60, or 120 | The frame rate cap for the water simulation. |
| `performance.smartPause` | true | | Pauses the simulation when a maximized or fullscreen window covers the monitor, to save GPU time. |
| `performance.pauseOnAnyWindow` | false | | When true, pauses for any window on the active workspace, not just maximized or fullscreen ones. |
| `performance.pauseExcludeList` | `[]` | | List of app IDs that should never trigger a pause. |

## Rebuilding the shaders

You only need this if you edit the shader source files in [wet-wallpaper/shaders](wet-wallpaper/shaders). The compiled `.qsb` files are already checked into the repository, so most people can skip this step entirely.

If you're using the Nix flake, `nix develop` gives you a shell with `cmake` and Qt's `qsb` tool already available. Otherwise, install `cmake`, `qt6-base`, and `qt6-shadertools` (package names vary by distribution) yourself, then run:

```bash
cmake -B build
cmake --build build
```

## How it works under the hood

`wet-wallpaper/shell.qml` opens one window per connected screen. Each window is a layer shell surface pinned to the background layer, sized to fill the whole screen, and set up so it never grabs keyboard focus or gets in your way.

The smart pause feature uses the `wlr-foreign-toplevel-management` Wayland protocol through Quickshell, so it works on any wlroots based compositor, not just Hyprland.

## License

See [LICENSE](LICENSE).

