# GitHub, for mirror repositories under github.com/apetrovic6. The token comes from the
# `tofunix-github-secret` clan var (taghmata/tofunix-github-secret.nix); generate it before the
# first apply: `clan vars generate <any machine> --generator tofunix-github-secret`.
{...}: let
  tokenFile = ../../../../../vars/shared/tofunix-github-secret/tofunix-github-secret/value;
  # Until the var is generated, GitHub is simply left out: every other resource still plans.
  hasToken = builtins.pathExists tokenFile;
in
  if !hasToken
  then {}
  else {
    data.sops_file.github_secrets = {
      source_file = "${tokenFile}";
      input_type = "yaml";
    };

    provider.github.default = {
      owner = "apetrovic6";
      token = "\${data.sops_file.github_secrets.data[\"github_token\"]}";
    };
  }
