{
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware.nix];

  networking.hostName = "servitor";

  # No tags in inventory/machines.nix yet, so this machine gets only the
  # clan-wide services (admin, tor). `base` is deliberately left off until the
  # board is known to boot -- it pulls in a large closure that would have to
  # cross-build or emulate before you ever see a login prompt. Add "base" to
  # the tags once this works.
  environment.systemPackages = with pkgs; [];

  networking.interfaces.end0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.13";
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = {
    address = "192.168.1.1";
    interface = "end0";
  };
  networking.nameservers = ["192.168.1.105"];

  environment.etc."NetworkManager/conf.d/unmanaged-end0.conf".text = ''
    [keyfile]
    unmanaged-devices=interface-name:end0;
  '';

  # ---------------------------------------------------------------------------
  # Network print server
  #
  # An HP LaserJet MFP M28-M31 (03f0:bf2a, serial VNC6X33483) hangs off this
  # board's USB port. Its printer interface is USB class 07/01/02 -- printer
  # class, *bidirectional* -- not protocol 04, so it does not speak
  # IPP-over-USB and `services.ipp-usb` plus driverless printing is not an
  # option for it. Its PPD reports `hpPrinterLanguage: hbpl1`, a host-based
  # language, so the rasterising happens here and the queue needs hplip's
  # hpcups filter. hbpl1 is handled by hpcups itself and this model is not
  # listed in models.dat as needing HP's binary plugin, so plain `hplip` is
  # enough -- `hplipWithPlugin`, whose blob is not built for aarch64 anyway,
  # is not.
  # ---------------------------------------------------------------------------
  services.printing = {
    enable = true;
    drivers = [pkgs.hplip];

    # The default is localhost:631, which would make this a print server that
    # only serves itself. openFirewall parses the port back out of
    # listenAddresses, so 631/tcp does not also need listing in
    # allowedTCPPorts below.
    listenAddresses = ["*:631"];
    openFirewall = true;

    # Must be false, and this is load-bearing rather than a preference.
    #
    # With socket activation on, the module turns listenAddresses into the
    # socket unit's ListenStream (cupsd.nix: it strips the "*:" prefix), so
    # "*:631" becomes a bare `ListenStream=631`. systemd binds that as a
    # single *dual-stack* socket, and every IPv4 client then reaches cupsd as
    # ::ffff:192.168.1.x. CUPS compares that against the IPv4 `Allow` masks
    # below, never matches, and answers 403 Forbidden to every TCP request --
    # including from 127.0.0.1. The giveaway in the log is cupsd failing its
    # own bind with "Unable to open listen socket for address 0.0.0.0:631 -
    # Address already in use", because systemd already holds it.
    #
    # With this off there is no socket unit, so cupsd honours `Listen *:631`
    # itself and opens one socket per address family (it sets IPV6_V6ONLY on
    # the v6 one), so IPv4 clients arrive as real IPv4 and the masks match.
    # On-demand activation buys a dedicated print server nothing anyway.
    startWhenNeeded = false;

    # Applied to <Location />, /admin and /admin/conf alike, so this is also
    # what lets you reach the web UI on http://192.168.1.13:631 from the LAN.
    allowFrom = ["localhost" "192.168.1.0/24"];

    # Both default to false and both are needed: defaultShared marks newly
    # added queues shared, browsing makes cupsd actually advertise them.
    # Without the pair the queue exists but is never offered to anyone.
    defaultShared = true;
    browsing = true;

    # cups-browsed points the other way -- it imports *other* servers' shared
    # queues, and is happy to invent duplicate phantom ones. This box is the
    # server, so it has nothing to import.
    browsed.enable = false;
  };

  # cupsd advertises its shared queues by registering them with avahi-daemon
  # over D-Bus; with no mDNS responder running, `browsing = true` advertises
  # to nobody and every client has to be pointed at
  # ipp://192.168.1.13:631/printers/LaserJet-M28 by hand. This is also what
  # makes the queue show up as AirPrint on phones and macOS.
  services.avahi = {
    enable = true;
    openFirewall = true; # 5353/udp
    publish = {
      enable = true;
      userServices = true;
    };
  };

  # Declared here rather than clicked together in the web UI, so the queue is
  # not a one-off living only in /var/lib/cups that a reinstall would lose.
  hardware.printers = {
    ensurePrinters = [
      {
        name = "LaserJet-M28";
        description = "HP LaserJet MFP M28-M31";
        location = "servitor";

        # The serial is what pins this to the physical unit -- without it the
        # URI is positional and breaks as soon as the printer is replugged
        # into a different port on the hub.
        deviceUri = "usb://HP/LaserJet%20MFP%20M28-M31?serial=VNC6X33483";

        # Relative to share/cups/model in the driver packages above; the exact
        # string `lpinfo -m` lists for hplip's PPD for this family.
        model = "HP/hp-laserjet_mfp_m28-m31.ppd.gz";

        # LC_PAPER is hr_HR in stc/base.nix; the PPD's own default is Letter.
        ppdOptions.PageSize = "A4";
      }
    ];
    ensureDefaultPrinter = "LaserJet-M28";
  };

  # ---------------------------------------------------------------------------
  # Network scanner
  #
  # The same box is also the scan server. Nothing about the printing config
  # above carries scanning -- SANE is a separate stack with its own daemon and
  # its own port; CUPS has no part in it.
  #
  # models.dat for this model (usb-pid=bf2a) says scan-type=9 (non-zero, so
  # hpaio drives it), scan-src=1 (SCAN_SRC_FLATBED -- no document feeder) and
  # plugin=0. That last one is what makes this possible at all on aarch64:
  # HP's proprietary scan plugin has no build for this architecture, so a
  # model that needed it would be a dead end here.
  #
  # There is no driverless alternative to fall back on either. A network HP
  # would be scanned over eSCL with sane-airscan, but this unit is
  # io-support=2 (USB only) and speaks no IPP-over-USB, so saned it is.
  # ---------------------------------------------------------------------------
  hardware.sane = {
    enable = true;
    extraBackends = [pkgs.hplip];
  };

  services.saned = {
    enable = true;

    # The module seeds saned.conf with `localhost` and nothing else, so
    # without this every client on the LAN is refused and the symptom is an
    # empty device list rather than an error. Note this is a plain host
    # allow-list: saned has no authentication, so anyone on the subnet can
    # drive the scanner.
    extraConfig = "192.168.1.0/24";
  };

  # The admin clan service (clan.nix, roles.default.tags.all) authorises the
  # admin key for root, which is what `clan machines update` uses. sshd itself
  # still has to be on for that to be reachable.
  services.openssh.enable = true;

  # 631/tcp (CUPS) comes from services.printing.openFirewall and 5353/udp
  # (mDNS) from services.avahi.openFirewall, so neither is repeated here.
  # 6566/tcp is not covered by anything: hardware.sane.openFirewall opens only
  # 8612/udp, the SANE *discovery* port, and never the port saned.socket
  # actually listens on.
  networking.firewall.allowedTCPPorts = [
    22
    6566 # sane-port, for saned
  ];

  # 4 GB of RAM and no swap partition in the image: without this, a
  # `nixos-rebuild` run on the board itself gets OOM-killed. Harmless when
  # everything is built on phalanx and copied over.
  zramSwap.enable = true;
}
