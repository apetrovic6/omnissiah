# Forgejo, with its repositories on the NAS.
{
  self,
  config,
  pkgs,
  ...
}: let
  baseDomain = config.clan.core.vars.generators."caddy-env".files."domain".value;
in {
  users.users.forgejo.extraGroups = ["git"];

  users.groups.git = {
    gid = 65540;
  };

  # Keep external targets and allow delivery to the Hermes webhook on ryza:8644.
  services.forgejo.settings.webhook.ALLOWED_HOST_LIST = "external,${self.lib.hosts.ryza}";

  services.imperium.forgejo = {
    enable = true;
    package = pkgs.forgejo;

    user = "forgejo";
    group = "git";

    stateDir = "/mnt/nas/git";

    port = 9000;
    host = "127.0.0.1";
    subdomain = "forge";
    domain = baseDomain;

    sshPort = 2222;
    startSshServer = true;

    database = {
      host = "127.0.0.1";
      name = "forgejo";
      user = "forgejo";
    };

    sso = {
      enable = false;
      providerName = "Pocket ID";
      autoDiscoverUrl = "https://id.noosphere.uk/.well-known/openid-configuration";
    };
  };
}
