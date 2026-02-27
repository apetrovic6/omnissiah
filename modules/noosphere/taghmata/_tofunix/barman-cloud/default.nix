{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/barman-s3-credentials/barman-s3-credentials/value;

  namespaces = [
    "yarr"
    "harbor"
    "keycloak"
    "woodpecker"
    "forgejo"
    "vikunja"
    "pocket-id"
  ];

  mkSecret = ns: {
    "barman-s3-${ns}" = {
      metadata = {
        name = "barman-s3-secret-key";
        namespace = ns;
        labels = {
          "cnpg.io/reload" = "true";
        };
      };

      data = {
        ACCESS_KEY_ID = "\${data.sops_file.barman_s3.data[\"access_key_id\"]}";
        ACCESS_SECRET_KEY = "\${data.sops_file.barman_s3.data[\"access_secret_key\"]}";
      };
    };
  };
in {
  data.sops_file.barman_s3 = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  resource.kubernetes_secret_v1 =
    builtins.foldl' (acc: ns: acc // mkSecret ns) {} namespaces;
}
