# The Codeberg token the forge pushes mirrors with (_tofunix/conduits.nix:
# `scriptorium.remotes.codeberg`), so a mirror needs no per-repository SSH key.
# An access token for codeberg.org/apetrovic with the `write:repository` scope.
# The repositories themselves are created on Codeberg by hand. Prompted once;
# stored sops-encrypted like the other tofunix secrets.
{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-codeberg-secret = {
        prompts.codeberg-token.description = "Codeberg access token for codeberg.org/apetrovic (scope write:repository)";
        data.codeberg_token = "$codeberg_token";
      };
    };
  };
}
