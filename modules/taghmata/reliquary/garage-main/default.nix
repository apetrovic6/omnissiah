{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      garage-main-rpc-secret = {
        namespace = "garage-operator";
        random.secret = "-hex 32";
        data.rpc-secret = "$secret";
      };

      garage-main-admin-token = {
        namespace = "garage-operator";
        random.secret = "-hex 32";
        data.admin-token = "$secret";
      };
    };
  };
}
