{self, ...}: {
  flake.nixosModules.domains = {lib, ...}: {
    options.domains = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Central domain registry. Set domain names here and reference them as config.domains.<name> elsewhere.";
    };
  };
}
