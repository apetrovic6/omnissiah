{
  self,
  lib,
  ...
}: {
  # flake.overlays.librewolf = final: prev: let
  #   newSource = final.fetchFromCodeberg {
  #     owner = "librewolf";
  #     repo = "source";
  #     rev = "152.0-1";
  #     hash = "sha256-T7ZRCmHx3jnFz7zzXS8btEepP9HRtKS8CWTehxdxIlM=";
  #     fetchSubmodules = true;
  #   };
  #   newSrc = final.fetchurl {
  #     url = "mirror://mozilla/firefox/releases/152.0/source/firefox-152.0.source.tar.xz";
  #     hash = "sha512-LHrfNnAEBj7p8zheaS9hLY5cDBBmK/KUmWwRgAHkPewSyoy0/XDmeiWpA9v1rfg9IuSH8Evz+TDaKoFcgDeM6w==";
  #   };
  #   localSettingsPrefs = final.runCommand "local-settings.js" {} ''
  #     substitute ${newSource}/settings/defaults/pref/local-settings.js $out \
  #       --replace-fail 'pref("general.config.filename", "librewolf.cfg");' ""
  #   '';
  # in {
  #   librewolf-unwrapped = prev.librewolf-unwrapped.overrideAttrs (old: {
  #     version = "152.0-1";
  #     src = newSrc;

  #     patches =
  #       (builtins.filter
  #         (p: !(builtins.elem (toString p) (map toString old.passthru.extraPatches)))
  #         old.patches)
  #       ++ ["${newSource}/patches/pref-pane/pref-pane-small.patch"];

  #     postPatch =
  #       ''
  #         rm -rf obj-x86_64-pc-linux-gnu
  #         patchShebangs mach build
  #       ''
  #       + ''
  #         while read patch_name; do
  #           echo "applying LibreWolf patch: $patch_name"
  #           patch -p1 < ${newSource}/$patch_name
  #         done <${newSource}/assets/patches.txt

  #         rm toolkit/components/ml/content/backends/OpenAIPipeline.mjs
  #         rm -rf toolkit/components/ml/vendor/openai

  #         cp -r ${newSource}/themes/browser .
  #         cp ${newSource}/assets/search-config.json services/settings/dumps/main/search-config.json
  #         sed -i '/MOZ_SERVICES_HEALTHREPORT/ s/True/False/' browser/moz.configure

  #         sed -i '/# This must remain last./i gkrust_features += ["glean_disable_upload"]\'$'\n' toolkit/library/rust/gkrust-features.mozbuild

  #         cp ${newSource}/patches/pref-pane/category-librewolf.svg browser/themes/shared/preferences
  #         cp ${newSource}/patches/pref-pane/librewolf.css browser/themes/shared/preferences
  #         cp ${newSource}/patches/pref-pane/librewolf.inc.xhtml browser/components/preferences
  #         cp ${newSource}/patches/pref-pane/librewolf.js browser/components/preferences

  #         for fn in browser/config/version.txt browser/config/version_display.txt; do
  #           echo "152.0-1" > "$fn"
  #         done

  #         echo "patching appstrings.properties"
  #         find . -path '*/appstrings.properties' -exec sed -i s/Firefox/LibreWolf/ {} \;

  #         for fn in $(find "${newSource}/l10n/en-US/browser" -type f -name '*.inc.*'); do
  #           target_fn=$(echo "$fn" | sed "s,${newSource}/l10n/en-US/browser,browser/locales/en-US," | sed "s,\.inc,,")
  #           cat "$fn" >> "$target_fn"
  #         done
  #       '';

  #     meta = old.meta // {knownVulnerabilities = [];};
  #   });
  #   librewolf = final.wrapFirefox final.librewolf-unwrapped {
  #     extraPrefsFiles = [
  #       "${newSource}/settings/librewolf.cfg"
  #       localSettingsPrefs
  #     ];
  #     extraPoliciesFiles = [
  #       "${newSource}/settings/distribution/policies.json"
  #     ];
  #     libName = "librewolf";
  #   };
  # };

  flake.overlays.vesktop = final: prev: {
    vesktop = prev.vesktop.override {
      pnpm_10_29_2 = final.pnpm_10;
    };
  };

  flake.overlays.helix = final: _prev: {
    # Replace nixpkgs' helix outright with the magos-wrapped one (config, theme,
    # keybinds, language servers baked in). `overrideAttrs` can't do this — it only
    # tweaks the nixpkgs derivation's attrs, so a `package` attr there is inert.
    helix = self.inputs.magos.packages.${final.system}.helix;
  };

  flake.overlays.herdr = final: _prev: {
    # Same deal as helix: the magos-wrapped herdr carries its config.toml via
    # HERDR_CONFIG_PATH, so it has to replace the package outright.
    herdr = self.inputs.magos.packages.${final.system}.herdr;
  };

  flake.overlays.bitwarden-desktop = final: prev: {
    prev.electron_39 = final.electron_41-bin;
  };

  flake.overlays.rke2 = final: prev: {
    rke2_1_35 = prev.rke2_1_35.overrideAttrs (old: {
      # k8s validates that UpstreamGolang (ldflag) == runtime.Version().
      # When nixpkgs builds with GOEXPERIMENT=boringcrypto, runtime.Version() gains the
      # "-X:boringcrypto" suffix but the ldflag doesn't — patch the ldflag to match.
      # Only apply when upstream actually sets GOEXPERIMENT=boringcrypto; newer nixpkgs
      # versions use GOFIPS140 instead and setting both causes a build error.
      ldflags =
        if (old.env or {}) ? GOEXPERIMENT && (old.env or {}).GOEXPERIMENT == "boringcrypto"
        then
          map (
            flag:
              if final.lib.hasPrefix "-X github.com/k3s-io/k3s/pkg/version.UpstreamGolang=" flag
              then flag + "-X:boringcrypto"
              else flag
          )
          old.ldflags
        else old.ldflags;
    });
  };

  flake.overlays.pangolin-cli = final: prev: {
    pangolin-cli = prev.pangolin-cli.overrideAttrs (old: {
      version = "0.12.0";
      src = old.src.override {
        hash = "sha256-0G5HsAa9I0ilPQ92qQIuYssfGvoZhLrF3kyO1+0JqEQ=";
      };
      vendorHash = "sha256-FCIp0VLmRO6TUPRDNd3Zl/CULwy00D8F4YTo/oQge+s=";
      doInstallCheck = false; # upstream 0.5.1 tag has version const still set to 0.5.0
    });
  };

  flake.overlays.newt = final: prev: {
    fosrl-newt = prev.fosrl-newt.overrideAttrs (old: {
      version = "1.13.0";
      src = final.fetchFromGitHub {
        owner = "fosrl";
        repo = "newt";
        rev = "1.13.0";
        hash = "sha256-Maw0qELlnh0m+NsQGdDC3wGYK8zi8Lbt7zwJqieR4hg=";
      };
      vendorHash = "sha256-+zMSzNbqmWm/DXL2xMUd5uPP5tSIybsRokwJ2zd0pf0=";
    });
  };
}
