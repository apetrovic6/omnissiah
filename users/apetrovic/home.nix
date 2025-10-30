{ self, config, pkgs, ... }:

{
  imports = [ self.inputs.home-manager.nixosModules.default ];

  home-manager.users.apetrovic = {
    imports = [
      ./home-configuration.nix
    ];
  };

}
