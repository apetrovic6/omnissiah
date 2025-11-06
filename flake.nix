{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";

    nixpkgs.follows = "nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "clan-core/nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak?ref=latest";
    import-tree.url = "github:vic/import-tree";

    magos = {
      url = "path:/home/apetrovic/clan/magos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    hyprland.url = "github:hyprwm/Hyprland";

    # darwin = {
    #   url = "github:nix-darwin/nix-darwin";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    


  };

  outputs =
    inputs@{
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      imports = [
        inputs.clan-core.flakeModules.default
      ];

      # https://docs.clan.lol/guides/flake-parts
      clan = {
        imports = [ ./clan.nix ];
      };

      perSystem =
        { pkgs, inputs', ... }:
        {
          devShells.default = pkgs.mkShell { packages = [ inputs'.clan-core.packages.clan-cli ]; };
        };
    };
}
