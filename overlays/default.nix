{ ... }: {
  flake.overlays.rke2 = final: prev: {
    rke2_1_35 = prev.rke2_1_35.overrideAttrs (old: {
      # GOEXPERIMENT=boringcrypto makes runtime.Version() return "go1.26.1-X:boringcrypto"
      # but the ldflag sets UpstreamGolang=go1.26.1 — k8s validation fails on the mismatch.
      # Append the boringcrypto suffix so they match.
      ldflags =
        map (
          flag:
            if final.lib.hasPrefix "-X github.com/k3s-io/k3s/pkg/version.UpstreamGolang=" flag
            then flag + "-X:boringcrypto"
            else flag
        )
        old.ldflags;
    });
  };

  flake.overlays.pangolin-cli = final: prev: {
    pangolin-cli = prev.pangolin-cli.overrideAttrs (old: {
      version = "0.6.0";
      src = old.src.override {
        hash = "sha256-9uQLCSH7LLl8I/LgsgTo6w808iwmH1FF0GYNn5xyVuc=";
      };
      vendorHash = "sha256-eBrglhyqKy6pG9eF0yfJdCOLxeWys4atKAp9Jgtzdj8=";
       doInstallCheck = false; # upstream 0.5.1 tag has version const still set to 0.5.0
    });
  };

  flake.overlays.newt = final: prev: {
    fosrl-newt = prev.fosrl-newt.overrideAttrs (old: {
      version = "1.11.0";
      src = final.fetchFromGitHub {
        owner = "fosrl";
        repo = "newt";
        rev = "1.11.0";
        hash = "sha256-CHrBMHjRvxE78FfooYAH7NOUKNPxbHnWLMkJ4kH3Qkc=";
      };
      vendorHash = "sha256-YIcuj1S+ZWAzXZOMZbppTvsDcW1W1Sy8ynfMkzLMQpM=";
    });
  };
}
