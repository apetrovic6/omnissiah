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
    placeholders = {
        "default" = { input = "Search"; list = "No Results"; };
        "files" = { input = "Browse Files"; list = "No Files Found"; };
        "calc" = { input = "Calculate"; list = "Enter Expression"; };
        "runner" = { input = "Run Command"; list = "No Commands"; };
        "websearch" = { input = "Search Web"; list = ""; };
        "clipboard" = { input = "Clipboard"; list = "Clipboard Empty"; };
        "symbols" = { input = "Symbol"; list = "No Symbols"; };
        "todo" = { input = "Todo"; list = "No Todos"; };
      };

    providers.prefixes = [
      {provider = "websearch"; prefix = "@";}
      {provider = "providerlist"; prefix = ";";}
      {provider = "clipboard"; prefix = ":";}
      {provider = "files"; prefix = "/";}
      {provider = "runner"; prefix = ">";}
      {provider = "windows"; prefix = "$";}
      {provider = "symbols"; prefix = ".";}
      {provider = "todo"; prefix = "!";}
    ];

      # providers.actions = [];

     keybinds.quick_activate = [];
  };
};
}
