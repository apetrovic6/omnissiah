# The prod environment: which applications are deployed to taghmata.
{...}: {
  imports = [
    # enginarium: what the cluster itself runs on
    ./apps/enginarium/rke2-config
    ./apps/enginarium/metallb
    ./apps/enginarium/cert-manager
    ./apps/enginarium/metrics-server
    ./apps/enginarium/reflector
    ./apps/enginarium/sops-secrets-operator
    ./apps/enginarium/cloudnative-pg

    # datavault: storage
    ./apps/datavault/longhorn
    ./apps/datavault/csi-driver-nfs
    ./apps/datavault/local-path-provisioner
    ./apps/datavault/garage-operator
    (import ./apps/datavault/garage-ui {
      cluster = "main";
      s3Service = "garage-s3-api";
    })
    (import ./apps/datavault/garage-ui {
      cluster = "backup";
      s3Service = "garage-backup-s3-api";
    })

    # augur: observability
    ./apps/augur/prometheus-stack
    ./apps/augur/prometheus-stack/garage-alerts.nix
    # cerberus is a host, not a cluster workload: its scrape config and its rules
    # live next to the stack's, for the same reason garage-alerts.nix does.
    ./apps/augur/prometheus-stack/cerberus-scrape.nix
    ./apps/augur/prometheus-stack/cerberus-alerts.nix
    ./apps/augur/alloy
    ./apps/augur/glances

    # pharos: access and identity
    ./apps/pharos/pocket-id

    # scriptorium: code and build
    ./apps/scriptorium/forgejo
    ./apps/scriptorium/harbor
    ./apps/scriptorium/woodpecker-ci
    ./apps/scriptorium/ncps

    # munitorum: media acquisition
    ./apps/munitorum/yarr

    # lexicanum: search and reference
    ./apps/lexicanum/searxng
    ./apps/lexicanum/karakeep

    # cogitator: everyday tools
    ./apps/cogitator/bytestash
    ./apps/cogitator/excalidraw
    ./apps/cogitator/vikunja

    # fabricata: products built from rust-app-template (../../_products.nix)
    ./apps/fabricata/pilot
  ];

  # CRD imports are now auto-discovered by the flake-module
  # nixidy.target is set in ../taghmata.nix (nixidy.envs.prod)

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = false;
  };
}
