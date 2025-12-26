{charts,...}:
{
  nixidy.target.repository = "https://github.com/apetrovic6/omnissiah.git";

  # Set the target branch the rendered manifests for _this_
  # environment should be pushed to in the repository defined
  # above.
  nixidy.target.branch = "master";

  # Set the target sub-directory to copy the generated
  # manifests to when running `nixidy switch .#dev`.
  nixidy.target.rootPath = " ./modules/noosphere/taghmata/nixidy/manifests/prod";

  nixidy.defaults.syncPolicy.autoSync = {
    enable = true;
    prune = true;
    selfHeal = true;
  };

  applications.cert-manager = {
    output.path = "./cert-manager";
    namespace = "cert-manager";
    createNamespace = true;

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
      values = {
        global.leaderElection.namespace = "cert-manager";
        crds.enabled = true;
      };
    };
  };

  applications.sops-secrets = {
    output.path = "./sops-secrets-operator";
    namespace = "sops";
    createNamespace = true;

    helm.releases.sops-secrets-operator = {
      chart = charts.isindir.sops-secrets-operator;
      values = {
        secretsAsFiles = [
          {
            mountPath = "/etc/sops-age-key-file";
            name = "sops-age-key-file";
            secretName = "sops-age-key-file";
          }
        ];

        extraEnv = [
          {
            name = "SOPS_AGE_KEY_FILE";
            value = "/etc/sops-age-key-file/key";
          }
        ];
      };
    };
  };

  applications.ingress-traefik-load-balancer-config = {
    namespace = "kube-system";
    output.path = "./traefik";
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
    ];
  };

  applications.metallb = {
    output.path = "./metallb";
    namespace = "metallb-system";
    createNamespace = true;

    helm.releases.metallb = {
      chart = charts.metallb.metallb;
    };

    yamls = [
      /*
      yaml
      */
      ''
        apiVersion: metallb.io/v1beta1
        kind: IPAddressPool
        metadata:
          name: lan-pool
          namespace: metallb-system
          annotations:
            argocd.argoproj.io/sync-wave: "1"
        spec:
          addresses:
            - 192.168.1.240-192.168.1.250
      ''
      /*
      yaml
      */
      ''
        apiVersion: metallb.io/v1beta1
        kind: L2Advertisement
        metadata:
          name: lan-adv
          namespace: metallb-system
          annotations:
            argocd.argoproj.io/sync-wave: "1"
        spec:
          ipAddressPools:
            - lan-pool
      ''
    ];
  };
}
