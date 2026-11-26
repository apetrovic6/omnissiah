# The `tofunix` CLI: OpenTofu with its providers, bound to the configuration
# in ./_tofunix. `nix build .#tofunix.tfjson` is the generated configuration.
{inputs, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    packages.tofunix = let
      tofu = inputs.tofunix.lib {inherit pkgs lib;};

      # owner/repo = { version; hash; }. To bump one: change the version, empty
      # the hash, and take the new one from the build error.
      providers = {
        "hashicorp/local" = {
          version = "2.9.1";
          hash = "sha256-nqtdLyIRKh0OFKycGjUB5CUP2b5joFNLSZ65M8GRhqI=";
        };
        "goharbor/harbor" = {
          version = "3.12.5";
          hash = "sha256-mbFowZuYGVRKyZLp6AX1G89bBvbhYSY/OCW38gx7nss=";
        };
        "adyxax/forgejo" = {
          version = "1.5.8";
          hash = "sha256-vvwHjIcX79hWe2xjuw+LSTArTQ61zNUMGL02YgGGvp8=";
        };
        "go-gitea/gitea" = {
          version = "0.8.1";
          hash = "sha256-5XasOnXuplfri018rogl5rZq9OKjJwQ0CUsUusQTIbg=";
        };
        "carlpett/sops" = {
          version = "1.4.1";
          hash = "sha256-AlnuMNkmsTTRVI7VVoC8q7y64zx/+K833RtgEFK8A2s=";
        };
        "integrations/github" = {
          version = "6.6.0";
          hash = "sha256-4YaFJfGo7NPRGS51musdgGTtDTeYUtkkZYjDW7ISgHE=";
        };
        "trozz/pocketid" = {
          version = "2.3.0";
          hash = "sha256-MEMEPn5PerMIh+CfFYyEqM0142RyfT4Eoq/gu4ijFTQ=";
        };
        "bpg/proxmox" = {
          version = "0.122.0";
          hash = "sha256-eOiXPwEF1tGnua6JHGKwf0zI9S6i2EugV6GY1i9R5yw=";
        };
        "hashicorp/kubernetes" = {
          version = "3.2.1";
          hash = "sha256-U9ZcNapbdiR0xzb/1j8Q2bPO4U2kh+VWse9OaSdehKs=";
        };
      };
      cli = tofu.mkCliAio {
        plugins = lib.mapAttrsToList (source: pin: let
          parts = lib.splitString "/" source;
        in
          tofu.mkOpentofuProvider {
            owner = lib.head parts;
            repo = lib.last parts;
            inherit (pin) version hash;
          })
        providers;

        moduleConfig = {
          imports = [./_tofunix];
          # Plain data the configuration reads, so no file in it has to count
          # `../` to reach cartographa.
          _module.args = {
            inherit (import ../cartographa/_cartographa.nix) noosphere vars;
            products = import ./_products.nix;
          };
        };
      };
    in
      # The state bucket's S3 keys are decrypted here, per run, into this
      # process only. They used to be exported by .envrc, which put them in
      # the environment of everything started from the repo shell -- editors,
      # language servers, build scripts and coding agents included.
      (pkgs.writeShellApplication {
        name = "tofunix";
        runtimeInputs = [pkgs.sops pkgs.git];
        text = ''
          root=$(git rev-parse --show-toplevel)
          secret="$root/vars/shared/tofunix-s3-secrets/tofunix-s3-secrets/value"
          AWS_ACCESS_KEY_ID=$(sops decrypt --input-type yaml --extract '["access_key_id"]' "$secret")
          AWS_SECRET_ACCESS_KEY=$(sops decrypt --input-type yaml --extract '["secret_access_key"]' "$secret")
          export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
          exec ${lib.getExe' cli "tofunix"} "$@"
        '';
      })
      # mkCliAio attaches these with `//`; keeps `nix build .#tofunix.tfjson`.
      // {inherit (cli) module tfjson gitlab;};
  };
}
