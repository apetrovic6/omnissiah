{
  inputs = {
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-26.05";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    garage-operator = {
      url = "github:rajsinghtech/garage-operator";
      flake = false;
    };

    go-vikunja = {
      url = "github:go-vikunja/helm-chart";
      flake = false;
    };

    nix-jetbrains-plugins.url = "github:nix-community/nix-jetbrains-plugins";

    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
      # inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.follows = "nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "clan-core/nixpkgs";

    nix-flatpak.url = "github:gmodena/nix-flatpak?ref=latest";

    impermanence.url = "github:nix-community/impermanence";

    import-tree.url = "github:vic/import-tree";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    omnishell = {
      url = "github:apetrovic6/omnishell";
      # url = "path:/home/apetrovic/clan/omnishell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    magos = {
      url = "github:apetrovic6/magos";
      # url = "path:/home/apetrovic/clan/magos";
      inputs.nixpkgs.follows = "nixpkgs";
      # magos.nixosModules.nixarchy imports nixarchy's NixOS module, which
      # imports these three itself. Each must be the very store path this
      # flake already imports, or every option they declare is declared twice
      # and the machine stops evaluating. sops-nix follows clan-core's so clan
      # stays authoritative over secrets.
      inputs.nixarchy.inputs = {
        home-manager.follows = "home-manager";
        nix-flatpak.follows = "nix-flatpak";
        sops-nix.follows = "clan-core/sops-nix";
        microvm.follows = "microvm";
      };
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MicroVMs for isolated workloads (CI runners on ryza first). nixarchy
    # brings its own copy through magos; it follows this one below, so there
    # is a single pin.
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixhelm = {
      url = "github:nix-community/nixhelm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tofunix = {
      # url = "/home/apetrovic/clan/tofunix?dir=lib";
      url = "gitlab:TECHNOFAB/tofunix?dir=lib";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nixos-rocksmith = {
      url = "github:re1n0/nixos-rocksmith/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    steam-config-nix = {
      url = "github:different-name/steam-config-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # SoundCraft + the other 11 ArtCraft apps. Upstream (storytold) is
    # pre-alpha and cuts releases daily, and this tracks its default branch:
    # the Machines cron (.forgejo/workflows/machines.yml) bumps it along with
    # every other input every three days, so a bad day upstream shows up as a
    # red gaming build there rather than as a surprise at deploy time. Pin it
    # to a tag (`?ref=vX.Y.Z`) if a build breaks and you want a known-good set
    # until upstream recovers.
    nix-craftapps = {
      url = "github:olafkfreund/nix-craftapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
      inputs.brew-src.follows = "brew-src";
    };

    # brew itself, overriding nix-homebrew's pin. It must be at least as new
    # as the homebrew-core tap below: when core adopts new bottle DSL (e.g.
    # `manifest_sha256`, 2026-11-20, needs brew >= 7.0.15) an older brew
    # reports every formula as unreadable and `brew bundle` fails activation.
    # Bump this tag whenever homebrew-core is updated.
    brew-src = {
      url = "github:Homebrew/brew/7.0.15";
      flake = false;
    };

    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-quickemu = {
      url = "github:quickemu-project/homebrew-quickemu";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    glance-k8s = {
      url = "github:lukasdietrich/glance-k8s";
      flake = false;
    };

    rustfs = {
      url = "github:rustfs/rustfs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # MCP server giving coding agents real NixOS data -- packages, options,
    # home-manager, nix-darwin, nixvim, nixarchy -- from search.nixos.org and
    # the official docs, instead of inventing attribute names. A fork of
    # utensils/mcp-nixos.
    #
    # Stays here rather than moving to magos with the Omarchy desktop: this is
    # agent tooling, wired into programs.mcp.servers for both Claude Code and
    # pi, and has nothing to do with the session.
    #
    # A real flake, not `flake = false`: it carries its own fastmcp 4 stack
    # (nixpkgs still has 3.x, and its overlays.default would move fastmcp
    # set-wide and break other consumers of `mcp`). Taking
    # packages.<system>.mcp-nixarchy keeps that contained to this one package.
    mcp-nixarchy = {
      url = "github:olafkfreund/mcp-nixarchy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Strata, shared local inference (modules/rites/strata).
    # `flake = false`: its flake only carries a devShell, no package.
    # Pinned to a release tag, not main -- main moves through rc branches daily.
    # To update: bump the tag here, then `nix flake update strata`.
    strata = {
      url = "github:Niko1221/Strata/v0.2.17";
      flake = false;
    };

    pilot = {
      url = "git+https://forge.ugalabugala.org/manjo/pilot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    import-tree,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.clan-core.flakeModules.default
        inputs.treefmt-nix.flakeModule
        (import-tree ./modules)
        (import-tree ./overlays)
      ];

      noosphere = import ./modules/cartographa/_noosphere-values.nix;

      # https://docs.clan.lol/guides/flake-parts
      clan = {
        imports = [./clan.nix];
        pkgsForSystem = system:
          import inputs.nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              allowInsecurePredicate = pkg: inputs.nixpkgs.lib.getName pkg == "librewolf";
              permittedInsecurePackages = ["librewolf-151.0.2-1"];
              # PipeASIO (Rocksmith, via nixos-rocksmith overlay) builds against
              # Wine's MSVC cross-toolchain → xwin-fetch-msvc requires this.
              microsoftVisualStudioLicenseAccepted = true;
            };
            nix.settings.extra-experimental-features = ["pipe-operators"];
          };
      };
    };
}
