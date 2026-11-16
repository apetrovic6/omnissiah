# The pilot's session-cookie key (template ADR 0029): 32 random bytes, base64, which is what
# the service's `auth.cookie_key` expects. Generated, never typed; rotating it signs everyone
# out. The cerberus deployment has its own key (machines/cerberus/pilot.nix).
{self, ...}: {
  flake.nixosModules.reliquary = {pkgs, ...}: {
    clan.core.vars.generators = self.lib.mkSopsGenerators pkgs {
      # Named for the cluster: cerberus's own generator is `pilot-cookie-key`.
      pilot-k8s-cookie-key = {
        namespace = "pilot";
        secretName = "pilot-cookie-key";
        random.key = "-base64 32";
        data.cookie-key = "$key";
      };
    };
  };
}
