{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    self.nixosModules.noosphere
    self.nixosModules.pharos
    self.nixosModules.smb
    self.nixosModules.nfs
    self.nixosModules.scriptorium
    self.nixosModules.librarium
    ./network.nix
    ./database.nix
    ./vaultwarden.nix
    ./newt.nix
    ./proxy.nix
    ./storage.nix
    ./media.nix
    ./forgejo.nix
    ./home-assistant.nix
    ./nopresh.nix
    ./kaneo.nix
    ./memos.nix
    ./davical.nix
    ./forgejo-runner.nix
    ./monitoring.nix
    ./heartbeat.nix
    ./ntfy.nix
    ./pilot.nix
  ];

  services.qemuGuest.enable = true;

  nixpkgs.config.allowUnfree = true; # can't set with external pkgs from pkgsForSystem

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 10d";
    };
    settings = {
      trusted-users = ["apetrovic"];
      auto-optimise-store = true;
      # The daily gc only drops paths older than 10 days, which leaves a
      # 125 GB root that also holds CI workspaces with little headroom. Nix collects garbage mid-build once free space
      # drops below min-free, until max-free.
      # Not the runner module's `storeCache`, which replaces the daily gc.
      min-free = 20 * 1024 * 1024 * 1024;
      max-free = 40 * 1024 * 1024 * 1024;
    };
  };

  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = false;
    };
  };

  services.dbus.enable = true;
}
