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
  # The Forgejo bot credentials (HOM-17); the hermes user and group are below.
  imports = [./disko.nix ./network.nix self.nixosModules.hermes-forgejo-bot];
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
    "d /home/hermes/work-devzero 0750 hermes hermes -"
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
  security.auditd = {
    enable = true;
    settings = {
      # Budget about 10 GiB for ~90 days of builds; the window depends on event volume.
      max_log_file = 256;
      num_logs = 40;
      max_log_file_action = "rotate";
      space_left = "10%";
      space_left_action = "syslog";
      admin_space_left = "5%";
      # Reclaim the oldest audit logs under disk pressure rather than suspending auditing.
      admin_space_left_action = "rotate";
      disk_full_action = "rotate";
    };
  };
  # Match processes running as Hermes and login sessions that later change UID.
  security.audit.rules = lib.concatMap (arch: [
    "-a always,exit -F arch=${arch} -S execve -S execveat -F uid=${hermesUid} -k hermes-exec"
    "-a always,exit -F arch=${arch} -S execve -S execveat -F auid=${hermesUid} -k hermes-exec"
  ]) ["b64" "b32"];
}
