{
  charts,
  config,
  ...
}: let
  namespace = "garage-operator";
  domain = config.noosphere.domain;

  cluster-main = import ./cluster-main {inherit config namespace domain;};
  cluster-backup = import ./cluster-backup {inherit config namespace domain;};
in {
  imports = [
    ../../../_modules/templates/garage-admin-metrics.nix
    cluster-main
    cluster-backup
    ./block-census.nix
  ];
  applications.garage-operator = {
    inherit namespace;
    createNamespace = true;
    # The garageclusters CRD is ~1.1 MB. Client-side apply stores the whole
    # manifest in the last-applied-configuration annotation, capped at 256 KiB,
    # so every sync failed on that one resource and a CRD change in an operator
    # upgrade would never apply. Server-side apply keeps no such annotation.
    syncPolicy.syncOptions.serverSideApply = true;

    yamls = [
      (builtins.readFile ../../../../../../../vars/shared/garage-main-rpc-secret/garage-main-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-main-admin-token/garage-main-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-rpc-secret/garage-backup-rpc-secret/value)
      (builtins.readFile ../../../../../../../vars/shared/garage-backup-admin-token/garage-backup-admin-token/value)
      (builtins.readFile ../../../../../../../vars/shared/kaneo-s3-key/kaneo-s3-key/value)
      (builtins.readFile ../../../../../../../vars/shared/memos-s3-key/memos-s3-key/value)
      (builtins.readFile ../../../../../../../vars/shared/sccache-garage-key/sccache-garage-key/value)
    ];

    helm.releases.garage-operator = {
      chart = charts.rajsinghtech.garage-operator;
      values = {
        replicaCount = 3;

        # The chart can render a Grafana dashboard ConfigMap
        # (`<release>-garage-dashboard`, key `garage-prometheus.json`, with bucket size
        # and object-quota panels). Grafana picks it up through the dashboard sidecar
        # that kube-prometheus-stack runs by default
        # (grafana.sidecar.dashboards.enabled = true, label `grafana_dashboard`, value
        # "1", searchNamespace ALL), so the label below is not decoration: without it
        # the ConfigMap exists and nothing loads it. One ConfigMap for the release, so
        # both clusters show up in the same dashboard rather than two of the same name.
        grafanaDashboard = {
          enabled = true;
          labels.grafana_dashboard = "1";
        };

        # The operator's own /metrics (HTTPS :8443, authn/authz through
        # TokenReview + SubjectAccessReview) is the only source of per-bucket
        # quota series (garage_operator_bucket_*): Garage's admin /metrics,
        # scraped by the two garageAdminMetrics ServiceMonitors, has no
        # per-bucket numbers at all. The sccache bucket's quota alert
        # (prometheus-stack/garage-alerts.nix, group garage.bucket) reads the
        # utilization ratio from here, so this monitor is load-bearing. The
        # release label is the observability Prometheus' serviceMonitorSelector.
        serviceMonitor = {
          enabled = true;
          labels.release = "kube-prometheus-stack";
        };

        # Deliberately left off. The chart's bundled rule set covers the same ground as
        # resources.prometheusRules.garage in _env/apps/prometheus-stack/garage-alerts.nix
        # -- and three of its names (GarageClusterUnhealthy, GarageClusterUnavailable,
        # GarageBlockResyncErrors) are identical to rules written here, with different
        # expressions. Enabling both would emit two different alerts with the same name
        # on the same topic. Verified on 2026-11-06: `kubectl get prometheusrule -A`
        # shows no garage-operator rules, so nothing is colliding today.
      };
    };

    # The chart creates the `garage-operator-metrics-reader` ClusterRole
    # (get on the /metrics non-resource URL) but binds it to nobody -- the
    # kubebuilder scaffold leaves that to the installation. Without this
    # binding the operator's SubjectAccessReview rejects Prometheus' token and
    # the ServiceMonitor above scrapes 401s. Subject: the Prometheus CR's own
    # ServiceAccount (observability/prometheus-prometheus).
    resources.clusterRoleBindings.garage-operator-metrics-reader-prometheus = {
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "garage-operator-metrics-reader";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "prometheus-prometheus";
          namespace = "observability";
        }
      ];
    };
  };
}
