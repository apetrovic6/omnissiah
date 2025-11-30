{self, ...}: {
  flake.nixosModules.vars = {
    config,
    lib,
    pkgs,
    ...
  }: {
    clan.core.vars.generators.domain= {
      share = true;
prompts.base = {
      description = "Base domain for services (e.g. example.com)";
      type = "line";
      persist = true;
      display.label = "Base domain";
    };

    files.baseDomain = {
      secret = false;  # important: allows using `.value` in Nix
    };

    script = ''
      set -eu
      cp "$prompts/base" "$out/baseDomain"
    '';
    
  };
}
