{self, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.impermanence;
  in {
    imports = [
      self.inputs.impermanence.nixosModules.impermanence
    ];

    options.services.imperium.impermanence = {
      enable = mkEnableOption "Enable Impermanence";
    };

    config = mkIf cfg.enable {
      environment.persistence."/persist" = {
        enable = true; # NB: Defaults to true, not needed
        hideMounts = true;
        directories = [
          "/etc"
          "/var/spool"
          "/root"
          "/srv"
          # "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/db/sudo/lectured"
          "/var/lib/systemd/coredump"
          "/etc/NetworkManager/system-connections"
          {
            directory = "/var/lib/colord";
            user = "colord";
            group = "colord";
            mode = "u=rwx,g=rx,o=";
          }
        ];
        files = [
          #          "/etc/machine-id"
          {
            file = "/var/keys/secret_file";
            parentDirectory = {mode = "u=rwx,g=,o=";};
          }
        ];

        users.apetrovic = {
          directories = [
            "Downloads"
            "Music"
            "Pictures"
            "Documents"
            "Videos"
            ".config"
            ".local/share"
            {
              directory = ".gnupg";
              mode = "0700";
            }
            {
              directory = ".ssh";
              mode = "0700";
            }
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
            ".local/share/direnv"
          ];
          files = [
            # ".screenrc"
            # ".bash_history"
            # ".gitconfig"
          ];
        };
      };

      boot.initrd.systemd = {
        # enable = lib.mkDefault true; # this enabled systemd support in stage1 - required for the below setup
        services.rollback = {
          description = "Rollback BTRFS root subvolume to a pristine state";
          wantedBy = ["initrd.target"];

          # LUKS/TPM process. If you have named your device mapper something other
          # than 'enc', then @enc will have a different name. Adjust accordingly.
          after = ["systemd-cryptsetup@cryptroot.service"];

          # Before mounting the system root (/sysroot) during the early boot process
          before = ["sysroot.mount"];

          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /mnt

            # We first mount the BTRFS root to /mnt
            # so we can manipulate btrfs subvolumes.
            mount -o subvol=/ /dev/mapper/cryptroot /mnt

            # While we're tempted to just delete /root and create
            # a new snapshot from /root-blank, /root is already
            # populated at this point with a number of subvolumes,
            # which makes `btrfs subvolume delete` fail.
            # So, we remove them first.
            #
            # /root contains subvolumes:
            # - /root/var/lib/portables
            # - /root/var/lib/machines

            btrfs subvolume list -o /mnt/root |
              cut -f9 -d' ' |
              while read subvolume; do
                echo "deleting /$subvolume subvolume..."
                btrfs subvolume delete "/mnt/$subvolume"
              done &&
              echo "deleting /root subvolume..." &&
              btrfs subvolume delete /mnt/root
            echo "restoring blank /root subvolume..."
            btrfs subvolume snapshot /mnt/root-blank /mnt/root

            # Once we're done rolling back to a blank snapshot,
            # we can unmount /mnt and continue on the boot process.
            umount /mnt
          '';
        };
      };
    };
  };
}
