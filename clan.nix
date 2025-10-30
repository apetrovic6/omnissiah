{
  # Ensure this is unique among all clans you want to use.
  meta.name = "omnissiah";
  meta.tld = "omnissiah";

  modules."@imperium/machine-type" = {...}: {
    _class = "clan.service";
    manifest.name = "machine-type";

    roles.laptop.perInstance.nixosModule = {lib, pkgs, ...} :{
    
      networking.networkmanager.enable = true;


       environment.systemPackages = [ pkgs.bitwarden-desktop ];

      # Safe, vendor-neutral power management (works well with GNOME and others)
      services.power-profiles-daemon.enable = true;

      # Battery/energy info for desktop environments and tools
      services.upower.enable = true;

      # Helps on Intel CPUs; mkDefault so you can override per-machine if needed
      services.thermald.enable = lib.mkDefault true;

      # Sensible behavior on lid close
      services.logind = {
        lidSwitch = "suspend";
        lidSwitchExternalPower = "suspend";
        lidSwitchDocked = "ignore";
      };


      # Optional quality-of-life bits (commented for now)
       powerManagement.powertop.enable = true; # run powertop --auto-tune at boot
       services.fwupd.enable = true;           # firmware updates (UEFI, Thunderbolt, etc.)

# Sleep behavior: suspend quickly, then hibernate later to save battery
    systemd.sleep.extraConfig = ''
      SuspendState=suspend
      HibernateMode=shutdown
      HibernateDelaySec=1h
      SuspendEstimationSec=0
    '';
    # Use suspend-then-hibernate on lid close / idle (matches logind defaults above)
    systemd.targets."sleep".wantedBy = [ "suspend-then-hibernate.target" ];
    systemd.services."systemd-suspend-then-hibernate".enable = true;
    };
    };
 

  inventory.machines = {
    # Define machines here.
    enginseer = {
      tags = [ "laptop" ];
      deploy.targetHost = "root@192.168.1.50";
    };
  };



  # Docs: See https://docs.clan.lol/reference/clanServices
  inventory.instances = {

    machine-type = {
      module.input = "self" ;
      module.name = "@imperium/machine-type";

      roles.laptop.tags.laptop = {};
    };


    


    # Docs: https://docs.clan.lol/reference/clanServices/admin/
    # Admin service for managing machines
    # This service adds a root password and SSH access.
    admin = {
      roles.default.tags.all = { };
      roles.default.settings.allowedKeys = {
        # Insert the public key that you want to use for SSH access.
        # All keys will have ssh access to all machines ("tags.all" means 'all machines').
        # Alternatively set 'users.users.root.openssh.authorizedKeys.keys' in each machine
        "dominus" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg";
      };
    };

    apetrovic-user =  {
      module.name = "users";
      roles.default.tags.all = { };
      roles.default.settings = {
        user = "apetrovic";
        prompt = true;
        share = true;
        groups = [
          "wheel" # Allow using 'sudo'
          "networkmanager" # Allows to manage network connections.
          "video" # Allows to access video devices.
          "input" # Allows to access input devices.
          "kvm"
          "adb"
          "docker"
        ];
      };

      roles.default.extraModules = [ ./users/apetrovic/home.nix ]; # 
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
      roles.controller.machines."__YOUR_CONTROLLER__" = { };
      # Peers of the network
      # tags.all means 'all machines' will joined
      roles.peer.tags.all = { };
    };

    # Docs: https://docs.clan.lol/reference/clanServices/tor/
    # Tor network provides secure, anonymous connections to your machines
    # All machines will be accessible via Tor as a fallback connection method
    tor = {
      roles.server.tags.nixos = { };
    };
  };

  # Additional NixOS configuration can be added here.
  # machines/jon/configuration.nix will be automatically imported.
  # See: https://docs.clan.lol/guides/more-machines/#automatic-registration
  machines = {
     enginseer = { config, pkgs, ... }: {
       environment.systemPackages = [ pkgs.btop ];

            users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg" # elided 
            ];
     };
  };
}
