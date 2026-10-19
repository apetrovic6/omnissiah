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
    options,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkMerge mkOption mkEnableOption types concatStringsSep optionals optionalAttrs;
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

    yb = cfg.yabridge;

    # The exact Wine that nixpkgs' yabridgectl wrapper puts on PATH
    # (wine-wow64-yabridge, currently 9.21), referenced by store path rather
    # than installed system-wide: a second `wine` on PATH would shadow
    # whatever else expects one. Using the same build for the installer as
    # for the plugin host is what keeps the prefix version consistent.
    ybWine = pkgs.wineWow64Packages.yabridge;

    # yabridgectl owns ~/.config/yabridgectl/config.toml and rewrites it on
    # `add`, so the dirs are registered through the CLI instead of having
    # Home Manager place a read-only file there that the CLI cannot update.
    # Absolute path, not a bare `yabridgectl`: this snippet is also spliced
    # into a Home Manager activation script, where PATH is not the user's and
    # the `|| true` guard would turn a missing binary into a silent no-op --
    # registering nothing, and leaving `sync` to find no plugins at all.
    ybAddDirs = concatStringsSep "\n" (map (d: ''
      if [ -d "$WINEPREFIX/${d}" ]; then
        ${pkgs.yabridgectl}/bin/yabridgectl add "$WINEPREFIX/${d}" >/dev/null 2>&1 || true
      fi
    '') yb.pluginDirs);

    yabridgeSync = pkgs.writeShellApplication {
      name = "yabridge-sync";
      runtimeInputs = [pkgs.yabridgectl];
      text = ''
        export WINEPREFIX="${yb.prefix}"
        if [ ! -d "$WINEPREFIX" ]; then
          echo "yabridge: no prefix at $WINEPREFIX -- install a plugin first with:"
          echo "  yabridge-install /path/to/installer.exe"
          exit 1
        fi
        ${ybAddDirs}
        yabridgectl sync --prune
        yabridgectl status
      '';
    };

    yabridgeInstall = pkgs.writeShellApplication {
      name = "yabridge-install";
      runtimeInputs = [pkgs.yabridgectl yabridgeSync];
      text = ''
        if [ "$#" -eq 0 ]; then
          echo "usage: yabridge-install <installer.exe> [args...]"
          exit 1
        fi
        export WINEPREFIX="${yb.prefix}"
        if [ ! -d "$WINEPREFIX" ]; then
          echo "yabridge: creating prefix at $WINEPREFIX"
          ${ybWine}/bin/wineboot -u
        fi
        ${ybWine}/bin/wine "$@"
        yabridge-sync
      '';
    };

    # Plain `winetricks` would act on ~/.wine with the system wine. This one
    # is pinned to the yabridge prefix and the yabridge Wine, which is the
    # only combination that matters here.
    yabridgeWinetricks = pkgs.writeShellApplication {
      name = "yabridge-winetricks";
      runtimeInputs = [pkgs.winetricks];
      text = ''
        export WINEPREFIX="${yb.prefix}"
        export WINE="${ybWine}/bin/wine"
        export PATH="${ybWine}/bin:$PATH"
        exec winetricks "$@"
      '';
    };

    # iLok License Manager has to live in the SAME prefix as the plugins:
    # the plugins query the PACE components installed alongside them, so an
    # ILM in its own prefix authorises nothing.
    ilokInstall = pkgs.writeShellApplication {
      name = "ilok-install";
      runtimeInputs = [yabridgeInstall];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: ilok-install /path/to/iLokLicenseManager.exe"
          echo
          echo "Download it from https://www.ilok.com/#!license-manager first."
          exit 1
        fi
        echo "iLok: installing into ${yb.prefix}"
        echo "iLok: machine activation and Cloud may work; a USB dongle will not."
        yabridge-install "$1"
      '';
    };

    ilok = pkgs.writeShellApplication {
      name = "ilok";
      text = ''
        export WINEPREFIX="${yb.prefix}"
        # Located rather than hardcoded: PACE has moved the install path
        # between versions, and the name carries spaces either way.
        ilm=$(find "$WINEPREFIX/drive_c" -iname "iLok License Manager.exe" 2>/dev/null | head -n1)
        if [ -z "$ilm" ]; then
          echo "iLok: License Manager not found in ${yb.prefix}"
          echo "Install it with:  ilok-install /path/to/iLokLicenseManager.exe"
          exit 1
        fi
        exec ${ybWine}/bin/wine "$ilm" "$@"
      '';
    };
  in {
    # Inert until programs.craftapps.enable, so an unconditional import is
    # safe even on hosts that never turn proaudio on.
    imports = [self.inputs.nix-craftapps.nixosModules.default];

    options.services.imperium.proaudio = {
      enable = mkEnableOption "pro audio / DAW support";

      user = mkOption {
        type = types.str;
        default = "apetrovic";
        description = ''
          User whose home holds the plugin directories and the Wine prefix.
          Used to place impermanence persistence entries.
        '';
      };

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

      yabridge = {
        enable = mkEnableOption "yabridge, for Windows VST2/VST3/CLAP plugins under Wine";

        prefix = mkOption {
          type = types.str;
          default = "$HOME/.wine-yabridge";
          description = ''
            WINEPREFIX holding the Windows plugins. Deliberately not ~/.wine:
            a dedicated prefix keeps plugins clear of other Wine apps, and
            stops an unrelated newer wine from upgrading the prefix past the
            Wine version yabridge pins (prefixes do not downgrade cleanly).
          '';
        };

        pluginDirs = mkOption {
          type = types.listOf types.str;
          default = [
            "drive_c/Program Files/Common Files/VST3"
            "drive_c/Program Files/Common Files/CLAP"
            "drive_c/Program Files/Common Files/VST2"
            "drive_c/Program Files/Steinberg/VstPlugins"
            "drive_c/Program Files/VstPlugins"
          ];
          description = ''
            Directories inside the prefix for yabridgectl to index, relative
            to the prefix root. Ones that do not exist are skipped, so the
            default covers the usual install locations without complaining.
          '';
        };
      };

      nam = {
        enable = mkEnableOption "Neural Amp Modeler capture + impulse response directories";

        dir = mkOption {
          type = types.str;
          default = ".local/share/nam";
          description = ''
            Where NAM captures and cabinet IRs live, relative to the home
            directory. Kept under ~/.local/share deliberately: the
            impermanence module already persists that wholesale, so the
            captures survive the boot-time rollback without another entry.

            NAM has no search-path convention -- the plugin opens a file
            chooser -- so this is purely a stable place to point it at.
          '';
        };
      };

      ilok = {
        enable =
          mkEnableOption ''
            iLok License Manager inside the yabridge Wine prefix.

            Only machine ("PC") activation and iLok Cloud have any chance of
            working. The iLok USB dongle does NOT: there is no Linux driver
            for the key and Wine cannot pass it through, so even USB-over-IP
            forwarding leaves nothing able to talk to it. Plugins whose
            license is USB-only cannot be authorised on this machine at all.

            Unsupported by PACE either way -- treat it as empirical
          '';
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

          # GuitarML Proteus: neural amp modelling that ships VST3, so it is
          # the only neural amp option SoundCraft can actually load. Its
          # engine and capture format are not NAM's -- it takes .json
          # profiles, not .nam -- so it complements NAM rather than replacing
          # it. See the nam option below.
          proteus

          # LV2-only: invisible to SoundCraft, used by Ardour and Carla.
          calf
          airwindows-lv2
          x42-plugins
          neural-amp-modeler-lv2
          ir-lv2 # cabinet impulse responses, to pair with NAM
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

    config = mkIf cfg.enable (mkMerge [
      {
      # iLok rides on the yabridge prefix and the Wine pinned with it, so it
      # has nothing to install into on its own.
      assertions = [
        {
          assertion = cfg.ilok.enable -> yb.enable;
          message = "services.imperium.proaudio.ilok.enable requires yabridge.enable (it installs into the yabridge Wine prefix).";
        }
      ];

      # ── Impermanence ──────────────────────────────────────────────────
      # phalanx rolls the root subvolume back to pristine on every boot, so
      # anything not listed here is gone at reboot. Without it the whole Wine
      # prefix, every installed Windows plugin, the yabridgectl index and the
      # generated stubs are destroyed nightly -- and for iLok machine
      # activation that means burning an activation on every single boot.
      #
      # ~/.local/share is already persisted wholesale by the impermanence
      # module, which is why the NAM model directory lives under it and needs
      # no entry of its own.
      environment.persistence."/persist".users.${cfg.user}.directories =
        mkIf config.services.imperium.impermanence.enable
        ([".lv2" ".vst3" ".clap" ".lxvst" ".ladspa" ".dssi"]
          ++ optionals yb.enable [
            ".vst"
            ".config/yabridgectl"
            # Relative to the home dir, which is how impermanence wants it;
            # keep in step with yabridge.prefix if that is ever changed.
            ".wine-yabridge"
          ]);

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

      environment.systemPackages =
        cfg.daws
        ++ cfg.plugins
        ++ cfg.tools
        # yabridgectl finds libyabridge-chainloader-*.so by searching
        # NIX_PROFILES, and /run/current-system/sw is first in it, so simply
        # installing yabridge here is enough -- no `yabridgectl set --path`.
        ++ optionals yb.enable [
          pkgs.yabridge
          pkgs.yabridgectl
          yabridgeInstall
          yabridgeSync
          yabridgeWinetricks
        ]
        ++ optionals cfg.ilok.enable [ilokInstall ilok];

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
      }

      # ── yabridge re-sync ────────────────────────────────────────────────
      # yabridge's stubs embed the version they were generated from, so
      # `yabridgectl sync` MUST be re-run after every yabridge bump or the
      # plugins stop loading. Doing it at activation makes that automatic.
      # --no-verify because the post-install checks spawn Wine, which has no
      # business running inside an activation script; yabridge-sync does the
      # verifying pass when invoked by hand.
      (optionalAttrs (options ? home-manager) {
        home-manager.sharedModules =
          optionals yb.enable [
            ({lib, ...}: {
              home.activation.yabridgeSync = lib.hm.dag.entryAfter ["writeBoundary"] ''
                export WINEPREFIX="${yb.prefix}"
                if [ -d "$WINEPREFIX" ]; then
                  ${ybAddDirs}
                  ${pkgs.yabridgectl}/bin/yabridgectl sync --prune --no-verify || \
                    echo "yabridge: sync failed -- run 'yabridge-sync' to see why"
                fi
              '';
            })
          ]
          ++ optionals cfg.nam.enable [
            ({
              config,
              lib,
              ...
            }: {
              home.activation.namDirs = lib.hm.dag.entryAfter ["writeBoundary"] ''
                run mkdir -p \
                  "${config.home.homeDirectory}/${cfg.nam.dir}/captures" \
                  "${config.home.homeDirectory}/${cfg.nam.dir}/irs"
              '';
            })
          ];
      })
    ]);
  };
}
