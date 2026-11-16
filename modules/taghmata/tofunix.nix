# The `tofunix` CLI: OpenTofu with its providers, bound to the configuration
# in ./_tofunix.
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    packages.tofunix = let
      tofu = inputs.tofunix.lib {inherit pkgs lib;};
    in
      tofu.mkCliAio {
        plugins = [
          (tofu.mkOpentofuProvider {
            owner = "hashicorp";
            repo = "local";
            version = "2.9.1";
            hash = "sha256-nqtdLyIRKh0OFKycGjUB5CUP2b5joFNLSZ65M8GRhqI=";
          })
          (tofu.mkOpentofuProvider {
            owner = "goharbor";
            repo = "harbor";
            version = "3.12.5";
            hash = "sha256-mbFowZuYGVRKyZLp6AX1G89bBvbhYSY/OCW38gx7nss=";
          })

          # (tofu.mkOpentofuProvider {
          #   owner = "keycloak";
          #   repo = "keycloak";
          #   version = "5.6.0";
          #   hash = "sha256-NhXKDH82YHPHdP7pA+0VC61Sv5hCIkXjcvapqJjzhEI=";
          # })

          (tofu.mkOpentofuProvider {
            owner = "adyxax";
            repo = "forgejo";
            version = "1.5.8";
            hash = "sha256-vvwHjIcX79hWe2xjuw+LSTArTQ61zNUMGL02YgGGvp8=";
          })

          # (tofu.mkOpentofuProvider {
          #   owner = "kichiyaki";
          #   repo = "woodpecker";
          #   version = "0.5.0";
          #   hash = "";
          # })

          (tofu.mkOpentofuProvider {
            owner = "carlpett";
            repo = "sops";
            version = "1.4.1";
            hash = "sha256-AlnuMNkmsTTRVI7VVoC8q7y64zx/+K833RtgEFK8A2s=";
          })

          (tofu.mkOpentofuProvider {
            owner = "integrations";
            repo = "github";
            version = "6.6.0";
            hash = "sha256-4YaFJfGo7NPRGS51musdgGTtDTeYUtkkZYjDW7ISgHE=";
          })
          (tofu.mkOpentofuProvider {
            owner = "trozz";
            repo = "pocketid";
            version = "2.3.0";
            hash = "sha256-MEMEPn5PerMIh+CfFYyEqM0142RyfT4Eoq/gu4ijFTQ=";
          })

          (tofu.mkOpentofuProvider {
            owner = "hashicorp";
            repo = "kubernetes";
            version = "3.2.1";
            hash = "sha256-U9ZcNapbdiR0xzb/1j8Q2bPO4U2kh+VWse9OaSdehKs=";
          })
        ];
        moduleConfig = ./_tofunix/default.nix;
      };
  };
}
