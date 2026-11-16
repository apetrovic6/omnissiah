{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  diskId = "/dev/disk/by-id/nvme-WD_BLACK_SN770_2TB_23462Z801872";
in {
  imports = [
    self.nixosModules.workstation-host
    # self.inputs.magos.nixosModules
    self.inputs.nixos-hardware.nixosModules.common-cpu-amd
    self.inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    self.nixosModules.proaudio
    self.inputs.nixvirt.nixosModules.default

    ./vllm.nix

    # ./llama-cpp.nix and ./llama-swap.nix are left on disk but NOT imported:
    # Strata replaced the llama.cpp engine outright, and its server does its own
    # lazy load / idle unload (--lazy, --idle-unload), which was the only part of
    # llama-swap still earning its keep once coder-30b and qwen36-35b-q4 were
    # dropped. Re-import llama-swap.nix if a second model ever comes back.
    ./strata.nix
  ];

  nixpkgs.config.cudaCapabilities = ["8.6"];

  # Lets phalanx build the aarch64 closure for servitor (Banana Pi BPI-M5)
  # without a native aarch64 builder. The signed U-Boot is unaffected -- it is
  # pinned to an x86_64 build platform and cross-compiles, because the Amlogic
  # signing tool is an x86_64 binary and its Makefile dispatches on `uname -m`.
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  nixpkgs.config = {
    allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) [
        "replace"
        "nvidia"
      ];
    permittedInsecurePackages = ["electron-39.8.10" "pnpm-10.29.2"];
  };

  programs.kdeconnect.enable = true;

  magos.niri.outputs = {
    "DP-2" = {
      scale = 1.33;
      mode = "3840x2160@119.999";
    };
  };

  networking.interfaces.enp6s0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.46";
        prefixLength = 24;
      }
    ];
  };

  networking = {
    nameservers = [self.lib.lan.dns];
    defaultGateway = {
      address = self.lib.lan.gateway;
      interface = "enp6s0";
    };
  };

  virtualisation.waydroid.enable = true;

  networking.nftables.enable = true;

  boot = {
    kernelParams = ["amd_iommu=on"];
    kernelModules = ["kvm-amd" "vfio-pci" "r8169"];
  };

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = ["apetrovic"];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  # Let libvirt’s qemu use the bridge
  virtualisation.libvirtd = {
    allowedBridges = ["virbr0"];
  };

  hardware.nvidia.prime.sync.enable = lib.mkForce false;
  hardware.nvidia.prime.offload.enable = lib.mkForce false;

  # Realtime groundwork already comes from the rocksmith module via the
  # "gaming" tag; this adds the plugin search paths, JACK, a buffer ceiling
  # for mixdown sessions, and the DAW/plugin set.
  services.imperium.proaudio = {
    enable = true;
    soundcraft.enable = true;
    yabridge.enable = true;
    nam.enable = true;
    ilok.enable = true;
  };

  boot = {
    # llama-swap's models total ~80GB of mmap'ed weights, and MoE decode
    # reads experts straight out of the page cache, token by token. The
    # default swappiness (60) evicts exactly those pages first when a
    # build or a browser pressures memory -- zram had 23.5GB of them in
    # one recorded session -- and a compressed model page turns into
    # decompression cost per token, invisible in every llama.cpp counter.
    # On this box the page cache IS the working set; reclaim it last.
    kernel.sysctl."vm.swappiness" = lib.mkDefault 10;
  };

  boot.loader.grub.devices = [diskId];
}
