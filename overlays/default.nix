{lib, ...}: {
  flake.overlays.openldap = final: prev: {
    openldap = prev.openldap.overrideAttrs (_: {
      doCheck = false;
    });
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
      version = "0.8.0";
      src = old.src.override {
        hash = "sha256-0G5HsAa9I0ilPQ92qQIuYssfGvoZhLrF3kyO1+0JqEQ=";
      };
      vendorHash = "sha256-FCIp0VLmRO6TUPRDNd3Zl/CULwy00D8F4YTo/oQge+s=";
      doInstallCheck = false; # upstream 0.5.1 tag has version const still set to 0.5.0
    });
  };

  flake.overlays.newt = final: prev: {
    fosrl-newt = prev.fosrl-newt.overrideAttrs (old: {
      version = "1.11.0";
      src = final.fetchFromGitHub {
        owner = "fosrl";
        repo = "newt";
        rev = "1.12.3";
        hash = "sha256-Maw0qELlnh0m+NsQGdDC3wGYK8zi8Lbt7zwJqieR4hg=";
      };
      vendorHash = "sha256-+zMSzNbqmWm/DXL2xMUd5uPP5tSIybsRokwJ2zd0pf0=";
    });
  };
}
