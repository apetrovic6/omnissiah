{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  # Ryza alone declares the generator, so Clan never encrypts the private key for Stygies.
  hermesPublicKey = self.lib.vars.shared "hermes-stygies-ssh" "id_ed25519.pub";
  hermesUid = toString config.users.users.hermes.uid;
  # The workspace migration as hermes, from activation (as root) or by hand
  # (`sudo hermes-workspace-migrate`, or as hermes). Companies: every one in the
  # registry, enabled or not, since their directories may exist either way.
  hermesWorkspaceMigrate = pkgs.writeShellScriptBin "hermes-workspace-migrate" (let
    command = lib.escapeShellArgs ([
        (lib.getExe pkgs.python3)
        "-I"
        "${../../modules/rites/_hermes-workspace-migrate.py}"
        config.users.users.hermes.home
      ]
      ++ lib.attrNames (import ../ryza/_work-projects.nix).companies);
  in ''
    case "$(${lib.getExe' pkgs.coreutils "id"} -un)" in
      root) exec ${lib.getExe' pkgs.util-linux "runuser"} -u hermes -- ${command} ;;
      hermes) exec ${command} ;;
      *) printf '%s\n' 'run as root (sudo) or as hermes' >&2; exit 1 ;;
    esac
  '');
in {
  # The Forgejo bot credentials (HOM-17) and the work coder's company forges
  # (HOM-36); the hermes user and group are below.
  imports = [./disko.nix ./network.nix self.nixosModules.hermes-forgejo-bot self.nixosModules.hermes-work-coder];
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

  # Hermes: the personal coder in ~/personal, the work profile in ~/work
  # (<company>/<repo key>, .tasks/<company>).
  systemd.tmpfiles.rules = [
    "d /home/apetrovic/work 0750 apetrovic users -"
    "d /home/hermes/personal 0750 hermes hermes -"
    "d /home/hermes/work 0750 hermes hermes -"
  ];

  # One-time move from the old layout (~/work personal, ~/work-devzero work),
  # README "Hermes workspaces on stygies". Activation runs before tmpfiles on a
  # switch and at boot (/home is on the root filesystem), and the script ignores
  # the empty skeleton tmpfiles leaves after a refused run. It acts only while
  # ~/work-devzero exists and stops for good after a success (a done-stamp). It
  # never fails the switch: a refusal is printed in the deploy output and logged
  # to the journal (`journalctl -t hermes-workspace-migrate`); the task commands
  # refuse until the move is done. `sudo hermes-workspace-migrate` re-runs it.
  # codebase-memory-mcp: Hermes (on ryza) starts it over SSH as the hermes user
  # (machines/ryza/hermes.nix), so the index sits next to the repositories, in
  # ~/.cache/codebase-memory-mcp. /home is persistent here (no impermanence).
  environment.systemPackages = [hermesWorkspaceMigrate self.inputs.codebase-memory-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default];
  system.activationScripts.hermes-workspace-migrate = {
    deps = ["users"];
    text = ''
      if [ -d ${lib.escapeShellArg config.users.users.hermes.home} ]; then
        status=0
        output=$(${lib.getExe hermesWorkspaceMigrate} 2>&1) || status=$?
        if [ -n "$output" ]; then
          printf '%s\n' "$output" >&2
          priority=info
          [ "$status" -eq 0 ] || priority=err
          printf '%s\n' "$output" | ${lib.getExe' pkgs.systemd "systemd-cat"} -t hermes-workspace-migrate -p "$priority" 2>/dev/null || true
        fi
      fi
    '';
  };

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
