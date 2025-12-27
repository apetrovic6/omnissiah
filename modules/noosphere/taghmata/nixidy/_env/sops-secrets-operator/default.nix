{charts, ...}: {

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

}
