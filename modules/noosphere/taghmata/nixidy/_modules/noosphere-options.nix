{lib, ...}: {
  options.noosphere = rec {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Base domain used by nixidy modules.";
    };

    sso = {
      provider = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Name of the SSO Provider";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "${lib.toLower sso.provider}.${domain}";
        description = "Url of th SSO provider";
      };
    };
  };
}
