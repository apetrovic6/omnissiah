{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      bytestash-jwt-secret = {
        namespace = "bytestash";
        random.secret = "-hex 32";
        data = {
          jwt-key = "$secret";
          expiry = "24h";
        };
      };
    };
  };
}
