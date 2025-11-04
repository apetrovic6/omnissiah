{ lib, config, ... }:
let
  c = config.lib.stylix.colors;
in
{
  options.hyperium.palette = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = {
      backgroundDefault = "#${c.base00}";
      backgroundAlpha50 = "alpha(#${c.base01}, 0.5)";
      background        = "#${c.base01}";
      foreground        = "#${c.base05}";

      textDefault    = "#${c.base05}";
      textAlternate  = "#${c.base04}";
      textPopup      = "#${c.base0A}";

      border = "#${c.base0D}";

      warning = "#${c.base0A}";
      urgent = "#${c.base09}";
      error = "#${c.base08}";
    };
    description = "Hyperium DE palette derived from Stylix.";
  };
}

