{self, ...}: {
  # Signed U-Boot for the Banana Pi BPI-M5 (Amlogic S905X3, G12A/SM1 family).
  #
  # nixpkgs has no bananapi-m5 target. Its closest relative is
  # `ubootLibreTechCC`, which hand-rolls the *GXL* signing chain
  # (aml_encrypt_gxl, no DDR blobs). The M5 is G12A: a different tool, nine DDR
  # firmware blobs and `--level v3` throughout. Rather than transcribe that
  # sequence, this drives LibreELEC's own `g12a.inc` Makefile, which is what
  # upstream U-Boot's board documentation tells you to use.
  #
  # The build platform is pinned to x86_64 on purpose. `aml_encrypt_g12a` is a
  # statically linked x86_64 ELF, and g12a.inc dispatches on `uname -m`:
  # anything else makes it reach for `qemu-x86_64 -L /usr/x86_64-linux-gnu/`, a
  # path that does not exist on NixOS. A native aarch64 build -- including an
  # emulated one under binfmt, where `uname -m` answers aarch64 -- takes that
  # branch and dies. Fixing buildPlatform here also makes the U-Boot compile
  # itself a real cross-compile rather than an emulated one.
  flake.overlays.uboot-bananapi-m5 = _final: _prev: {
    ubootBananaPim5 = let
      crossPkgs = import self.inputs.nixpkgs {
        system = "x86_64-linux";
        crossSystem.config = "aarch64-unknown-linux-gnu";

        # Standalone nixpkgs instance: it does not inherit the flake's
        # `pkgsForSystem` config, and both the vendor blobs and the signing
        # tool are redistributable-but-unfree firmware.
        config.allowUnfree = true;
      };

      inherit (crossPkgs) lib;

      # Amlogic publishes no sources for the boot firmware or for the tool that
      # assembles a bootable image, so the blobs have to come from the vendor.
      # LibreELEC's collection is the one upstream U-Boot documents.
      amlogicBootFip = crossPkgs.fetchFromGitHub {
        owner = "LibreELEC";
        repo = "amlogic-boot-fip";
        rev = "61bd933c03b14ed6d360c1e48f2f7b26bb7484c9";
        hash = "sha256-bgQeJiyplVrLRJ/TH8ruf7uqZlV8q4Bd9zBttTAa1Gs=";
        meta.license = lib.licenses.unfreeRedistributableFirmware;
      };
    in
      crossPkgs.buildUBoot {
        defconfig = "bananapi-m5_defconfig";

        filesToInstall = [
          "amlogic-fip/u-boot.bin"
          # The .sd.bin variant additionally carries the 512-byte block the
          # boot ROM reads from sector 0, so it is the one to flash.
          "amlogic-fip/u-boot.bin.sd.bin"
        ];

        postBuild = ''
          # g12a.inc resolves the blobs, ./blx_fix.sh and ./aml_encrypt_g12a
          # relative to the board directory and writes into $O and $TMP, so the
          # read-only store copy has to be made writable first. The board's own
          # Makefile is a bare `include ../g12a.inc`, hence the sibling layout.
          cp -r ${amlogicBootFip}/bananapi-m5 amlogic-fip-src
          cp ${amlogicBootFip}/g12a.inc .
          chmod -R u+w amlogic-fip-src

          # blx_fix.sh is `#!/bin/bash`, which does not exist in the sandbox.
          # Without this the FIP build dies on ENOENT with nothing useful said.
          patchShebangs amlogic-fip-src

          mkdir -p amlogic-fip amlogic-fip-tmp
          make -C amlogic-fip-src \
            BL33="$PWD/u-boot.bin" \
            O="$PWD/amlogic-fip" \
            TMP="$PWD/amlogic-fip-tmp"

          # The boot ROM only accepts an image carrying the @AML magic at
          # offset 0x10. A silent signing failure would otherwise ship a blob
          # that just does not boot, with nothing to diagnose on the board.
          magic=$(dd if=amlogic-fip/u-boot.bin bs=1 skip=16 count=4 status=none)
          if [ "$magic" != "@AML" ]; then
            echo "u-boot signing failed: expected @AML at 0x10, got '$magic'" >&2
            exit 1
          fi
        '';

        extraMeta = {
          platforms = ["aarch64-linux"];
          license = lib.licenses.unfreeRedistributableFirmware;
          longDescription = ''
            Boot loader for the Banana Pi BPI-M5.

            It lives in the raw sectors ahead of the first partition rather than
            in a filesystem, so `nixos-rebuild` never updates it -- a U-Boot
            bump has to be flashed by hand. Flashing:

            ```sh
            dd if=u-boot.bin.sd.bin of=<dev> conv=fsync,notrunc bs=512 skip=1 seek=1
            dd if=u-boot.bin.sd.bin of=<dev> conv=fsync,notrunc bs=1 count=440
            ```

            The second write is clipped to 440 bytes and must come last: it
            restores the boot ROM's entry code without overwriting the MBR
            partition table at offset 446.
          '';
        };
      };
  };
}
