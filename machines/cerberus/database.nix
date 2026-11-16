# PostgreSQL for the services on this machine, backed up to the NAS nightly.
{
  self,
  pkgs,
  ...
}: {
  imports = [self.nixosModules.postgresql];

  services.imperium.postgresql = {
    enable = true;
    listenAddresses = "*";
    openFirewall = true;
    package = pkgs.postgresql_18;

    extensions = {
      vector = ps: ps.pgvector;
      vchord = ps: ps.vectorchord;
    };

    authentication = ''
      # TYPE  DATABASE  USER      ADDRESS         METHOD
      local   all       all                       peer
      host    all       all       127.0.0.1/32    scram-sha-256
      host    all       all       ::1/128         scram-sha-256
      host    all       all       ${self.lib.lan.cidr}  scram-sha-256
    '';

    backup = {
      enable = true;
      location = "/mnt/nas/postgres_backup/manjo";
      startAt = "*-*-* 01:15:00";
    };

    users.vaultwarden = {
      databases = ["vaultwarden"];
      ensureDBOwnership = true;
    };

    users.forgejo = {
      databases = ["forgejo"];
      ensureDBOwnership = true;
    };

    users.hass = {
      databases = ["hass"];
      ensureDBOwnership = true;
    };

    users.immich = {
      databases = ["immich"];
      ensureDBOwnership = true;
      extensions = ["unaccent" "uuid-ossp" "cube" "earthdistance" "pg_trgm" "vector" "vchord"];
    };
  };
}
