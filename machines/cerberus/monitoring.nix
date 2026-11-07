{
  config,
  lib,
  ...
}: let
  inherit (lib) concatMapStringsSep mapAttrsToList;

  # --- who may scrape ---------------------------------------------------------
  #
  # Prometheus lives in the cluster and cerberus does not, so the scrape reaches
  # this host from outside the cluster: pod traffic to the LAN leaves through the
  # node the Prometheus pod happens to run on, and cerberus sees that node's IP as
  # the source, never a pod IP (there is no route on the router for the pod CIDR,
  # so the node masquerades). Which node that is moves when the pod is rescheduled
  # — Prometheus' TSDB volume is longhorn, so the pod can land on any node — hence
  # all four node IPs are allowed.
  #
  # These are the static node IPs from inventory/machines.nix (and each node's own
  # machines/<node>/configuration.nix). Nothing here is a range or a /24: phalanx
  # (192.168.1.75), the VPS and every other LAN device must be refused, and they
  # are — the nixos-fw chain ends in `nixos-fw-log-refuse`, so a port that has no
  # matching rule here is closed.
  # attrname = node name, value = that node's IP, so the iptables comment can
  # say which machine a rule belongs to when someone reads `iptables -L nixos-fw`.
  scrapeSources = {
    luna = "192.168.1.232";
    terra = "192.168.1.138";
    sol = "192.168.1.42";
    mars = "192.168.1.44";
  };

  exporterPort = 9100;

  # --- collector flags --------------------------------------------------------
  #
  # Flag names and default values below were taken from `--help` of the pinned
  # package itself (node_exporter 1.12.1, the same build the cluster's DaemonSet
  # runs — node_exporter_build_info{job="node-exporter"} reports version="1.12.1"),
  # not from documentation or memory:
  #
  #   --collector.filesystem.mount-points-exclude
  #       default ^/(dev|proc|run/credentials/.+|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($|/)
  #   --collector.filesystem.fs-types-exclude
  #       default ^(autofs|binfmt_misc|bpf|cgroup2?|configfs|debugfs|devpts|devtmpfs|fusectl|
  #               hugetlbfs|iso9660|mqueue|nsfs|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|
  #               selinuxfs|squashfs|erofs|sysfs|tracefs)$
  #   --[no-]collector.systemd            default: DISABLED  -> enabledCollectors below
  #
  # Two things that are easy to get wrong here:
  #
  # 1. The exclusion flags are OVERRIDES, not additions: passing one replaces the
  #    exporter's default list entirely. So each value below is the real default
  #    with our entries added, copied out of --help, rather than a short list that
  #    would silently re-enable every pseudo-filesystem the default drops.
  #
  # 2. `$$` is not a typo. The nixpkgs exporter module splices extraFlags straight
  #    into the unit's ExecStart, and systemd expands `$VAR` in ExecStart; a single
  #    `$` would vanish as an unset variable. systemd.service(5), "Command lines":
  #    "to pass a literal dollar sign, use \"$$\"". The exporter therefore receives
  #    `$`, which is what the Go regex needs.
  #    Verified against the built unit file: /etc/systemd/system/
  #    prometheus-node-exporter.service in cerberus's toplevel carries `$$`, and
  #    running the same binary with the `$` form behaves as intended (see the
  #    report).
  filesystemExcludeFlags = [
    # /mnt added: every NFS export (modules/rites/nfs.nix) and every SMB share
    # (services.imperium.smb) on this host lives under /mnt/nas.
    "--collector.filesystem.mount-points-exclude=^/(dev|mnt|proc|run/credentials/.+|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($$|/)"

    # nfs|nfs4|cifs|cifsdfs added to the default list. The default excludes only
    # pseudo-filesystems, so a Synology mount would otherwise be scraped: the
    # filesystem collector calls statfs() on every mount it keeps, and a dead NAS
    # would then stall the scrape on it. The mounts are `soft` with timeo=30
    # retrans=3 (modules/rites/nfs.nix) so it would recover rather than hang
    # forever, but "recover after 3 retries against a dead NAS" is still a worse
    # monitoring story than "never touch it": cerberus has one local disk, and the
    # thing that filled in 2026-11-06 (a stale container volume) is on it. NFS
    # health is not this exporter's job.
    # nfsvers=4.1 mounts appear as fstype "nfs4" in /proc/self/mountinfo, so both
    # spellings are needed; cifs/cifsdfs are the systemd/cifs-utils spellings for
    # the SMB shares.
    "--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|cifs|cifsdfs|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|nfs|nfs4|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|smb2|smb3|squashfs|erofs|sysfs|tracefs)$$"
  ];

  # node_exporter's own default unit filter is
  #     .+\.(automount|device|mount|scope|slice)
  # i.e. mount units are dropped. Kept EXCEPT for .mount, because this host's
  # real state lives on NFS mounts (Forgejo stateDir=/mnt/nas/git, immich
  # mediaLocation=/mnt/nas/photos) and a failed mnt-nas-*.mount unit is the first
  # hard signal that the NAS link is broken. `[.]` is used instead of `\.` on
  # purpose: a backslash would have to survive both Nix string escaping and
  # systemd's ExecStart unescaping to arrive at the regex intact, and a character
  # class says the same thing with nothing to get wrong.
  # .automount/.device/.scope/.slice stay excluded: automount masters never hold
  # a failed state worth paging for, .device units churn with USB/network events,
  # and .scope/.slice are session plumbing that would only add series.
  systemdUnitFilterFlags = [
    "--collector.systemd.unit-exclude=.+[.](automount|device|scope|slice)"
  ];
