{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      garage-backup-rpc-secret = {
        namespace = "garage-operator";
        random.secret = "-hex 32";
        data.rpc-secret = "$secret";
      };

      garage-backup-admin-token = {
        namespace = "garage-operator";
        random.secret = "-hex 32";
        data.admin-token = "$secret";
      };
    };
  };
}
