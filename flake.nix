{
  description = "Interactive GPU water-surface background layer for Hyprland, hosted by Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, quickshell }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # The quickshell config directory itself — `shell.qml` and friends,
          # installed verbatim. Shaders are shipped pre-compiled (.qsb), so no
          # Qt/qsb dependency is needed just to install this.
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "water-surface-quickshell";
            version = "1.0.0";
            src = ./water-surface;
            dontBuild = true;
            installPhase = ''
              mkdir -p "$out/share/water-surface"
              cp -r . "$out/share/water-surface"
            '';
          };

          # CLI wrapper around `qs ipc call ... wallpaper change`, for
          # real-time wallpaper switching with an animated transition.
          wallpaperScript = pkgs.stdenvNoCC.mkDerivation {
            pname = "water-surface-wallpaper";
            version = "1.0.0";
            src = ./water-surface/bin/water-surface-wallpaper;
            dontUnpack = true;
            installPhase = ''
              mkdir -p "$out/bin"
              install -m755 "$src" "$out/bin/water-surface-wallpaper"
            '';
          };
        });

      homeManagerModules.default = { config, lib, pkgs, ... }@args:
        import ./home-manager/module.nix (args // {
          inherit self quickshell;
        });

      # Rebuilding the .qsb shaders (only needed if you edit the .vert/.frag
      # sources) still uses the CMake + qsb workflow from the original repo.
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.cmake pkgs.qt6.qtbase pkgs.qt6.qtshadertools ];
          };
        });
    };
}
