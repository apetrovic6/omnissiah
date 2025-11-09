{
  self,
  pkgs,
  ...
}: {
  imports = [
    self.inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.backupFileExtension = "bak";
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.apetrovic = {
    imports = [
      ./home-configuration-darwin.nix
    ];
  };
}
