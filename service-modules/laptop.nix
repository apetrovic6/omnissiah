
{
  _class = "clan.service";
  manifest.name = "role-laptop";

  # Single role called "default" (selected by the 'laptop' tag)
  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    # Networking & power basics for laptops
    networking.networkmanager.enable = true;
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;

    # Gentle thermal help on Intel; safe no-op elsewhere
    services.thermald.enable = lib.mkDefault true;

    # Lid behavior (customize per your preference later)
    services.logind = {
      lidSwitch = "suspend";
      lidSwitchExternalPower = "suspend";
      lidSwitchDocked = "ignore";
    };

    # Firmware updates (UEFI / TB / docks, etc.)
    services.fwupd.enable = true;

    # Suspend-then-hibernate: quick sleep, deep-save after 1h
    # ⚠️ Requires swap + resume config; see note below
    systemd.sleep.extraConfig = ''
      SuspendState=suspend
      HibernateMode=shutdown
      HibernateDelaySec=1h
      SuspendEstimationSec=0
    '';
    systemd.targets."sleep".wantedBy = [ "suspend-then-hibernate.target" ];
    systemd.services."systemd-suspend-then-hibernate".enable = true;

    # Room to grow later:
    # powerManagement.powertop.enable = true;
    # services.auto-cpufreq.enable = true;
  };
}
