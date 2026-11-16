{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      pocket-id-encryption-key = {
        namespace = "pocket-id";
        random.secret = "-base64 32";
        data.encryption-key = "$secret";
      };
    };
  };
}
