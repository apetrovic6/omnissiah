# {self, ...}: {
#   flake.nixosModules.service-base = {
#     config,
#     lib,
#     pkgs,
#     ...
#   }:
{
  _class = "clan.service";
  manifest.name = "base";
  manifest.readme = "";

  roles.default.description = "Some basic tools and settings that are needed everywhere";

  roles.default.perInstance.nixosModule = {
    self,
    lib,
    pkgs,
    ...
  }: {
    imports = [];

    environment.systemPackages = with pkgs; [
      btop
      pciutils
      vim
      self.inputs.nvf.packages.${pkgs.system}.default
      wget
      git
      fastfetch
      yazi
      killall
    ];

    fonts = {
      packages = with pkgs.nerd-fonts; [
        fira-code
        fira-mono

        jetbrains-mono
      ];
    };

    nix.gc.automatic = true;
    nix.settings.auto-optimise-store = true;

    programs.dconf = {
      enable = true;
    };

    services.xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    services.tailscale = {
      enable = true;
    };

    nixpkgs.config.allowUnfree = true;
  };

  #};
}
