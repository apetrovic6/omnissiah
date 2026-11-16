{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      # A random password for the Harbor Woodpecker robot account.
      tofunix-harbor-woodpecker-secret = {
        setup = ''
          password="$(openssl rand -base64 32 | tr -d '\n' | head -c 32)"
        '';
        data.woodpecker_password = "$password";
        runtimeInputs = [pkgs.openssl];
      };
    };
  };
}
