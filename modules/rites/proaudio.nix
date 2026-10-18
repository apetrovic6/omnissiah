{self, ...}: {
  # Pro audio / DAW support, layered on top of the realtime groundwork that
  # modules/rites/rocksmith.nix already lays down (PAM rtprio + memlock for
  # @audio, preempt=full, usbcore.autosuspend=-1, performance governor,
  # PipeWire at 48 kHz / quantum 128, node suspend disabled).
  #
  # Deliberately NOT musnix: everything musnix does here is already covered
  # except the plugin search paths, and musnix.kernel.realtime would repoint
  # boot.kernelPackages -- rebuilding the NVIDIA module outside the binary
  # cache and reopening the kernel-module/userspace mismatch that breaks
  # niri screen sharing. A USB interface at a 2.7 ms quantum does not need
  # CONFIG_PREEMPT_RT.
  flake.nixosModules.proaudio = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types concatStringsSep;
    cfg = config.services.imperium.proaudio;

    # NixOS has no FHS plugin directories, so every host (SoundCraft, Ardour,
    # Carla, Bitwig) finds zero plugins unless these are set explicitly. This
    # is the one thing musnix is genuinely best at, lifted without the kernel.
    # $HOME comes first so a hand-dropped plugin shadows the packaged one.
    pluginPath = dir:
      concatStringsSep ":" [
        "$HOME/.${dir}"
        "$HOME/.nix-profile/lib/${dir}"
        "/run/current-system/sw/lib/${dir}"
      ];
  in {
    # Inert until programs.craftapps.enable, so an unconditional import is
    # safe even on hosts that never turn proaudio on.
    imports = [self.inputs.nix-craftapps.nixosModules.default];

    options.services.imperium.proaudio = {
      enable = mkEnableOption "pro audio / DAW support";

      jack = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Expose PipeWire's JACK implementation. Needed by Ardour, Carla and
          Bitwig, and it makes them visible as nodes in qpwgraph for routing.

          SoundCraft does NOT use this -- it only speaks ALSA (CoreAudio /
          WASAPI / ALSA / WebAudio), so it reaches PipeWire through the ALSA
          compat plugin instead. Harmless to leave on either way.
        '';
      };

      maxQuantum = mkOption {
        type = types.int;
        default = 2048;
        description = ''
          Largest buffer a client may negotiate. rocksmith.nix pins the
          *default* quantum to 128 (~2.7 ms) for live guitar monitoring, and
          caps max-quantum at 512. A mixdown session with a deep plugin chain
          needs room to ask for 1024 or 2048 instead of xrunning; clients that
          want low latency still get it, because this only raises the ceiling.
        '';
      };

      allowedRates = mkOption {
        type = types.listOf types.int;
        default = [44100 48000 88200 96000];
        description = ''
          Sample rates PipeWire may switch to. Without this the 48 kHz pinned
          by rocksmith.nix silently resamples 44.1 kHz project material.
          Rocksmith still negotiates 48 kHz, which it strictly requires.
        '';
      };

      soundcraft = {
        enable = mkEnableOption "SoundCraft, via the nix-craftapps flake";
      };

      daws = mkOption {
        type = types.listOf types.package;
        default = [pkgs.ardour];
        description = ''
          DAWs to install. Ardour by default: SoundCraft is pre-alpha and
          cannot yet pick an audio interface or buffer size, so keep a mature
          one around. reaper and bitwig-studio are unfree -- see the note on
          nixpkgs.config.allowUnfreePredicate in machines/phalanx.
        '';
      };

      plugins = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          # Ship CLAP + VST3 -- the formats SoundCraft can actually host.
          surge-XT # clap vst3 lv2
          cardinal # clap vst3 vst lv2
          lsp-plugins # clap vst3 vst lv2 ladspa
          zam-plugins # clap vst3 vst lv2 ladspa
          dragonfly-reverb # clap vst3 lv2
          distrho-ports # vst3 vst lv2 -- VST3 only, no CLAP

          # LV2-only: invisible to SoundCraft, used by Ardour and Carla.
          calf
          airwindows-lv2
          x42-plugins
          neural-amp-modeler-lv2
          gxplugins-lv2

          # Deliberately omitted: pkgs.sfizz builds only libsfizz.so plus the
          # sfizz_jack/sfizz_render CLIs -- no LV2 or VST3 bundle, so it is
          # not loadable in any DAW. pkgs.tap-plugins is LADSPA-only.
        ];
        description = ''
          Plugin packages. SoundCraft hosts CLAP, VST3 and AU -- NOT LV2 --
          and upstream's own feature tour only commits to CLAP, so the
          CLAP/VST3 half of this list is what it will actually see. The
          LV2-only entries are still worth having for Ardour and Carla.
        '';
      };

      tools = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          carla # modular plugin host / rack
          qpwgraph # PipeWire + JACK patchbay
          pwvucontrol # PipeWire-native mixer
          guitarix # amp sim, pairs with the Zen-Go
          sox
          flac
        ];
        description = "Supporting tools and utilities.";
      };
    };

    config = mkIf cfg.enable {
      # ── Plugin discovery ──────────────────────────────────────────────
      environment.sessionVariables = {
        CLAP_PATH = pluginPath "clap";
        LV2_PATH = pluginPath "lv2";
        VST_PATH = pluginPath "vst";
        VST3_PATH = pluginPath "vst3";
        LXVST_PATH = pluginPath "lxvst";
        LADSPA_PATH = pluginPath "ladspa";
        DSSI_PATH = pluginPath "dssi";
      };

      services.pipewire = {
        jack.enable = cfg.jack;

        # A separate drop-in rather than extending rocksmith.nix's
        # "92-low-latency": extraConfig.pipewire.<name> is a JSON-valued
        # option, so two modules defining the same name is an evaluation
        # conflict, not a merge. 93- sorts later, and PipeWire applies
        # conf.d files in lexical order with later keys winning.
        extraConfig.pipewire."93-proaudio" = {
          "context.properties" = {
            "default.clock.allowed-rates" = cfg.allowedRates;
            "default.clock.max-quantum" = cfg.maxQuantum;
          };
        };
      };

      environment.systemPackages = cfg.daws ++ cfg.plugins ++ cfg.tools;

      # ── SoundCraft ────────────────────────────────────────────────────
      # nix-craftapps packages all twelve ArtCraft apps; enableAll stays off
      # so only SoundCraft lands. These are upstream prebuilt binaries
      # (sourceProvenance = binaryNativeCode) autoPatchelf'd into place, and
      # upstream cuts releases daily -- flake.lock is the stability mechanism.
      programs.craftapps = mkIf cfg.soundcraft.enable {
        enable = true;
        apps.soundcraft.enable = true;

        # The apps read fonts only from /usr/share/fonts and ignore
        # fontconfig. linkFonts (default true) tmpfiles-symlinks that to
        # /run/current-system/sw/share/X11/fonts. It is recreated every boot,
        # so impermanence on this host is not a problem.
        linkFonts = true;
      };
    };
  };
}
