{config, ...}: 
let 
  c = config.lib.stylix.colors;
in 
{
     background-default =  "#${c.base00}";
     background-alpha-50 = "alpha(#${c.base01}, 0.5)";
     background = "#${c.base01}";
     foreground = "#${c.base05}";

     text-default = "#${c.base05}";
     text-alternate =  "#${c.base04}";
     text-popup = "#${c.base0A}";

     border  = "#${c.base0D}";}
