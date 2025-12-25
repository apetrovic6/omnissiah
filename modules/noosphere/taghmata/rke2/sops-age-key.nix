{...}: {
  flake.nixosModules.noosphere = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.noosphere.taghmata.sopsAgeKey;
  in {
    options.noosphere.taghmata.sopsAgeKey = {
      enable = lib.mkEnableOption "Manage SOPS Age key file via clan vars and publish it as a Kubernetes Secret";

      generatorName = lib.mkOption {
        type = lib.types.str;
        default = "sops-age-key";
        description = "Clan vars generator name.";
      };

      namespace = lib.mkOption {
        type = lib.types.str;
        default = "sops";
        description = "Namespace where sops-secrets-operator runs.";
      };

      secretName = lib.mkOption {
        type = lib.types.str;
        default = "sops-age-key-file";
        description = "Kubernetes Secret name that contains the Age key file.";
      };

      kubeconfigPath = lib.mkOption {
        type = lib.types.str;
        default = "/etc/rancher/rke2/rke2.yaml";
        description = "Kubeconfig path on the control-plane node.";
      };
    };

    config = lib.mkIf cfg.enable {
      # 1) Clan vars: store the Age key file as a secret, deploy at runtime (/run/secrets/...)
      clan.core.vars.generators.${cfg.generatorName} = {
        # same key across all nodes that include this module
        share = true;

        prompts.key = {
          description = "Paste the full AGE private key file content (keys.txt) for SOPS";
          type = "multiline-hidden";
          persist = true; # stores in backend (sops), not in nix store
        };

        files.key = {
          deploy = true;
          owner = "root";
          group = "root";
          mode = "0400";
          neededFor = "services";
        };
      };

      # 2) Publish it into Kubernetes as the Secret that the sops-secrets-operator mounts
      environment.systemPackages = [pkgs.kubectl];

      systemd.services."publish-${cfg.secretName}" = {
        description = "Publish clan vars Age key file as K8s Secret ${cfg.namespace}/${cfg.secretName}";
        after = ["rke2-server.service" "network-online.target"];
        wants = ["rke2-server.service" "network-online.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          Environment = [
            "KUBECONFIG=${cfg.kubeconfigPath}"
          ];
        };

        script = let
          kubectl = "${pkgs.kubectl}/bin/kubectl";
          ageKeyPath = config.clan.core.vars.generators.${cfg.generatorName}.files.key.path;
        in ''
          set -euo pipefail

          ${kubectl} get ns ${cfg.namespace} >/dev/null 2>&1 || ${kubectl} create ns ${cfg.namespace}

          ${kubectl} -n ${cfg.namespace} create secret generic ${cfg.secretName} \
            --from-file=key=${ageKeyPath} \
            --dry-run=client -o yaml | ${kubectl} apply -f -
        '';
      };
    };
  };
}
