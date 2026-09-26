{
  self,
  pkgs,
  ...
}: {
  imports = [
    self.inputs.home-manager.nixosModules.default
  ];

  home-manager.extraSpecialArgs = {inherit self;};

  home-manager.backupFileExtension = "bak";
  home-manager.sharedModules = [
    # steam-config-nix HM module defines programs.steam.config in the HM
    # module system, which the nixos-rocksmith HM module needs to set
    # declarative Steam launch options for Rocksmith 2014.
    self.inputs.steam-config-nix.homeModules.default
  ];

  home-manager.users.apetrovic = {
    imports = [
      (
        if pkgs.stdenv.isDarwin
        then ./home-darwin.nix
        else ./home-configuration.nix
      )
    ];
  };
}
