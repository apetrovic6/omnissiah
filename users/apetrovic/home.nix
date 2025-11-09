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
  home-manager.sharedModules = [];

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
