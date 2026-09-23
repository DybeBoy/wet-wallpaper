{ config, lib, pkgs, self, quickshell, ... }:

let
  cfg = config.services.wetWallpaper;
  system = pkgs.system;
in
{
  options.services.wetWallpaper = {
    enable = lib.mkEnableOption "the wet-wallpaper interactive water surface (Quickshell + Hyprland)";

    quickshellPackage = lib.mkOption {
      type = lib.types.package;
      default = quickshell.packages.${system}.default;
      defaultText = lib.literalExpression "quickshell.packages.<system>.default";
      description = "The quickshell package used to run the wet-wallpaper config.";
    };
  };

  # Note: this module only installs the shell.qml/*.qsb config and starts it.
  # config.json (wave speed, damping, smart-pause exclude list, ...) is left
  # for the user to hand-edit at runtime — see Config.qml's data directory.
  # It is deliberately NOT managed declaratively here, since Quickshell's
  # writeAdapter()-on-first-run bootstrap and this module's static install
  # would otherwise fight over the same file.
  config = lib.mkIf cfg.enable {
    xdg.configFile."quickshell/wet-wallpaper" = {
      source = "${self.packages.${system}.default}/share/wet-wallpaper";
      recursive = true;
    };

    # `wet-wallpaper` CLI — switches the wallpaper in real time via
    # the "wallpaper" Quickshell IPC target exposed by Config.qml.
    home.packages = [ self.packages.${system}.wallpaperScript ];

    systemd.user.services.wet-wallpaper = {
      Unit = {
        Description = "Interactive water-surface background layer (Quickshell)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.quickshellPackage}/bin/quickshell -c wet-wallpaper";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
