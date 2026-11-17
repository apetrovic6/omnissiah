{self, ...}: {
  nixidy.envs.prod.apps.sops-secrets-operator = {charts, ...}: {
    applications.sops-secrets = {
      output.path = "./sops-secrets-operator";
      namespace = "sops";
      createNamespace = true;

      helm.releases.sops-secrets-operator = {
        chart = charts.isindir.sops-secrets-operator;
        extraOpts = ["--kube-version" "1.35.0"];
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
  };

  perSystem = {system, ...}: {
    nixidy.crds.definitions.sops-secrets-operator.chart = self.inputs.nixhelm.chartsDerivations.${system}.isindir.sops-secrets-operator;
  };
}
