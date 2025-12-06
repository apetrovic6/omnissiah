{ config, lib, pkgs, ... }:

{
  ##########################################################################
  # Taghmata / RKE2 node token
  #
  # This uses Clan's `vars` framework to generate and store a secret
  # node token that is shared across all machines in the clan.
  #
  # Use it from NixOS as:
  #
  #   services.rke2.tokenFile =
  #     config.clan.core.vars.generators."taghmata-rke2-node-token"
  #       .files."node-token".path;
  #
  ##########################################################################

  clan.core.vars.generators."taghmata-rke2-node-token" = {
    # Share across machines (so all servers/agents see the same token)
    share = true;

    # We want a secret file called "node-token"
    files."node-token" = {
      secret = true;
      # owner/group/mode defaults are fine: root:root 0400
      # neededFor = "services" ensures it’s deployed before services start
      neededFor = "services";
    };

    # We need openssl to generate a random token
    runtimeInputs = [ pkgs.openssl ];

    # Script that writes the token into $out/node-token
    script = ''
      #!/usr/bin/env bash
      set -euo pipefail
      umask 077

      # Generate a 32-byte hex token
      openssl rand -hex 32 > "$out/node-token"
    '';
  };
}
