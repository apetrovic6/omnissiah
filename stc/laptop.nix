{
  _class = "clan.service";
  manifest.name = "laptop";
  manifest.readme = "";

  roles.default.description = "Laptop specific configuration";

  # Single role called "default" (selected by the 'laptop' tag)
  roles.default.perInstance.nixosModule = {
    lib,
    pkgs,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      brightnessctl
    ];

    environment.variables = {
      #      AQ_DRM_DEVICES = "/dev/dri/card1:/dev/dri/card1";
    };

    # Networking & power basics for laptops
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;

    # Gentle thermal help on Intel; safe no-op elsewhere
    services.thermald.enable = lib.mkDefault true;

    # Lid behavior (customize per your preference later)
    services.logind = {
      lidSwitch = "suspend-then-hibernate";
      lidSwitchExternalPower = "suspend-then-hibernate";
      lidSwitchDocked = "ignore";
    };

    systemd.sleep.extraConfig = ''
      # Valid kernel state for suspend-to-RAM:
      # values must come from: freeze mem disk
      SuspendState=mem

      # How hibernate should write to /sys/power/disk
      HibernateMode=shutdown

      # Suspend-then-hibernate timing logic
      HibernateDelaySec=1h
      SuspendEstimationSec=0
    '';
  };
}
