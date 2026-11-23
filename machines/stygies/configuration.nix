{
  config,
  lib,
  self,
  ...
}: let
  # Ryza alone declares the generator, so Clan never encrypts the private key for Stygies.
  hermesPublicKey = self.lib.vars.shared "hermes-stygies-ssh" "id_ed25519.pub";
  hermesUid = toString config.users.users.hermes.uid;
in {
  imports = [./disko.nix ./network.nix];
  # The VM architecture is known before the installer writes its facter report.
  nixpkgs.hostPlatform = "x86_64-linux";

  system.stateVersion = "26.05";
  services.qemuGuest.enable = true;

  users.groups.hermes = {};
  users.users.hermes = {
    isNormalUser = true;
    uid = 1100;
    group = "hermes";
    home = "/home/hermes";
    openssh.authorizedKeys.keys = lib.optional (builtins.pathExists hermesPublicKey) (
      lib.removeSuffix "\n" (builtins.readFile hermesPublicKey)
    );
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    # Only the provisioned public key should authorize Hermes, even on a persistent home.
    extraConfig = ''
      Match User hermes
        AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    '';
  };

  systemd.tmpfiles.rules = [
    "d /home/apetrovic/work 0750 apetrovic users -"
    "d /home/hermes/work 0750 hermes hermes -"
  ];

  nix.settings = {
    extra-experimental-features = ["nix-command" "flakes"];
    # Give one build all six vCPUs instead of multiplying jobs by cores per job.
    max-jobs = 1;
    cores = 6;
  };
  nix.gc = {
    dates = lib.mkForce "weekly";
    options = lib.mkForce "--delete-older-than 14d";
  };

  services.journald.settings.Journal = {
    Storage = "persistent";
    SystemMaxUse = "4G";
    MaxRetentionSec = "90day";
  };
  security.auditd.enable = true;
  security.audit.rules =
    map (arch: "-a always,exit -F arch=${arch} -S execve -S execveat -F uid=${hermesUid} -k hermes-exec")
    ["b64" "b32"];
}
