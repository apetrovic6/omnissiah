{config, ...}: let
in {
  flake.nixosModules.pharos = {pkgs, ...}: {
    clan.core.vars.generators.pangolin = {
      files."pangolin.env" = {
        secret = true;
        mode = "0400";
      };

      runtimeInputs = [pkgs.openssl];

      script = ''
        set -euo pipefail
        secret="$(openssl rand -base64 32)"

        
        cat  > "$out/pangolin.env" <<EOF
        SERVER_SECRET=$secret
        EOF
      ''

    };
  };
}