in {
  # Metric names and label names every alert in
  # modules/noosphere/taghmata/nixidy/_env/apps/prometheus-stack/cerberus-alerts.nix
  # is written against come from a live scrape of this same binary version with
  # these same flags.
  services.prometheus.exporters.node = {
    enable = true;
    port = exporterPort;

    # The exporter listens on all addresses; reachability is decided by the
    # firewall rules below, not by the bind address. Binding to 192.168.1.105
    # instead would couple the unit to an address that configuration.nix owns
    # elsewhere, and would not add anything: the only paths to this host are the
    # LAN and Pangolin's newt routes, and neither carries 9100 (see the
    # `ugala-bugala`/`plex` tcp-ports lists in configuration.nix — adding 9100 to
    # those would also trip the one-route-per-destination trap documented there).
    listenAddress = "0.0.0.0";

    # openFirewall = true would be the one-line way to do this, and it is exactly
    # the wrong thing: with the iptables backend (cerberus's firewall backend
    # evaluates to "iptables"; networking.nftables.enable is false) the exporter
    # module appends
    #     ip46tables -A nixos-fw -p tcp -m tcp --dport 9100 -j nixos-fw-accept
    # with no source match, i.e. it opens the exporter to the whole LAN and to
    # anything routed in. The rule is written by hand below instead.
    openFirewall = false;

    # --collector.systemd is off by default in 1.12.1, which is why the cluster's
    # node-exporter scrape returns no node_systemd_* series at all. On this host
    # the failed-unit signal is the point: Forgejo, Technitium, Caddy, ntfy,
    # Postgres, immich and the runner are all systemd units.
    enabledCollectors = ["systemd"];

    extraFlags = filesystemExcludeFlags ++ systemdUnitFilterFlags;
  };

  # iptables style, because cerberus's firewall backend is the iptables one
  # (config.networking.firewall.backend evaluates to "iptables" on this pinned
  # nixpkgs), and the module writes an `iptables` rule per accepted port into the
  # `nixos-fw` chain just before its closing reject rule. `extraInputRules` is the
  # nftables flavour and would be inert here.
  #
  # Plain `iptables`, not the module helper `ip46tables`: that helper runs the
  # identical arguments through ip6tables too, and an IPv4 source address is a
  # parse error there. All four sources are IPv4, as is the Prometheus target.
  #
  # `networking.firewall.extraCommands` is a plain string option (last definition
  # wins, no merge), so the existing value on this host was checked: it is empty.
  networking.firewall.extraCommands =
    concatMapStringsSep "\n" ({
      name,
      ip,
    }: ''
      iptables -w -A nixos-fw -p tcp --dport ${toString exporterPort} -s ${ip}/32 -m comment --comment prometheus-node-exporter:${name} -j nixos-fw-accept
    '') (mapAttrsToList (name: ip: {
        inherit name ip;
      })
      scrapeSources);

  # A note on what is deliberately NOT here: no NFS/CIFS filesystem monitoring
  # (excluded above), no swap rule (this host has none configured), and no
  # blackbox probe of Technitium or Forgejo — the cluster has no blackbox-exporter
  # deployed, and standing one up just for two LAN probes is a component, not a
  # flag. See the report for what enabling it would take.
}
