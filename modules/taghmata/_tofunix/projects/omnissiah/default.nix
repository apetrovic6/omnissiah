# omnissiah, this repository, on forge.ugalabugala.org. It is not created here;
# only what its CI needs is managed.
#
# NTFY_TOKEN lets the Machines workflow announce the "render manifests" pull
# request (rituals/render-manifests-pr.sh) on ntfy. It is the publisher token
# of the `ntfy-access` clan var (taghmata/reliquary/ntfy): write-only on the
# homelab-alerts topic, the same credential Alertmanager publishes with. Read
# from the var, so rotating the var and applying again updates the secret and
# nothing is copied by hand.
{...}: let
  inherit (import ../../../../cartographa/_cartographa.nix) vars;
in {
  data.sops_file.ntfy_access = {
    source_file = "${vars.shared "ntfy-access" "alertmanager-ntfy"}";
    input_type = "yaml";
  };

  resource.forgejo_repository_actions_secret.omnissiah-ntfy-token = {
    provider = "forgejo.cerberus";
    owner = "manjo";
    repository = "omnissiah";
    name = "NTFY_TOKEN";
    # The var is a SopsSecret manifest; the token is in its one secret template.
    data = "\${yamldecode(data.sops_file.ntfy_access.raw).spec.secretTemplates[0].stringData.token}";
  };
}
