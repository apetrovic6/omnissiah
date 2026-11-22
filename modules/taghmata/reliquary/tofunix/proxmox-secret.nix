{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-proxmox-secret = {
        prompts.api-token = {
          description = "Secret (UUID) of the tofu@pam!tofunix API token on 192.168.1.11";
          type = "line";
        };
        data.api_token = "$api_token";
      };
    };
  };
}
