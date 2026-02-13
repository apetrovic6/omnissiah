{ref, ...}:
let
  secretsFile = toString ../../../../../vars/shared/tofunix-pocketid-secret/tofunix-pocketid-secret/value;
  noosphere = import ../../../../vars/_noosphere-values.nix;
  inherit (noosphere) domain;
in
{
  data.sops_file.pocket_api_key = {
    source_file = secretsFile;
    input_type = "yaml";
  };
  
  provider.pocketid = {
    base_url = "https://id.${domain}";
    api_token = "\${data.sops_file.api_key.data[\"api_key\"]}";
  };


  resource.pocketid_group.admin = {
    name = "admins";
    friendly_name = "Administrators";
  };
  

  # resource.pocketid_client.vikunja = {
  #   name = "Vikunja";
  #   callback_urls = [
  #     "https://vikunja.${domain}/auth/openid/pocketid"
  #   ];
  # };

  # output.client_id = {
  #   value = ref.pocketid_client.vikunja.id;
  # };

  # output.client_secret = {
  #   value = ref.pocketid_client.vikunja.client_secret;
  #   sensitive = true;
  # };
}
