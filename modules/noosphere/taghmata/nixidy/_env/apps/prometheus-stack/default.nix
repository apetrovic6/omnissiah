{
  config,
  charts,
  ...
}: let
  namespace = "observability";
  domain = config.noosphere.domain;
in {
  applications.prometheus-crds = {
    inherit namespace;

    helm.releases.prometheus-operator-crds = {
      chart = charts.prometheus-community.prometheus-operator-crds;
    };
  };

  applications.prometheus-grafana = {
    inherit namespace;
    createNamespace = true;

    helm.releases.kube-prometheus-stack = {
      chart = charts.prometheus-community.kube-prometheus-stack;
      includeCRDs = false;

      values = {
        crds.enabled = true;
        fullnameOverride = "prometheus";

        # Storage. `storageSpec: {}` today means the operator falls back to an
        # emptyDir named prometheus-prometheus-prometheus-db: the 30d retention
        # below would then delete nothing, because a pod restart wipes the TSDB.
        # (Observed: retention=10d, but the oldest queryable sample was the pod's
        # own start time, 3d15h back.)
        #
        # storageClassName = longhorn, because that is what every other
        # stateful-but-unpinned workload here uses (harbor, forgejo, woodpecker,
        # the *arr stack, vikunja, karakeep, bytestash), and Prometheus is one of
        # them: replicas=1 with only a *preferred* anti-affinity, so the pod can
        # land on any node and the volume has to follow it over the network.
        # local-path is what Garage's own pods use, and for a reason that does
        # not apply here: those are pinned one-per-machine by required
        # anti-affinity, Garage replicates its own data, and the operator owns
        # those claims. local-path is node-bound (WaitForFirstConsumer, Retain) so
        # a Prometheus pod rescheduled onto another node could not bind its old
        # volume -- which is exactly the failure mode the new volume is meant to
        # remove -- and it has allowVolumeExpansion=false, so a 30-day TSDB could
        # never grow. Longhorn gives Retain, 2 replicas (numberOfReplicas=2 /
        # persistence.defaultClassReplicaCount=2), expansion, and it is the one
        # storage class with a backup target (NFS on the NAS) and snapshot
        # RecurringJobs already defined. CNPG's longhorn-cnpg-strict-local is the
        # wrong shape: it is dataLocality=strict-local for latency-sensitive
        # random IO, and a TSDB is sequential appends + compaction.
        # Cost: 2 replicas x 50Gi = 100Gi of the 590Gi-per-node schedulable
        # Longhorn pool, on nodes with ~1.6TB free on /var/lib/longhorn.
        #
        # Size is set from the measured rate, not a guess. Before the change:
        # prometheus_tsdb_head_series = 282810,
        # rate(prometheus_tsdb_head_samples_appended_total[15m]) = 10362 samples/s,
        # sum(prometheus_tsdb_storage_blocks_bytes) = 4.46GB for 3d15h of data
        # => 1.31 GB/day => 1.37 bytes per sample. Adding Garage is 6 targets x
        # ~3.3-3.5k samples per scrape at 30s = ~680 samples/s (+6.6%), so
        # ~11.0k samples/s => 1.41 GB/day => 30d ~= 42GB, plus the WAL.
        # 50Gi leaves ~19% headroom; retentionSize 45GB is the guard rail: it is
        # above the 30d figure, so time-based retention decides when data goes
        # away, and a cardinality spike evicts old data instead of filling the
        # volume and crash-looping Prometheus.
        prometheus.prometheusSpec = {
          retention = "30d";
          retentionSize = "45GB";

          storageSpec.volumeClaimTemplate.spec = {
            accessModes = ["ReadWriteOnce"];
            storageClassName = "longhorn";
            resources.requests.storage = "50Gi";
          };

          # Not load-bearing today: the API server already defaults a
          # StatefulSet to Retain/Retain. Declared because switching from
          # emptyDir to a volumeClaimTemplate changes an immutable field, and the
          # operator may have to delete and recreate the StatefulSet to do it.
          # That is also the restart this change causes.
          persistentVolumeClaimRetentionPolicy = {
            whenDeleted = "Retain";
            whenScaled = "Retain";
          };
        };

        alertManager = {
          fullNameOverride = "alertmanager";
          enabled = true;
          ingress.enabled = false;
        };

        grafana = {
          enabled = true;
          fullnameOverride = "grafana";
          forceDeployDatasources = false;
          forceDeployDashboards = false;
          defaultDashboardsEnabled = true;
          serviceMonitor.enabled = true;
          admin = {
            existingSecret = "grafana-admin-secret";
            userKey = "admin-user";
            passwordKey = "admin-password";
          };
        };

        kubeApiServer.enabled = true;
        kubelet = {
          enabled = true;
          serviceMonitor = {
            metricRelabelings = [
              {
                action = "replace";
                sourceLabels = ["node"];
                targetLabel = "instance";
              }
            ];
          };
        };

        # Disable control plane component monitoring for RKE2
        # These create Endpoint resources that ArgoCD excludes
        kubeControllerManager.enabled = false;
        kubeEtcd.enabled = false;
        kubeScheduler.enabled = false;
        kubeProxy.enabled = false;

        # CoreDNS works fine
        coredDns.enabled = true;

        kube-state-metrics = {
          fullnameOverride = "kube-state-metrics";
        };

        # ingress = {
        #   enabled = true;
        #   ingressClassName = "traefik";
        #   hosts =
        # };
      };
    };

    yamls = [
      ''
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
            name: grafana-admin-secret
            namespace: observability
        spec:
            secretTemplates:
                - name: ENC[AES256_GCM,data:amEb//H1Kn2FPTYqaAhs1EewacQ=,iv:zGAYTF2HzAlv42/uRtg6/7KZuUqQ9HtoIGPqzobhN+w=,tag:1eSzFs6RfwE9XysFtD7EAA==,type:str]
                  type: ENC[AES256_GCM,data:LQlnKDfr,iv:I1UOzWuPBgvPpcw5SbzPIOE0dNZ4O7XETT4M5lRFT5A=,tag:CBZ+agxOEP//+6C8nZZiDg==,type:str]
                  stringData:
                    admin-user: ENC[AES256_GCM,data:UibhMLk=,iv:QKDw+uO/a8rgWBBwq3DNY399xq9FQr3sgJd8Trv5y7k=,tag:Ak9yBkYCWUOAH5suf+yAhQ==,type:str]
                    admin-password: ENC[AES256_GCM,data:oGwQ3JrQoqP+NIEeZVI/6fHb3i0=,iv:/WGvXG0LBXNwoP8/8eyKNI+obOnDpGJt0QZ5m577PRU=,tag:lipFbA/X720FgmodC204RA==,type:str]
        sops:
            age:
                - recipient: age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g
                  enc: |
                    -----BEGIN AGE ENCRYPTED FILE-----
                    YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBOdGdsMWNSemlyTFRtNTNE
                    ZUw1bGd0MEJ4dDlxS1prVmpkN3E0N2dBZ1ZBCnRDamlmT2JhSUp0WktYUkxGSWY5
                    dkxPanVvRU43THVNampUeUlwQldUWjQKLS0tIHRPUnpvQytOZGQzZGpHMldDK0Rp
                    dFZpV3RZbkZQcUtXU051ZjNpa0lTR2MKUhU7LqwAuv99A1xJGp6/aOtlZf0MpIRU
                    bA9endhStVa5/YO332flqYqeP6HP641LPHN3Xm+4PEzHFUqoB2kgjQ==
                    -----END AGE ENCRYPTED FILE-----
            lastmodified: "2025-12-28T12:36:50Z"
            mac: ENC[AES256_GCM,data:XH5yaKVWDiNTuH7Ox6/XoRkixRWwjK+Ubj5Yva69SeXhQiMzloBK8f9dXMufq40F3WrPSt3GZuFusk/3rWI6TqPUebzy7XwYQUBjRwpjaWmohPgpVikC9AFXAvpWqGU5Gixyq6yfhd664Fd1UqXrHYsCWNDKv9uMYlN++nuJx1Y=,iv:wiGRggc4A7L12qkp2n+CA5up7hn9GUsR6C4FTz9Zvsg=,tag:VNuNEMPB21n/4dTcw+B9lg==,type:str]
            encrypted_suffix: Templates
            version: 3.11.0
      ''
    ];

    resources.ingresses.grafana-ip-root = {
      metadata = {
        namespace = "observability";

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
          "cert-manager.io/cluster-issuer" = "letsencrypt-cloudflare";
          "glance/name" = "Grafana";
          "glance/icon" = "di:grafana";
          "glance/url" = "https://grafana.${domain}";
          "glance/description" = "Dashboards";
          "glance/id" = "grafana";
          "glance/parent" = "grafana";
          "category" = "monitoring";
        };
      };

      spec = {
        ingressClassName = "traefik";

        tls = [
          {
            secretName = "grafana-tls";
            hosts = ["grafana.${domain}"];
          }
        ];

        rules = [
          {
            host = "grafana.${domain}";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "grafana";
                  port.number = 80;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
