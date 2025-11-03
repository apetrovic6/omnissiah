{...}:
{

  imports = [
    ./themes

  ];

nix.settings = {
  extra-substituters = ["https://walker.cachix.org" "https://walker-git.cachix.org"];
  extra-trusted-public-keys = ["walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM=" "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="];
};


programs.walker = {
  enable = true;
  runAsService = true; # Note: this option isn't supported in the NixOS module only in the home-manager module

  # All options from the config.toml can be used here https://github.com/abenz1267/walker/blob/master/resources/config.toml
  config = {
    theme = "ugala";
    placeholders."default" = { input = "Search"; list = "No Results"; };
    providers.prefixes = [
      {provider = "websearch"; prefix = "@";}
      {provider = "providerlist"; prefix = "_";}
      {provider = "clipboard"; prefix = ":";}
      {provider = "files"; prefix = "/";}
      {provider = "runner"; prefix = ">";}
      {provider = "windows"; prefix = "$";}
    ];
      #keybinds.quick_activate = ["F1" "F2" "F3"];
  };
};
}
