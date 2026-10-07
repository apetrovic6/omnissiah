{
  self,
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    # sd-image.nix rather than sd-image-aarch64.nix: the aarch64 variant bakes
    # Raspberry Pi firmware and a Pi config.txt into the FIRMWARE partition and
    # drags in profiles/base.nix (installer tooling we do not want on the
    # deployed board). Everything from it that this board actually needs is set
    # explicitly below.
    #
    # Kept imported on the deployed system too, not just for image builds: it is
    # what defines `fileSystems."/"` by label, and keeping it means
    # `system.build.sdImage` stays available to rebuild the image later.
    "${modulesPath}/installer/sd-card/sd-image.nix"
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.overlays = [self.overlays.uboot-bananapi-m5];

  # U-Boot's Generic Distro Configuration Concept: it scans the partitions for
  # /boot/extlinux/extlinux.conf and takes the kernel, initrd and ${fdtfile}
  # from there. There is no EFI firmware on this board, so neither
  # systemd-boot nor GRUB (nor lanzaboote) has anything to install into.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # S905X3 is mainline (meson-sm1) -- no vendor kernel, no out-of-tree DTB.
  # CONFIG_MMC_MESON_GX and CONFIG_SERIAL_MESON_CONSOLE are both =y in the
  # arm64 defconfig nixpkgs builds from, so the SD/eMMC controller and this
  # console need no initrd modules. Ethernet (dwmac-meson8b plus the RTL8211F
  # PHY) comes up as a module after the initrd, which is fine -- root is local.
  #
  # ttyAML0, not ttyAMA0: the Amlogic meson_uart driver names its ports
  # differently from the ARM PL011 that most aarch64 images assume. Getting
  # this wrong costs you the serial console exactly when you need it.
  boot.kernelParams = [
    "console=ttyAML0,115200n8"
    "console=tty0"
  ];
  boot.consoleLogLevel = lib.mkDefault 7;

  sdImage = {
    # The FIRMWARE vfat partition is a Raspberry Pi vestige. It cannot be
    # dropped without rewriting the upstream module's sfdisk layout, so it
    # stays, empty. The 8 MiB gap in front of it (firmwarePartitionOffset) is
    # what leaves room for U-Boot in the raw sectors.
    populateFirmwareCommands = "";

    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./files/boot
    '';

    # U-Boot goes into the raw sectors ahead of the first partition. This is
    # also why the table has to stay MBR: a GPT header at LBA 1, and its entry
    # array at LBA 2-33, would sit exactly where these writes land.
    #
    # Order matters. The second write is clipped to 440 bytes deliberately --
    # it restores the boot ROM's entry code while leaving the MBR partition
    # table at offset 446 intact -- so it has to come after the bulk write.
    postBuildCommands = ''
      dd if=${pkgs.ubootBananaPim5}/u-boot.bin.sd.bin of=$img \
        conv=fsync,notrunc bs=512 skip=1 seek=1
      dd if=${pkgs.ubootBananaPim5}/u-boot.bin.sd.bin of=$img \
        conv=fsync,notrunc bs=1 count=440
    '';
  };
}
