# The GitHub token tofunix uses to create mirror repositories under github.com/apetrovic6 and
# to push to them (_tofunix/projects: forgejo push mirrors over HTTPS). A fine-grained token
# for the user's own repositories, with Administration: read/write (create repos) and
# Contents: read/write (push). Prompted once; stored sops-encrypted like the other tofunix
# secrets.
{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      tofunix-github-secret = {
        prompts.github-token.description = "GitHub fine-grained token for github.com/apetrovic6 (Administration + Contents: read/write)";
        data.github_token = "$github_token";
      };
    };
  };
}
