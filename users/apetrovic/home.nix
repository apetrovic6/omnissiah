{ self, ... }:

{
  imports = [ 
    self.inputs.home-manager.nixosModules.default
    # self.inputs.stylix.homeModules.stylix
  ];

  # home-manager.sharedModules = [
  #   self.inputs.stylix.homeModules.stylix
  # ];

  home-manager.users.apetrovic = {
    imports = [
      ./home-configuration.nix
    ];
  };

}
