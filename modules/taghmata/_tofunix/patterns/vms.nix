# Proxmox virtual machines that a clan machine is installed onto.
#
#   manufactorum.vms.ryza = {
#     vmId = 120;
#     mac = "BC:24:11:5A:6E:01";
#     cores = 6;
#     memory = 16;
#     disk = 100;
#   };
#
# The VM boots the installer ISO (manufactorum.nix) only while its disk is
# empty: `scsi0` comes first in the boot order, so once
# `clan machines install` has written a bootloader the CD-ROM is never reached
# again and can stay attached.
#
# The disk is `scsi0` on virtio-scsi, so the guest sees it as
# /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi0, the id that clan's
# `ext4-single-disk` disko template (machines/mars/disko.nix) expects.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.manufactorum;
in {
  options.manufactorum = {
    node = mkOption {
      type = types.str;
      description = "The Proxmox node the VMs run on.";
    };
    datastore = mkOption {
      type = types.str;
      description = "The datastore VM disks are created on.";
    };
    bridge = mkOption {
      type = types.str;
      description = "The bridge VM NICs attach to.";
    };
    installer = mkOption {
      type = types.str;
      description = "The CD-ROM file id the VMs install from, as an OpenTofu expression.";
    };

    vms = mkOption {
      default = {};
      description = "Virtual machines, by clan machine name.";
      type = types.attrsOf (types.submodule {
        options = {
          vmId = mkOption {type = types.ints.positive;};
          mac = mkOption {
            type = types.str;
            description = "Fixed, so the DHCP reservation survives a recreate.";
          };
          cores = mkOption {type = types.ints.positive;};
          memory = mkOption {
            type = types.ints.positive;
            description = "GiB.";
          };
          disk = mkOption {
            type = types.ints.positive;
            description = "GiB. Growing it is in place; shrinking it is refused.";
          };
          description = mkOption {
            type = types.str;
            default = "";
          };
        };
      });
    };
  };

  config.resource.proxmox_virtual_environment_vm =
    lib.mapAttrs (name: vm: {
      inherit name;
      inherit (vm) description;
      node_name = cfg.node;
      vm_id = vm.vmId;
      tags = ["clan" "tofunix"];

      machine = "q35";
      bios = "seabios";
      operating_system.type = "l26";
      on_boot = true;
      started = true;
      # The guest agent is enabled in the NixOS configuration; until it is
      # installed, the provider would wait for it on every apply.
      agent = {
        enabled = true;
        timeout = "2m";
      };

      cpu = {
        inherit (vm) cores;
        type = "host";
      };
      memory.dedicated = vm.memory * 1024;

      scsi_hardware = "virtio-scsi-single";
      disk = [
        {
          datastore_id = cfg.datastore;
          interface = "scsi0";
          size = vm.disk;
          file_format = "raw";
          discard = "on";
          iothread = true;
          ssd = true;
        }
      ];

      cdrom = {
        file_id = cfg.installer;
        interface = "ide2";
      };
      boot_order = ["scsi0" "ide2"];

      # The provider declares this as a typed attribute, not a block, so in
      # JSON every field must be given. The zeros and "" are its "unset".
      network_device = [
        {
          inherit (cfg) bridge;
          model = "virtio";
          mac_address = vm.mac;
          disconnected = false;
          enabled = null; # deprecated; null keeps the attribute typed but unset
          firewall = false;
          mtu = 0;
          queues = 0;
          rate_limit = 0;
          trunks = "";
          vlan_id = 0;
        }
      ];

      serial_device = [{device = "socket";}];

      # A destroy is a power-off, not a shutdown request the guest may ignore.
      stop_on_destroy = true;
    })
    cfg.vms;
}
