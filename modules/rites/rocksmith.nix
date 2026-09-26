{self, ...}: {
  flake.nixosModules.rocksmith = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf;
    cfg = config.programs.steam.rocksmithPatch;
  in {
    # Rocksmith 2014 — real-time audio via PipeASIO over PipeWire.
    #
    # Depends on the nixos-rocksmith and steam-config-nix flake inputs.
    # The nixos-rocksmith NixOS module provides:
    #   - programs.steam.rocksmithPatch (PipeASIO, RS_ASIO, patch-rocksmith)
    #   - PAM rtprio/memlock limits for @audio
    #   - PipeWire + WirePlumber base enablement
    #
    # The nixos-rocksmith HM module (auto-imported when home-manager is
    # present) provides:
    #   - PipeASIO config.ini (~/.config/pipeasio/config.ini)
    #   - patch-rocksmith activation (copies DLLs into Proton prefix)
    #   - Steam launch options via steam-config-nix
    imports = [
      self.inputs.nixos-rocksmith.nixosModules.default
      self.inputs.steam-config-nix.nixosModules.default
    ];

    # PipeASIO (from nixos-rocksmith overlay) builds against Wine's MSVC
    # toolchain, which requires accepting the Microsoft Visual Studio license.
    nixpkgs.config.microsoftVisualStudioLicenseAccepted = true;
    nixpkgs.config.allowUnfree = true;

    # ── Rocksmith + PipeASIO ────────────────────────────────────────
    # PipeASIO bridges Rocksmith's ASIO calls directly to PipeWire —
    # no JACK daemon or libjack.so preloading needed.
    programs.steam.rocksmithPatch = {
      enable = true;
      pipeasio = {
        buffer = 128; # ~2.7 ms at 48 kHz
        rate = 48000; # Rocksmith strictly requires 48 kHz
        # Leave empty for auto-detection.  Set explicitly if PipeASIO
        # picks the wrong device:
        #   pw-cli ls | grep alsa
        inputDevice = "";
        outputDevice = "";
      };
    };

    # ── Audio group (required for PAM rtprio limits) ────────────────
    users.users.apetrovic.extraGroups = ["audio"];

    # ── Low-latency PipeWire tuning ─────────────────────────────────
    services.pipewire = {
      alsa.support32Bit = true;

      extraConfig.pipewire."92-low-latency" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.quantum" = 128; # ~2.7 ms at 48 kHz
          "default.clock.min-quantum" = 32;
          "default.clock.max-quantum" = 512;
        };
      };

      # Disable node suspension — prevents audio pops / xruns caused
      # by PipeWire putting the USB interface to sleep after 5 s idle.
      wireplumber.extraConfig."99-disable-suspend" = {
        "monitor.alsa.rules" = [{
          matches = [
            {"node.name" = "~alsa_input.*";}
            {"node.name" = "~alsa_output.*";}
          ];
          actions = {
            update-props = {
              "session.suspend-timeout-seconds" = 0;
            };
          };
        }];
      };
    };

    # ── Kernel & power tuning for low-latency audio ─────────────────
    boot.kernelParams = [
      "preempt=full" # dynamic preemption (merged PREEMPT_RT)
      "usbcore.autosuspend=-1" # prevent USB audio interface sleep
    ];

    # Performance governor prevents CPU sleep-state latency spikes.
    # Skipped when power-profiles-daemon is active (laptops) to avoid
    # conflicting CPU frequency management.
    powerManagement.cpuFreqGovernor =
      mkIf (!config.services.power-profiles-daemon.enable) "performance";

    # GameMode can boost scheduling priority for real-time audio apps.
    programs.gamemode.enable = true;

    # ── Useful debugging tools ──────────────────────────────────────
    environment.systemPackages = mkIf cfg.enable (with pkgs; [
      pwvucontrol # PipeWire-native volume control
      qpwgraph # visual PipeWire/JACK patchbay
    ]);
  };
}
