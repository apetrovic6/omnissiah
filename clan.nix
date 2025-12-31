{
  # Ensure this is unique among all clans you want to use.
  meta.name = "omnissiah";
  meta.domain = "omnissiah";

  imports = [
    ./inventory/machines.nix
  ];

  modules."@imperium/laptop" = import ./stc/laptop.nix;
  modules."@imperium/base" = import ./stc/base.nix;
  modules."@imperium/server" = import ./stc/server.nix;
  modules."@imperium/workstation" = import ./stc/workstation.nix;
  modules."@imperium/dev" = import ./stc/dev.nix;
  modules."@imperium/gaming" = import ./stc/gaming.nix;
  modules."@imperium/k8s-server" = import ./stc/k8s-server.nix;
  modules."@imperium/k8s-base" = import ./stc/k8s-base.nix;

  # Docs: See https://docs.clan.lol/reference/clanServices
  inventory.instances = {
    laptop = {
      module.input = "self";
      module.name = "@imperium/laptop";

      roles.default.tags.laptop = {};
    };

    base = {
      module.input = "self";
      module.name = "@imperium/base";

      roles.default.tags.base = {};
    };

    server = {
      module.input = "self";
      module.name = "@imperium/server";

      roles.default.tags.server = {};
    };

    workstation = {
      module.input = "self";
      module.name = "@imperium/workstation";

      roles.default.tags.workstation = {};
    };

    gaming = {
      module.input = "self";
      module.name = "@imperium/gaming";

      roles.default.tags.gaming = {};
    };

    k8s-server = {
      module.input = "self";
      module.name = "@imperium/k8s-server";

      roles.default.tags.k8s-server = {};
    };

    k8s-base = {
      module.input = "self";
      module.name = "@imperium/k8s-base";

      roles.default.tags.k8s-base = {};
    };

    dev = {
      module.input = "self";
      module.name = "@imperium/dev";

      roles.default.tags.dev = {};
    };

    # Docs: https://docs.clan.lol/reference/clanServices/admin/
    # Admin service for managing machines
    # This service adds a root password and SSH access.
    admin = {
      roles.default.tags.all = {};
      roles.default.settings.allowedKeys = {
        # Insert the public key that you want to use for SSH access.
        # All keys will have ssh access to all machines ("tags.all" means 'all machines').
        # Alternatively set 'users.users.root.openssh.authorizedKeys.keys' in each machine
        "admin" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg";
      };
    };

    apetrovic-user = {
      module.name = "users";
      roles.default.tags.workstation = {};
      roles.default.settings = {
        user = "apetrovic";
        prompt = true;
        share = true;
        groups = [
          "wheel" # Allow using 'sudo'
          "networkmanager" # Allows to manage network connections.
          "video" # Allows to access video devices.
          "input" # Allows to access input devices.
          "qemu"
          "libvirtd"
          "kvm"
          "adb"
          "docker"
        ];
      };

      roles.default.extraModules = [./users/apetrovic/home.nix];
    };

    # Docs: https://docs.clan.lol/reference/clanServices/zerotier/
    # The lines below will define a zerotier network and add all machines as 'peer' to it.
    # !!! Manual steps required:
    #   - Define a controller machine for the zerotier network.
    #   - Deploy the controller machine first to initialize the network.
    zerotier = {
      # Replace with the name (string) of your machine that you will use as zerotier-controller
      # See: https://docs.zerotier.com/controller/
      # Deploy this machine first to create the network secrets
      roles.controller.machines."__YOUR_CONTROLLER__" = {};
      # Peers of the network
      # tags.all means 'all machines' will joined
      roles.peer.tags.all = {};
    };

    # Docs: https://docs.clan.lol/reference/clanServices/tor/
    # Tor network provides secure, anonymous connections to your machines
    # All machines will be accessible via Tor as a fallback connection method
    tor = {
      roles.server.tags.nixos = {};
    };
  };

  # Additional NixOS configuration can be added here.
  # machines/jon/configuration.nix will be automatically imported.
  # See: https://docs.clan.lol/guides/more-machines/#automatic-registration
  machines = {
    enginseer = {
      config,
      pkgs,
      ...
    }: {
      environment.systemPackages = [pkgs.btop];

      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg" # elided
      ];
    };
  };
}
