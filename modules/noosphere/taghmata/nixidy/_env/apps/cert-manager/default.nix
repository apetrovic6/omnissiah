{
  config,
  charts,
  ...
}: let
  namespace = "cert-manager";
  domain = config.noosphere.domain;
in {
  applications.cert-manager = {
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
    #       dnsNames = [ "argocd.${domain}" ];
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
            - argocd.${domain}
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
            - longhorn.${domain}
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
}
