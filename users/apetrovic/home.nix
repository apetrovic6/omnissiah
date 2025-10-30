{ self, config, pkgs, ... }:

{
  imports = [ self.inputs.home-manager.nixosModules.default ];

  home-manager.users.jon = {
    imports = [
      ./home-configuration.nix
    ];
  };

}
