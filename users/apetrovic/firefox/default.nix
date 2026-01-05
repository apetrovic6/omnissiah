{lib, ...}: let
  extension = shortId: uuid: {
    name = uuid;
    value = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/${shortId}/latest.xpi";
      installation_mode = "force_installed";
    };
  };

  extensions = (
    lib.listToAttrs [
      (extension "bitwarden-password-manager" "{446900e4-71c2-419f-a6a7-df9c091e268b}")
      (extension "firefox-color" "FirefoxColor@mozilla.com")
      (extension "karakeep" "addon@karakeep.app")
      (extension "vimium" "{d7742d87-e61d-4b78-b8a1-b469842139fa}")
      (extension "sponsorblock" "sponsorBlocker@ajay.app")

      (extension "ublock-origin" "uBlock0@raymondhill.net")
      (extension "cookie-autodelete" "CookieAutoDelete@kennydo.com")

      (extension "darkreader" "addon@darkreader.org")
    ]
  );
in {
  programs.firefox.enable = true;
  programs.firefox.profiles.apetrovic.extensions.force = true;
  programs.firefox.policies.ExtensionSettings = extensions;

  programs.librewolf = {
    enable = true;

    policies = {
      AppAutoupdate = true;
      BackgroundAppUpdate = false;

      ExtensionUpdate = true;
      ExtensionSettings =
        extensions
        // {
          # Disable built-in search engines
          "amazondotcom@search.mozilla.org" = {
            installation_mode = "blocked";
          };
          "bing@search.mozilla.org" = {
            installation_mode = "blocked";
          };
          "ebay@search.mozilla.org" = {
            installation_mode = "blocked";
          };
          #  "*" = {
          #  installation_mode = "blocked";
          #  blocked_install_message = "Install your extensions with Nix";
        };
    };

    profiles.apetrovic = {
      isDefault = true;
      id = 0;

      containersForce = true;
      containers = {
        google = {
          id = 1;
          color = "turquoise";
        };
        meta = {
          id = 2;
          color = "blue";
        };
        work = {
          id = 3;
          color = "yellow";
        };
        banking = {
          id = 4;
          color = "green";
        };
        shopping = {
          id = 5;
          color = "red";
        };
        private = {
          id = 6;
          color = "orange";
        };
      };

      # If you set extensions.settings here or in sub-attrs,
      # and Home Manager warns it "overrides previous settings",
      # add:
      extensions = {
        force = true;
      };
    };
  };
}
