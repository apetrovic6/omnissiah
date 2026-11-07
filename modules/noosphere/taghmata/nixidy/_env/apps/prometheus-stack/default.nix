{
  config,
  charts,
  lib,
  ...
}: let
  namespace = "observability";
  domain = config.noosphere.domain;

  # ntfy lives on cerberus under the Caddy LAB_DOMAIN (ugalabugala.org), read
  # straight out of the caddy-env var (it carries a trailing newline: caddy.nix
  # writes it with echo, see machines/cerberus/memos.nix for the same trim).
  #
  # Not noosphere.uk: `dig ntfy.noosphere.uk` through Technitium answers the MetalLB
  # VIP 192.168.1.251, i.e. the request would hairpin through the cluster's own
  # Traefik looking for an Ingress that does not exist, and if the answer ever came
  # from the public side it would be the VPS. ugalabugala.org answers 192.168.1.105
  # from 192.168.1.105 (cerberus, Caddy -> ntfy) and 152.53.34.16 from a public
  # resolver, so the cluster side pins the zone in CoreDNS (see applications.coredns-
  # config in _env/prod.nix) instead of leaning on the nodes' resolv.conf.
  labDomain = lib.removeSuffix "\n" (builtins.readFile ../../../../../../../vars/shared/caddy-env/domain/value);
  ntfyUrl = "https://ntfy.${labDomain}/";
  ntfyTopic = "homelab-alerts";

  # Clan var outputs that exist only once the vars have been generated:
  #   vars/shared/ntfy-access/alertmanager-ntfy/value            (kube-secrets/ntfy)
  #   vars/shared/alertmanager-heartbeat/alertmanager-heartbeat/value (kube-secrets/alertmanager)
  # Read them when present, render without them when absent, so the flake evaluates
  # either way and an unconfigured receiver can never reference a file that is not
  # mounted (Alertmanager rejects the whole config file for one unreadable path,
  # which would take every alert down, not just the missing one).
  ntfySecretName = "alertmanager-ntfy";
  heartbeatSecretName = "alertmanager-heartbeat";
  ntfySecretYaml = ../../../../../../../vars/shared/ntfy-access/alertmanager-ntfy/value;
  heartbeatSecretYaml = ../../../../../../../vars/shared/alertmanager-heartbeat/alertmanager-heartbeat/value;
  ntfyReady = builtins.pathExists ntfySecretYaml;
  heartbeatReady = builtins.pathExists heartbeatSecretYaml;

  secretMount = name: "/etc/alertmanager/secrets/${name}";

  # Message body templates, evaluated by Alertmanager per alert group. ntfy takes
  # title/message as JSON strings in the body -- they are the only two values that go
  # through a template at all; priority and tags are static JSON values (see
  # ntfyReceiver, where the reason is recorded: Alertmanager's webhook http_config has
  # no headers field, and ntfy needs priority as a JSON number).
  #
  # The POST goes to the ntfy ROOT url, not to /<topic>: "To publish as JSON, you must
  # PUT/POST to the ntfy root URL, not to the topic URL", so the topic travels in the
  # body.
  #
  # WHY THE TITLE CANNOT CONTAIN A COLON (measured, not stylistic).
  #
  # Alertmanager infers each payload leaf's JSON type from the text its template
  # renders, and a leaf that reads as a YAML mapping -- `something: value` -- leaves as
  # a JSON OBJECT, not a string. ntfy requires title and message to be strings, and
  # answers 400 {"code":40024,"error":"invalid request: request body must be valid
  # JSON"} when they are not. The first version of this title used
  # `resolved: {{ .CommonLabels.alertname }}`; on 2026-11-06 16:16:47Z the live
  # Alertmanager logged exactly that for the resolved half of a test alert group whose
  # firing half had been accepted a few minutes earlier:
  #   level=ERROR source=dispatch.go msg="Notify for alerts failed"
  #   aggrGroup="{}/{severity=\"critical\"}:{}" num_alerts=2
  #   err="ntfy-critical/webhook[0]: ... unexpected status code 400:
  #        {\"code\":40024,...request body must be valid JSON}"
  # Isolated locally (real Alertmanager 0.33.1 -> a capturing HTTP server that JSON
  # -parses every body; four title templates, each fired and then resolved):
  #   "VariantColonPrefix"                 str   accepted   (firing text has no colon)
  #   {"resolved": "VariantColonPrefix"}   dict  REJECTED   (resolved text is a mapping)
  #   "VariantNoColon resolved"            str   accepted   (both states)
  #   "VariantDash - resolved"             str   accepted   (both states)
  #   {"note": "VariantColonMid"}          dict  REJECTED   (the colon only has to make
  #                                                        the whole leaf a mapping)
  # So the title renders `<alertname>` when firing and `<alertname> resolved` when it is
  # not: no colon, therefore a string in both states.
  #
  # The message leaf is safe for a different reason, visible in the same captures: its
  # first rendered line is always `<severity> - <alertname>` (no colon; and a colon in a
  # severity value would still need `: ` with a space to become a mapping), and the leaf
  # is multi-line, so the indented `garage cluster: ...` / `namespace: ...` lines are
  # plain content of a scalar rather than a top-level mapping -- which is how they came
  # through as strings in every capture above.
  ntfyTitle = lib.trim ''
    {{ .CommonLabels.alertname }}{{ if ne .Status "firing" }} resolved{{ end }}
  '';
  ntfyMessage = lib.trim ''
    {{- range .Alerts }}
    {{ .Labels.severity }} - {{ .Labels.alertname }}
    {{- if .Labels.garage_cluster }}
      garage cluster: {{ .Labels.garage_cluster }}
    {{- end }}
    {{- if .Labels.namespace }}
      namespace: {{ .Labels.namespace }}
    {{- end }}
    {{- if .Labels.pod }}
      pod: {{ .Labels.pod }}
    {{- end }}
    {{- if .Labels.node }}
      node: {{ .Labels.node }}
    {{- end }}
    {{- if .Annotations.summary }}
      {{ .Annotations.summary }}
    {{- end }}
    {{- if .Annotations.description }}
      {{ .Annotations.description }}
    {{- end }}
    {{- if .GeneratorURL }}
      {{ .GeneratorURL }}
    {{- end }}
    {{- end }}
  '';

  # ntfy receiver: one per severity.
  #
  # Priority and tags ride in the JSON body, NOT in HTTP headers: Alertmanager's
  # webhook http_config has no `headers` field at all, and its config parser rejects
  # it outright -- `amtool check-config` on the rendered Secret failed with
  # "field headers not found in type config.plain", which Alertmanager would have hit
  # at startup too, i.e. a crash-looping Alertmanager and no alerts at all.
  #
  # Verified against a real Alertmanager 0.33.1 delivering to a real ntfy 2.34.0
  # locally: a payload that carries `priority: 4` and `tags: [rotating_light]` as
  # plain (non-template) YAML values arrives at ntfy as a JSON *number* and a JSON
  # array -- priority=4 tags=["rotating_light"], raw types number/array -- which is
  # the shape ntfy requires. Template leaves were deliberately kept to the two
  # strings (title, message) so the number never passes through a template at all.
  ntfyReceiver = name: priority: tags: {
    inherit name;
    webhook_configs = [
      {
        url = ntfyUrl;
        send_resolved = true;
        # ntfy's message-size-limit defaults to 4k; a group of eight alerts with
        # summary+description is already close to it, and the point of a phone
        # notification is the first line, not the whole group.
        max_alerts = 8;
        http_config = {
          # The only credential handling this needs: the write token from the
          # SopsSecret the operator mounts (see alertmanagerSpec.secrets below).
          authorization = {
            type = "Bearer";
            credentials_file = "${secretMount ntfySecretName}/token";
          };
        };
        payload = {
          # Publishing as JSON must POST to the ntfy root URL, not to /<topic>, so
          # the topic is part of the body.
          topic = ntfyTopic;
          title = ntfyTitle;
          message = ntfyMessage;
          # Static values on purpose (see the note above): ntfy wants priority as a
          # number, 1=min .. 5=max, 3=default.
          inherit priority;
          inherit tags;
        };
      }
    ];
  };
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

        # --- Alertmanager: routes, receivers, storage ---------------------------
        #
        # This file used to configure `alertManager` (capital M). The chart's values
        # key is `alertmanager`, so that block never reached the chart: fullNameOverride
        # and ingress.enabled were inert, and Alertmanager has been running the chart's
        # default config -- one `null` receiver, i.e. every alert, the Garage ones
        # included, went nowhere. The block is now spelled correctly.
        #
        # fullNameOverride is deliberately NOT re-applied: making it take effect would
        # rename the StatefulSet (prometheus-alertmanager -> alertmanager-alertmanager),
        # orphan the running one and its state for no gain. ingress.enabled stays at the
        # chart default (false).
        alertmanager = {
          enabled = true;

          # Helm merges these maps into the chart default, so global/inhibit_rules/
          # templates stay as they are; `routes` and `receivers` are lists and are
          # replaced whole, which is why the null receiver is re-declared below.
          config = {
            route.routes =
              lib.optionals heartbeatReady [
                {
                  # Watchdog is expr: vector(1) with severity: none -- it fires on
                  # every evaluation, and it is the only alert whose *absence* is the
                  # signal. Silence here means Prometheus, Alertmanager, the cluster,
                  # the network or the lab's power are down together, and this route is
                  # the one thing that notices, because the check lives outside the
                  # pipeline it is watching.
                  #
                  # The healthchecks.io check expects a ping every 1m and alerts
                  # after 5m of grace, so Alertmanager re-sends Watchdog every
                  # minute: a notification goes out when both group_interval and
                  # repeat_interval have elapsed, hence both at 1m. Five missed
                  # pings before anyone is told.
                  #
                  # No send_resolved here: that is a receiver field (set below),
                  # and an unknown field in a route makes Alertmanager reject the
                  # whole config.
                  receiver = "heartbeat";
                  matchers = [''alertname = "Watchdog"''];
                  group_by = ["alertname"];
                  group_wait = "0s";
                  group_interval = "1m";
                  repeat_interval = "1m";
                }
              ]
              ++ lib.optionals ntfyReady [
                {
                  receiver = "ntfy-critical";
                  matchers = [''severity = "critical"''];
                  group_wait = "10s";
                  repeat_interval = "3h";
                }
                {
                  # Warnings are the noisy half -- 97 of the rules loaded in this
                  # cluster are severity=warning, and paging a phone for
                  # KubeletPlegDurationHigh or TargetDown on a homelab is how people
                  # start ignoring the phone. Garage is the thing this whole branch was
                  # built to watch, and its rules are the only ones whose alerts carry
                  # a garage_cluster label (stamped by the ServiceMonitor relabel, then
                  # kept by every rule's `by (garage_cluster)` / `and` expression).
                  # So that label is the discriminator: Garage warnings page, everything
                  # else falls out of `routes` to the parent receiver, which is "null".
                  receiver = "ntfy-warning";
                  matchers = [
                    ''severity = "warning"''
                    ''garage_cluster != ""''
                  ];
                  group_wait = "30s";
                  repeat_interval = "12h";
                }
              ];

            receivers =
              [ {name = "null";} ]
              ++ lib.optionals heartbeatReady [
                {
                  name = "heartbeat";
                  webhook_configs = [
                    {
                      # The ping URL is a credential: anyone holding it can mark the
                      # check healthy. It lives in the var-rendered Secret the operator
                      # mounts, and Alertmanager reads the URL from the file.
                      url_file = "${secretMount heartbeatSecretName}/url";
                      send_resolved = false;
                      max_alerts = 1;
                    }
                  ];
                }
              ]
              ++ lib.optionals ntfyReady [
                (ntfyReceiver "ntfy-critical" 4 [ "rotating_light" ])
                (ntfyReceiver "ntfy-warning" 3 [ "warning" ])
              ];
          };

          alertmanagerSpec = {
            # Silences, inhibition state and the Alertmanager WAL live in the pod's
            # emptyDir today: restart the pod and every silence you set to keep a
            # known-bad node quiet disappears, along with the inhibition state, and
            # the group timers reset -- which is how a re-notified alert after a
            # restart looks identical to a new one. 2Gi is oversized for what
            # Alertmanager actually keeps (silences + a small bucket WAL); it is the
            # smallest size that leaves room for a burst of alert groups, and at
            # Longhorn's 2 replicas that is 4Gi of the ~590Gi schedulable pool.
            # Same storage class as Prometheus above, for the same reason: replicas=1
            # with a *preferred* anti-affinity, so the pod can move nodes and the
            # volume has to follow it.
            #
            # Adding volumeClaimTemplates is an immutable change: the operator has to
            # recreate the StatefulSet, so this change costs one Alertmanager restart,
            # and the state in the emptyDir is lost exactly once, on the way onto the
            # volume. From here on it survives restarts.
            storage.volumeClaimTemplate.spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = "longhorn";
              resources.requests.storage = "2Gi";
            };

            persistentVolumeClaimRetentionPolicy = {
              whenDeleted = "Retain";
              whenScaled = "Retain";
            };

            # The operator mounts each of these into the alertmanager container at
            # /etc/alertmanager/secrets/<name>/, which is where url_file and
            # credentials_file above point. Declaring a secret that does not exist
            # would leave the pod unschedulable, hence the guards.
            secrets =
              lib.optionals ntfyReady [ntfySecretName]
              ++ lib.optionals heartbeatReady [heartbeatSecretName];
          };
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
    ]
    # Cluster-side credentials for the Alertmanager receivers, generated by
    # kube-secrets/ntfy and kube-secrets/alertmanager and read straight out of the var
    # store, exactly like garage-operator reads its rpc/admin SopsSecrets. They are
    # sops-encrypted manifests: the plaintext token and ping URL never appear in a
    # rendered manifest, only in the Secret the sops-secrets-operator produces from
    # them in observability.
    #
    # Guarded because they do not exist until the vars are generated
    #   clan vars generate cerberus --generator ntfy-access
    #   clan vars generate cerberus --generator alertmanager-heartbeat
    # and the flake must evaluate before then (see the let block).
    ++ lib.optionals ntfyReady [(builtins.readFile ntfySecretYaml)]
    ++ lib.optionals heartbeatReady [(builtins.readFile heartbeatSecretYaml)];

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
