{lib, ...}: {
  options.noosphere.domain = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Base domain used by nixidy modules.";
  };
}
