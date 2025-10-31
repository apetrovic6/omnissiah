{ self, ... }:

{
  imports = [ 
    self.inputs.home-manager.nixosModules.default
    # self.inputs.stylix.homeModules.stylix
  ];

  home-manager.extraSpecialArgs = {inherit self;};

   home-manager.sharedModules = [
   ];

  home-manager.users.apetrovic = {
    imports = [
      ./home-configuration.nix
    ];
  };

}
