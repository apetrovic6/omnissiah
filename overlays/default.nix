{
  self,
  lib,
  ...
}: {
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

  # pi and omp are no longer provided as overlays. The NixOS modules
  # (self.inputs.magos.nixosModules.pi / .omp) handle building, wrapping,
  # and installing — import them and set options instead.

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

  # sops-nix's sops-install-secrets still asks for buildGo125Module, which
  # nixpkgs removed on 2026-09-15 (Go 1.25 EOL). Upstream has not bumped it
  # yet, and it comes in transitively via clan-core, so shim the alias back.
  # Drop this once sops-nix builds with a current Go.
  flake.overlays.go125-shim = final: _prev: {
    buildGo125Module = final.buildGo126Module;
  };
}
