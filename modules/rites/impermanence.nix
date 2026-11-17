# Impermanence: the root filesystem is thrown away on every boot, and only
# what is listed here survives, bind-mounted from a persistent volume.
#
# Two parts, both under services.imperium.impermanence:
#
#   - what persists: `directories` and `files` for the system, and
#     `users.<name>.{directories,files}` relative to a user's home. Any module
#     may add to these, so a service can declare its own state next to itself.
#   - how the root is reset: `rollback` restores a blank btrfs snapshot over the
#     root subvolume in the initrd, after the encrypted device is unlocked.
#
# The defaults are the layout the workstations' disko files create: a LUKS
# device named cryptroot holding the subvolumes `root`, `root-blank` and
# `persist`, the last mounted at /persist.
{self, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.impermanence;
    rb = cfg.rollback;

    # A path, or the attribute set the upstream module accepts for one
    # (directory/file plus mode, user, group, parentDirectory).
    entries = types.listOf (types.either types.str types.attrs);
  in {
    imports = [
      self.inputs.impermanence.nixosModules.impermanence
    ];

    options.services.imperium.impermanence = {
      enable = mkEnableOption "an ephemeral root with explicit persistence";

      persistPath = mkOption {
        type = types.str;
        default = "/persist";
        description = "Mount point of the persistent volume.";
      };

      directories = mkOption {
        type = entries;
        description = "System directories to keep. Definitions add to the defaults.";
      };

      files = mkOption {
        type = entries;
        description = "System files to keep. Definitions add to the defaults.";
      };

      users = mkOption {
        default = {};
        description = "What to keep in each user's home, as paths relative to it.";
        type = types.attrsOf (types.submodule {
          options = {
            directories = mkOption {
              type = entries;
              default = [];
            };
            files = mkOption {
              type = entries;
              default = [];
            };
          };
        });
      };

      rollback = {
        enable = mkEnableOption "resetting the root subvolume on every boot" // {default = true;};

        device = mkOption {
          type = types.str;
          default = "/dev/mapper/cryptroot";
          description = "The btrfs filesystem that holds the subvolumes.";
        };

        subvolume = mkOption {
          type = types.str;
          default = "root";
          description = "The root subvolume, deleted and recreated on every boot.";
        };

        blankSnapshot = mkOption {
          type = types.str;
          default = "root-blank";
          description = "The empty snapshot the root subvolume is recreated from.";
        };

        after = mkOption {
          type = types.listOf types.str;
          default = ["systemd-cryptsetup@cryptroot.service"];
          description = "Initrd units that make `device` available, such as the LUKS unlock.";
        };
      };
    };

    config = mkIf cfg.enable {
      # What every machine with an ephemeral root needs to keep.
      services.imperium.impermanence = {
        directories = [
          "/etc"
          "/var/spool"
          "/root"
          "/srv"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/db/sudo/lectured"
          "/var/lib/systemd/coredump"
          "/etc/NetworkManager/system-connections"
        ];
        files = [
          {
            file = "/var/keys/secret_file";
            parentDirectory = {mode = "u=rwx,g=,o=";};
          }
        ];
      };

      boot.tmp.cleanOnBoot = lib.mkDefault true;

      environment.persistence.${cfg.persistPath} = {
        enable = true;
        hideMounts = true;
        inherit (cfg) directories files users;
      };

      boot.initrd.systemd.services.rollback = mkIf rb.enable {
        description = "Rollback BTRFS root subvolume to a pristine state";
        wantedBy = ["initrd.target"];

        # After the device is unlocked, and before the system root (/sysroot) is
        # mounted during early boot.
        inherit (rb) after;
        before = ["sysroot.mount"];

        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          mkdir -p /mnt

          # We first mount the BTRFS root to /mnt
          # so we can manipulate btrfs subvolumes.
          mount -o subvol=/ ${rb.device} /mnt

          # While we're tempted to just delete /root and create
          # a new snapshot from /root-blank, /root is already
          # populated at this point with a number of subvolumes,
          # which makes `btrfs subvolume delete` fail.
          # So, we remove them first.
          #
          # /root contains subvolumes:
          # - /root/var/lib/portables
          # - /root/var/lib/machines

          btrfs subvolume list -o /mnt/${rb.subvolume} |
            cut -f9 -d' ' |
            while read subvolume; do
              echo "deleting /$subvolume subvolume..."
              btrfs subvolume delete "/mnt/$subvolume"
            done &&
            echo "deleting /${rb.subvolume} subvolume..." &&
            btrfs subvolume delete /mnt/${rb.subvolume}
          echo "restoring blank /${rb.subvolume} subvolume..."
          btrfs subvolume snapshot /mnt/${rb.blankSnapshot} /mnt/${rb.subvolume}

          # Once we're done rolling back to a blank snapshot,
          # we can unmount /mnt and continue on the boot process.
          umount /mnt
        '';
      };
    };
  };
}
