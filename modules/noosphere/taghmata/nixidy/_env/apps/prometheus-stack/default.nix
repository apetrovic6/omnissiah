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

    helm.releases.kube-prometheus-stack = let
      endpoints = ["192.168.1.48" "192.168.1.59"];
    in {
      chart = charts.prometheus-community.kube-prometheus-stack;
      includeCRDs = false;

      values = {
        crds.enabled = true;
        fullnameOverride = "prometheus";

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

        kubeControllerManager = {
          enabled = true;
          inherit endpoints;
        };

        coredDns.enabled = true;

        kubeEtcd = {
          enabled = true;
          inherit endpoints;
          service = {
            enabled = true;
            port = 2381;
            targetPort = 2381;
          };
        };

        kubeScheduler = {
          enabled = true;
          inherit endpoints;
        };

        kubeProxy = {
          enabled = true;
          inherit endpoints;
        };

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

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: grafana-tls
          namespace: observability
        spec:
          secretName: grafana-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - grafana.${domain}
      ''
    ];

    resources.ingresses.grafana-ip-root = {
      metadata = {
        namespace = "observability";

        annotations = {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure";
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
