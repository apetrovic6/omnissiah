# The prod environment: which applications are deployed to taghmata.
{...}: {
  imports = [
    ./apps/rke2-config
    ./apps/metrics-server
    ./apps/cloudnative-pg
    ./apps/longhorn
    ./apps/metallb
    ./apps/sops-secrets-operator
    ./apps/alloy
    ./apps/cert-manager
    ./apps/woodpecker-ci
    ./apps/prometheus-stack
    ./apps/prometheus-stack/garage-alerts.nix
    # cerberus is a host, not a cluster workload: its scrape config and its rules
    # live next to the stack's, for the same reason garage-alerts.nix does.
    ./apps/prometheus-stack/cerberus-scrape.nix
    ./apps/prometheus-stack/cerberus-alerts.nix
    ./apps/yarr
    ./apps/csi-driver-nfs
    ./apps/excalidraw
    ./apps/karakeep
    ./apps/bytestash
    ./apps/harbor
    ./apps/glances
    ./apps/reflector
    ./apps/forgejo
    ./apps/searxng
    ./apps/garage-operator
    # The two Garage web UIs. They differ in one chart value: main sets the
    # admin token's `existingSecret` beside `config.garage`, backup inside it.
    # One of the two is probably not where the chart reads it; both are kept
    # as deployed.
    (import ./apps/garage-ui {
      cluster = "main";
      s3Service = "garage-s3-api";
      extraSecrets = ["garage-main-ui-admin-token"];
      adminTokenBesideGarage = true;
    })
    (import ./apps/garage-ui {
      cluster = "backup";
      s3Service = "garage-backup-s3-api";
      adminTokenBesideGarage = false;
    })
    ./apps/local-path-provisioner
    ./apps/vikunja
    ./apps/pocket-id
    ./apps/ncps
    ./apps/pilot
  ];

  # CRD imports are now auto-discovered by the flake-module
  # nixidy.target is configured in ../charts.nix via noosphere.nixidy.envs.prod

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = false;
  };
}
