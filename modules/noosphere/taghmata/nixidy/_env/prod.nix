{charts, ...}: {
  imports = [
    ./apps/metrics-server
    ./apps/cloudnative-pg
    ./apps/longhorn
    ./apps/cloudnative-pg
    ./apps/metallb
    ./apps/sops-secrets-operator
  ];

  nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "master";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod/";

  nixidy.applicationImports = [
    ../_generated/cert-manager-crd.nix
    ../_generated/metallb-crd.nix
    ../_generated/sops-secrets-operator-crd.nix
    ../_generated/cloudnativepg-crd.nix
    ../_generated/longhorn-crd.nix
    ../_generated/traefik-crd.nix
  ];

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  applications.zitadel = let
    namespace = "zitadel";
  in {
    inherit namespace;
    createNamespace = true;

    yamls = [
      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: zitadel-ip-root
          namespace: zitadel
          annotations:
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
        spec:
          ingressClassName: traefik
          tls:
            - secretName: zitadel-tls
              hosts:
                - zitadel.noosphere.uk
          rules:
            - host: zitadel.noosphere.uk
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: zitadel-service
                        port:
                          number: 80
      ''
      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: zitadel-tls
          namespace: zitadel
        spec:
          secretName: zitadel-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - zitadel.noosphere.uk
      ''

      ''
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
            name: master-key-secret
            namespace: zitadel
        spec:
            secretTemplates:
                - name: ENC[AES256_GCM,data:ZpiqL8WCeGT+Dy2w+npIHe0=,iv:tBg1LeEfJQJ8l3BTSSdMa9q8hw0T4afRZaEB7gZSvZ0=,tag:VkihmWYHAjQJSkufOJXyeg==,type:str]
                  type: ENC[AES256_GCM,data:rU73iT4f,iv:Zbzqz1F5JIMi966GRqqutRJWnIvLa3Y8oE2G0AfbEqA=,tag:/9YCaab7KpjKk3qbrP/mYA==,type:str]
                  stringData:
                    masterkey: ENC[AES256_GCM,data:j6eh0+A/REicMbJ809O7Hj8iF/9OPEA54xdKHv/2U7g=,iv:fWjbCrQ7Fwbh4ujTUgqyZFJkoFYPfSmoXzL9tPg8zx8=,tag:galzx+oXvhnEkvrbCDBv+g==,type:str]
        sops:
            age:
                - recipient: age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g
                  enc: |
                    -----BEGIN AGE ENCRYPTED FILE-----
                    YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBiMTRRNHdITXVJb2Q4UjMx
                    MEt0YWpHMmEvNjZ3dEw1eUEwR21xZGlZNUJRCkk3TjNxMVg5TVhzZ3NQUGVrMElj
                    VVdlblhMa0VvbWdQalJKQUlJYmxtOHMKLS0tIFExeWdtTDBDbENRdkxPamx1eEpW
                    enZDbUVsTXBCbmFlQnl2Y2xLVmlzUU0KkkB8bszGIDtAXxTlQc/aFqZ3+HCxRaH7
                    26WN7HQ9uDtILt5R3CXnXRlwjBouA1kFyvQQNN/dpj6UfvqcY0aotQ==
                    -----END AGE ENCRYPTED FILE-----
            lastmodified: "2025-12-27T16:22:46Z"
            mac: ENC[AES256_GCM,data:QJ3zaGyhsu74CaaEADBFsPpdrS2RElwQ61y54pezCiGXzTcZIFqgwmlGuIC/wKkgzSoh89HFoTjQxYI9RuM4/eDzbp1N72ImbDjUdRB+3iwbHaItQU0Xz2u/JDBT0c7rC4N4ZAjQ2FNtEkafgLvr/cx73G+3+8FYK9rOz+jiens=,iv:U1q9siD+tmWe0c5D9jnFKwWM/hfik6oOukBSNaZGGwI=,tag:vGtgW+ybKnL0njJjZCp+Ow==,type:str]
            encrypted_suffix: Templates
            version: 3.11.0      ''
    ];

    helm.releases.zitadel = {
      chart = charts.zitadel.zitadel;
      includeCRDs = true;

      values = {
        env = [
          {
            name = "ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD";
            valueFrom.secretKeyRef = {
              name = "pg-zitadel-superuser";
              key = "password";
            };
          }
          {
            name = "ZITADEL_DATABASE_POSTGRES_USER_PASSWORD";
            valueFrom.secretKeyRef = {
              name = "pg-zitadel-app";
              key = "password";
            };
          }
        ];

        zitadel = {
          masterkeySecretName = "master-key-secret";
          configmapConfig = {
            ExternalDomain = "zitadel.noosphere.uk";
            ExternalSecure = true;
            TLS.enabled = false;
            Database.Postgres = {
              Host = "pg-zitadel-rw";
              Port = "5432";
              Database = "app";
              MaxOpenConns = 20;
              MaxIdleConns = 10;
              MaxConnLifetime = "30m";
              MaxConnIdleTime = "5m";
              User = {
                Username = "app";
                SSL.Mode = "disable";
              };
              Admin = {
                Username = "postgres";
                SSL.Mode = "disable";
              };
            };
            dbSslCaCrtSecret = "pg-zitadel-ca";
          };
        };

        replicaCount = 3;
        ingress = {
          enabled = true;
          className = "traefik";
        };

        login = {
          enabled = true;
          ingress = {
            enabled = true;
            className = "traefik";
          };
        };

        metrics = {
          enabled = true;
        };

        initJob.command = "";
      };
    };

    resources.clusters.pg-zitadel = {
      metadata = {
        inherit namespace;
      };

      spec = {
        imageName = "ghcr.io/cloudnative-pg/postgresql:17.7-minimal-trixie";

        # bootstrap.initdb = {
        #   database = "app";
        #   owner = "app";
        #   secret.name = "";
        # };

        enableSuperuserAccess = true;
        primaryUpdateStrategy = "unsupervised";
        instances = 2;
        storage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "10Gi";
        };

        walStorage = {
          storageClass = "longhorn-cnpg-strict-local";
          size = "10Gi";
        };

        postgresql.parameters = {
          shared_buffers = "1GB";
          max_connections = "200";
          log_statement = "ddl";
        };

        monitoring.enablePodMonitor = true;
      };
    };
  };

  # applications.seerr = {
  #   namespace = "yarr";
  #   createNamespace = true;

  #   helm.releases.seerr = {
  #     chart = lib.helm.downloadHelmChart {
  #       repo = "oci://ghcr.io/fallenbagel/jellyseerr";
  #       chart = "jellyseer-chart";
  #       version = "v2.7.3";
  #       chartHash = "";
  #     };

  #     # values = {};
  #   };
  # };

  applications.cert-manager = let
    namespace = "cert-manager";
  in {
    output.path = "./cert-manager";
    inherit namespace;
    createNamespace = true;

    #     resources.certificates.argocdTls = {
    # metadata = {
    #       name = "argocd-tls";
    #       namespace = "argocd";
    #     };

    #     spec = {
    #       secretName = "argocd-tls";

    #       issuerRef = {
    #         kind = "ClusterIssuer";
    #         name = "letsencrypt-cloudflare";
    #       };

    #       # dnsNames is on spec (not under issuerRef)
    #       dnsNames = [ "argocd.noosphere.uk" ];
    #     };
    #   };

    # resources = {
    # sopsSecrets.cloudflare-api-token = {
    #   metadata = {
    #     name = "cloudflare-api-token";
    #     namespace = "cert-manager";
    #   };

    #   spec = {
    #     secretTemplates = [
    #       {
    #         name = "ENC[AES256_GCM,data:QNLMLWOxyDA7fLchMeqjCw7mql2atvUKG6tx,iv:U3hu0qNeRHOKJZQ4hxuaH38ye8Z5ogiqQmeSHCfPDbA=,tag:oRlBjsdoxKT3lFU4B5TDaA==,type:str]";
    #         type = "ENC[AES256_GCM,data:XtL7Ac8k,iv:MIbUt0HNNSMYY1uuCiI64lt+4ch2MCEncnV0ND/UTm8=,tag:KYXyRMBcFgWKEMEhBFl5ZQ==,type:str]";
    #         stringData = {
    #           "api-token" = "ENC[AES256_GCM,data:YBR9UX/dZbzZrqBDo+73SW3f9gRW5o6aN2Mnhv7oRw8/lagHT3APaw==,iv:7zK7x5quGs0hSQXYO5EhX1BFczWdl49wiQ1/jNx8Kws=,tag:bsP7FCHfUI3IJHY6bq8aQg==,type:str]";
    #         };
    #       }
    #     ];
    #   };

    #   sops = {
    #     age = [
    #       {
    #         recipient = "age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g";
    #         enc = ''
    #           -----BEGIN AGE ENCRYPTED FILE-----
    #           YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSA4Y2p6WER3UnIreDlTWXpV
    #           RmJJd0xaZWRwQnFtWVkwRjU5WEJWMCtSRFVZCll3VVdIMU1oNVBaUU1xZHZFTXpm
    #           dEVNVFdEa1JpY0FLTHQ2YUVTcWtHc0EKLS0tIEhLUDllTTVGSmQ4TkcxclA5SVA5
    #           UkpGeFYyMzJPbE1jSnpxWVJVWk1HeGMKqsYm5L2C4pn2WVeojynw/obX3UWd1EvN
    #           mouJ5lASzpgT4SmZR3IIrQ+kH0zmWOqVECgT6UPmnOJJXHvpokFGEw==
    #           -----END AGE ENCRYPTED FILE-----
    #         '';
    #       }
    #     ];

    #     lastmodified = "2025-12-25T15:56:06Z";
    #     mac = "ENC[AES256_GCM,data:nuZdBChTwtMIrA62L/5lHm4T3ll3NaAeZ+wedUrwD6NCgXfAV47I6N70a7YspQZqAHA8DmWwzqYp4iTCq4yaKKALKeKETO7ENxUSld75yyCEIGNGZEjNh6Rkq73G0t+tpfxdMeMgL7/5I7TS/Dp7oWG8VR+IKj+4eo215imStDg=,iv:0MdqC71AkmW3a797hOZjRdl3NGgD8YwOUnLTHquwZOY=,tag:SogKhY87EiT5rBN1zpB+HA==,type:str]";
    #     encrypted_suffix = "Templates";
    #     version = "3.11.0";
    #   };
    # };
    # };

    yamls = [
      ''
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
            name: cloudflare-api-token
            namespace: cert-manager
        spec:
            secretTemplates:
                - name: ENC[AES256_GCM,data:QNLMLWOxyDA7fLchMeqjCw7mql2atvUKG6tx,iv:U3hu0qNeRHOKJZQ4hxuaH38ye8Z5ogiqQmeSHCfPDbA=,tag:oRlBjsdoxKT3lFU4B5TDaA==,type:str]
                  type: ENC[AES256_GCM,data:XtL7Ac8k,iv:MIbUt0HNNSMYY1uuCiI64lt+4ch2MCEncnV0ND/UTm8=,tag:KYXyRMBcFgWKEMEhBFl5ZQ==,type:str]
                  stringData:
                    api-token: ENC[AES256_GCM,data:YBR9UX/dZbzZrqBDo+73SW3f9gRW5o6aN2Mnhv7oRw8/lagHT3APaw==,iv:7zK7x5quGs0hSQXYO5EhX1BFczWdl49wiQ1/jNx8Kws=,tag:bsP7FCHfUI3IJHY6bq8aQg==,type:str]
        sops:
            age:
                - recipient: age1juzhlapy63msgtzzelusuqqq0hy24907eh0zd7xxzpkjtt5m053sv6a38g
                  enc: |
                    -----BEGIN AGE ENCRYPTED FILE-----
                    YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSA4Y2p6WER3UnIreDlTWXpV
                    RmJJd0xaZWRwQnFtWVkwRjU5WEJWMCtSRFVZCll3VVdIMU1oNVBaUU1xZHZFTXpm
                    dEVNVFdEa1JpY0FLTHQ2YUVTcWtHc0EKLS0tIEhLUDllTTVGSmQ4TkcxclA5SVA5
                    UkpGeFYyMzJPbE1jSnpxWVJVWk1HeGMKqsYm5L2C4pn2WVeojynw/obX3UWd1EvN
                    mouJ5lASzpgT4SmZR3IIrQ+kH0zmWOqVECgT6UPmnOJJXHvpokFGEw==
                    -----END AGE ENCRYPTED FILE-----
            lastmodified: "2025-12-25T15:56:06Z"
            mac: ENC[AES256_GCM,data:nuZdBChTwtMIrA62L/5lHm4T3ll3NaAeZ+wedUrwD6NCgXfAV47I6N70a7YspQZqAHA8DmWwzqYp4iTCq4yaKKALKeKETO7ENxUSld75yyCEIGNGZEjNh6Rkq73G0t+tpfxdMeMgL7/5I7TS/Dp7oWG8VR+IKj+4eo215imStDg=,iv:0MdqC71AkmW3a797hOZjRdl3NGgD8YwOUnLTHquwZOY=,tag:SogKhY87EiT5rBN1zpB+HA==,type:str]
            encrypted_suffix: Templates
            version: 3.11.0
      ''

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: argocd-tls
          namespace: argocd
        spec:
          secretName: argocd-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - argocd.noosphere.uk
      ''

      ''
        apiVersion: cert-manager.io/v1
        kind: Certificate
        metadata:
          name: longhorn-tls
          namespace: longhorn-system
        spec:
          secretName: longhorn-tls
          issuerRef:
            kind: ClusterIssuer
            name: letsencrypt-cloudflare
          dnsNames:
            - longhorn.noosphere.uk
      ''

      ''
        apiVersion: cert-manager.io/v1
        kind: ClusterIssuer
        metadata:
          name: letsencrypt-cloudflare
        spec:
          acme:
            email: cloudflare-cert-manager.paging338@simplelogin.com
            server: https://acme-v02.api.letsencrypt.org/directory
            privateKeySecretRef:
              name: letsencrypt-cloudflare-account-key
            solvers:
              - dns01:
                  cloudflare:
                    apiTokenSecretRef:
                      name: cloudflare-api-token-secret
                      key: api-token
      ''
    ];

    helm.releases.cert-manager = {
      chart = charts.jetstack.cert-manager;
      includeCRDs = true;
      values = {
        global.leaderElection.namespace = "cert-manager";
        crds.enabled = true;
      };
    };
  };

  applications.ingress-traefik-load-balancer-config = {
    namespace = "kube-system";
    output.path = "./traefik";

    # resources.helmChartConfigs = {};
    yamls = [
      ''
        apiVersion: helm.cattle.io/v1
        kind: HelmChartConfig
        metadata:
          name: rke2-traefik
          namespace: kube-system
        spec:
          valuesContent: |-
            service:
              type: LoadBalancer

            providers:
              kubernetesGateway:
                enabled: true
      ''

      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: argocd-ip-root
          namespace: argocd
          annotations:
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
        spec:
          ingressClassName: traefik
          tls:
            - secretName: argocd-tls
              hosts:
                - argocd.noosphere.uk
          rules:
            - host: argocd.noosphere.uk
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: argo-cd-argocd-server
                        port:
                          number: 80
      ''

      ''
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: longhorn-ip-root
          namespace: longhorn-system
          annotations:
            traefik.ingress.kubernetes.io/router.entrypoints: websecure
        spec:
          ingressClassName: traefik
          tls:
            - secretName: longhorn-tls
              hosts:
                - longhorn.noosphere.uk
          rules:
            - host: longhorn.noosphere.uk
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: longhorn-frontend
                        port:
                          number: 80
      ''
    ];
  };
}
