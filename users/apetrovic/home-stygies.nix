{
  self,
  pkgs,
  lib,
  ...
}: {
  imports = [self.inputs.home-manager.nixosModules.default];

  nixpkgs.overlays = [self.overlays.helix self.overlays.herdr];
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "claude-code";

  home-manager = {
    extraSpecialArgs = {inherit self;};
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";

    users.apetrovic = {
      imports = [
        ./git.nix
        self.inputs.magos.homeModules.herdr
      ];

      home.stateVersion = "26.05";
      home.packages = [pkgs.helix pkgs.herdr];
      programs.claude-code.enable = true;
      programs.codex.enable = true;
      magos.herdr.claude.enable = true;
    };
  };
}
