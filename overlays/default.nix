{ ...}: {
  flake.overlays.rke2 = final: prev: {
    rke2_1_35 = prev.rke2_1_35.overrideAttrs (old: {
      # GOEXPERIMENT=boringcrypto makes runtime.Version() return "go1.26.1-X:boringcrypto"
      # but the ldflag sets UpstreamGolang=go1.26.1 — k8s validation fails on the mismatch.
      # Append the boringcrypto suffix so they match.
      ldflags = map (flag:
        if final.lib.hasPrefix "-X github.com/k3s-io/k3s/pkg/version.UpstreamGolang=" flag
        then flag + "-X:boringcrypto"
        else flag
      ) old.ldflags;
    });
  };

  flake.overlays.pangolin-cli = final: prev: {
    pangolin-cli = prev.pangolin-cli.overrideAttrs (old: {
      version = "0.5.1";
      src = old.src.override {
        hash = "sha256-+WwCYWC3CBvPnoakwD7rKJHckT5g4pUbtci/zRhGPFs=";
      };
      vendorHash = "sha256-gj7c8kMIX+xrGeoJjRQkPZdLuQuri2wAR0rXE2APCd8=";
      doInstallCheck = false; # upstream 0.5.1 tag has version const still set to 0.5.0
    });
  };

  flake.overlays.newt = final: prev: {
    fosrl-newt = prev.fosrl-newt.overrideAttrs (old: {
      version = "1.10.3";
      src = final.fetchFromGitHub {
        owner = "fosrl";
        repo = "newt";
        rev = "1.10.1";
        hash = "sha256-JU4aBwwdlxlBGHKmceyjcAVUZoT9voaWPFAkha4aXSE=";
      };
      vendorHash = "sha256-Sib6AUCpMgxlMpTc2Esvs+UU0yduVOxWUgT44FHAI+k=";
    });
  };
}
