{ self, ... }:

{
  imports = [ 
    self.inputs.home-manager.nixosModules.default
  ];

    home-manager.extraSpecialArgs = {inherit self;};

  home-manager.backupFileExtension = "bak";
   home-manager.sharedModules = [];

  home-manager.users.apetrovic = {
    imports = [
      ./home-configuration.nix
    ];
  };

}
