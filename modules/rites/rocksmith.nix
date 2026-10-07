{self, ...}: {
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
  flake.nixosModules.rocksmith = {
    config,
    options,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf;
    cfg = config.programs.steam.rocksmithPatch;

    # Zen-Go Pro Audio channel map: ch0 = mic (input 1), ch1 = guitar
    # (input 2). The stock nixos-rocksmith config exposes only 1 ASIO
    # input and maps Rocksmith's guitar endpoint to channel 0 — the mic.
    guitarChannel = 1;
    micChannel = 0;

    rsAsioIni = ''
      [Config]
      EnableWasapiOutputs=0
      EnableWasapiInputs=0
      EnableAsio=1

      [Asio]
      BufferSizeMode=driver

      [Asio.Output]
      Driver=PipeASIO
      BaseChannel=0
      EnableSoftwareEndpointVolumeControl=1
      EnableSoftwareMasterVolumeControl=1
      SoftwareMasterVolumePercent=100

      [Asio.Input.0]
      Driver=PipeASIO
      Channel=${toString guitarChannel}
      EnableSoftwareEndpointVolumeControl=1
      EnableSoftwareMasterVolumeControl=1
      SoftwareMasterVolumePercent=100

      [Asio.Input.Mic]
      Driver=PipeASIO
      Channel=${toString micChannel}
      EnableSoftwareEndpointVolumeControl=1
      EnableSoftwareMasterVolumeControl=1
      SoftwareMasterVolumePercent=100
    '';

    # CDLC enabler: the classic 133 KB RSCDLCEnabler D3DX9_42.dll proxy
    # (vendored in blobs/rocksmith/). The exe stays untouched so the CRC
    # remains 0xd1b38fcb — RS_ASIO refuses unknown CRCs. Do NOT use the
    # newer "TooManyCoresFix" builds: their SetProcessAffinityMask hack
    # crashes RS2014 at startup under Proton (only needed for >32 threads).
    cdlcDll = ../../blobs/rocksmith/D3DX9_42.dll;

    # Home Manager overrides on top of the nixos-rocksmith HM module:
    # PipeASIO with 2 input channels + Zen-Go RS_ASIO.ini channel map
    # + CDLC enabler DLL + repatch/sync helpers.
    rocksmithHmModule = {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }: let
      steamDir = "${config.home.homeDirectory}/.local/share/Steam";
      gameDir = "${steamDir}/steamapps/common/Rocksmith2014";
      gameIni = "${gameDir}/RS_ASIO.ini";
      pasio = osConfig.programs.steam.rocksmithPatch.pipeasio;
      iniFile = pkgs.writeText "RS_ASIO-zengo.ini" rsAsioIni;
    in {
      # Expose both Zen-Go input channels to PipeASIO (upstream hardcodes
      # inputs=1, which only captures the mic on channel 0).
      xdg.configFile."pipeasio/config.ini".text = lib.mkForce (
        lib.generators.toINI {} {
          pipeasio = {
            buffer_size = pasio.buffer;
            input_device = pasio.inputDevice;
            inputs = 2;
            output_device = pasio.outputDevice;
            sample_rate = pasio.rate;
          };
        }
      );

      # patch-rocksmith copies a stock RS_ASIO.ini (guitar → channel 0 =
      # mic) into the game dir on every activation. Rewrite it afterwards
      # with the Zen-Go channel map and drop in the CDLC enabler DLL.
      # Runs unconditionally so it also heals after Steam game updates
      # wipe the files.
      home.activation.rocksmithChannelMap = lib.hm.dag.entryAfter ["patchRocksmith"] ''
        if [ -d "${gameDir}" ]; then
          install -m644 ${iniFile} "${gameIni}"
          install -m644 ${cdlcDll} "${gameDir}/D3DX9_42.dll"
          echo "rocksmith: wrote Zen-Go channel map + CDLC enabler to ${gameDir}"
        fi
      '';

      # Fresh-install helper: after installing RS2014 in Steam and
      # launching it ONCE (creates the Proton prefix), run `rocksmith-patch`
      # to apply everything. Needed because the upstream patchRocksmith
      # activation only fires when the HM generation changes — a fresh
      # install's first deploy happens before the prefix exists, and
      # re-deploying unchanged config would skip it.
      home.packages = [
        (pkgs.writeShellApplication {
          name = "rocksmith-patch";
          text = ''
            set -eu
            if [ ! -d "${gameDir}" ]; then
              echo "Rocksmith 2014 not found at ${gameDir} — install it in Steam first."
              exit 1
            fi
            if [ ! -d "${steamDir}/steamapps/compatdata/221680" ]; then
              echo "No Proton prefix yet — launch the game once in Steam, quit, then re-run."
              exit 1
            fi
            export STEAM_DIR="${steamDir}"
            export PIPEASIO_PREFIX="${pkgs.pipeasio}"
            /run/current-system/sw/bin/steam-run ${pkgs.patch-rocksmith}/bin/patch-rocksmith
            install -m644 ${iniFile} "${gameIni}"
            install -m644 ${cdlcDll} "${gameDir}/D3DX9_42.dll"
            echo "Done. Launch Rocksmith from Steam."
          '';
        })
      ];
    };
  in {
    imports = [
      self.inputs.nixos-rocksmith.nixosModules.default
      self.inputs.steam-config-nix.nixosModules.default
    ];

    config = lib.mkMerge [
      (lib.optionalAttrs (options ? home-manager) {
        home-manager.sharedModules = [rocksmithHmModule];
      })

      {
        # PipeASIO (from nixos-rocksmith overlay) builds against Wine's MSVC
        # toolchain, which requires accepting the Microsoft Visual Studio license.
        nixpkgs.config.microsoftVisualStudioLicenseAccepted = true;
        nixpkgs.config.allowUnfree = true;

        # ── Rocksmith + PipeASIO ──────────────────────────────────────
        # PipeASIO bridges Rocksmith's ASIO calls directly to PipeWire —
        # no JACK daemon or libjack.so preloading needed.
        programs.steam.rocksmithPatch = {
          enable = true;
          pipeasio = {
            buffer = 128; # ~2.7 ms at 48 kHz
            rate = 48000; # Rocksmith strictly requires 48 kHz
            # Leave empty for auto-detection (PipeWire default source/sink).
            # Pin explicitly if the wrong device is picked:  pw-cli ls | grep alsa
            inputDevice = "";
            outputDevice = "";
          };
        };

        # ── Audio group (required for PAM rtprio limits) ──────────────
        users.users.apetrovic.extraGroups = ["audio"];

        # ── Low-latency PipeWire tuning ───────────────────────────────
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

        # ── Kernel & power tuning for low-latency audio ───────────────
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

        # ── Useful debugging tools ────────────────────────────────────
        environment.systemPackages = mkIf cfg.enable (with pkgs; [
          pwvucontrol # PipeWire-native volume control
          qpwgraph # visual PipeWire/JACK patchbay
        ]);
      }
    ];
  };
}
