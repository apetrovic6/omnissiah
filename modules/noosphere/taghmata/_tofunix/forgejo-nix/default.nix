{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/tofunix-forgejo-nix-secret/tofunix-forgejo-nix-secret/value;
in {
  data.sops_file.forgejo_nix_secrets = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  provider.forgejo.cerberus = {
    base_uri = "https://forge.ugalabugala.org";
    api_token = "\${data.sops_file.forgejo_nix_secrets.data[\"forgejo_token\"]}";
  };

  
  # resource.forgejo_organization.monolith-softworks-cerberus = {
  #   provider = ref.forgejo.cerberus;
  #   name = "monolith-softworks";
  #   full_name = "Monolith Softworks";
  # };

  # resource.forgejo_repository.omnissiah = {
  #   provider = ref.forgejo.cerberus;
  #   name = "omnissiah";
  #   description = "Clan.lol flake for Nix powered homelab";
  #   private = false;
  #   default_branch = "master";
  #   has_pull_requests = true;
  #   has_actions = true;
  #   has_issues = true;
  # };

  # resource.forgejo_repository_push_mirror.omnissiah-github = {
  #   provider = ref.forgejo.cerberus;
  #   owner = "manjo";
  #   repository = "omnissiah";
  #   remote_address = "https://github.com/apetrovic6/omnissiah";
  #   sync_on_commit = true;
  #   use_ssh = true;
  # };

  # resource.forgejo_repository_push_mirror.omnissiah-codeberg = {
  #   provider = ref.forgejo.cerberus;
  #   owner = "manjo";
  #   repository = "omnissiah";
  #   remote_address = "https://codeberg.org/apetrovic/omnissiah";
  #   sync_on_commit = true;
  #   use_ssh = true;
  # };

  # resource.forgejo_repository.infra = {
  #   provider = ref.forgejo.cerberus;
  #   name = "infra";
  #   description = "Proxmox provisioning etc";
  #   private = false;
  #   default_branch = "master";
  #   has_pull_requests = true;
  #   has_actions = true;
  #   has_issues = true;
  # };

  # resource.forgejo_repository_push_mirror.infra-github = {
  #   provider = ref.forgejo.cerberus;
  #   owner = "manjo";
  #   repository = "infra";
  #   remote_address = "https://github.com/apetrovic6/infra";
  #   sync_on_commit = true;
  #   use_ssh = true;
  # };

  # resource.forgejo_repository_push_mirror.infra-codeberg = {
  #   provider = ref.forgejo.cerberus;
  #   owner = "manjo";
  #   repository = "infra";
  #   remote_address = "https://codeberg.org/apetrovic/infra";
  #   sync_on_commit = true;
  #   use_ssh = true;
  # };

}
