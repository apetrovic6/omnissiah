# node_exporter on every clan machine outside the cluster, scraped by the
# cluster's Prometheus. Imported by the `base` service (stc/base.nix), so a new
# machine has it as soon as it is tagged `base`; the scrape side is generated
# from inventory/machines.nix (nixidy apps/augur/prometheus-stack/nodes.nix),
# so it is picked up there too.
#
# Off on the RKE2 nodes: the cluster's own node-exporter DaemonSet already runs
# there, on the same port.
#
# Generalized from cerberus's (2026-11), whose reasoning holds for every host:
#
# Who may scrape. Prometheus runs in the cluster, so its scrape leaves through
# whichever node the pod is on and arrives masqueraded to that node's IP (there
# is no route for the pod CIDR). Hence all four node IPs, and nothing wider:
# no LAN range, so no other device can read a host's metrics.
#
# Collector flags (node_exporter 1.12.1, from its own --help):
# - The exclusion flags REPLACE the defaults, so each value below is the
#   default plus our entries, not a short list that would re-enable every
#   pseudo-filesystem.
# - `$$` is not a typo: the module splices these into ExecStart, where systemd
#   expands `$VAR`; `$$` reaches the exporter as the `$` the regex needs.
# - /mnt and nfs/nfs4/cifs/smb are excluded: statfs() on a dead NAS mount would
#   stall the scrape, and NAS health is not this exporter's job.
# - The systemd collector is on (off by default): a failed unit is the most
#   useful signal on these hosts. Unit filter keeps .mount units, since a
#   failed NAS mount is the first hard sign the NAS link is broken.
{self, ...}: {
  flake.nixosModules.node-exporter = {
    config,
    lib,
    ...
  }: let
    inherit (lib) mkIf mkOption types concatMapStringsSep concatStringsSep mapAttrsToList;
    cfg = config.services.imperium.nodeExporter;
  in {
    options.services.imperium.nodeExporter = {
      enable = mkOption {
        type = types.bool;
        default = !(config.services.rke2.enable or false);
        defaultText = "true, except on RKE2 nodes";
      };
      port = mkOption {
        type = types.port;
        default = 9100;
      };
      scrapeSources = mkOption {
        type = types.attrsOf types.str;
        default = {inherit (self.lib.hosts) luna terra sol mars;};
        description = "name -> IPv4 address allowed to scrape: the cluster nodes.";
      };
    };

    config = mkIf cfg.enable {
      services.prometheus.exporters.node = {
        enable = true;
        inherit (cfg) port;
        # Reachability is the firewall's job (below), not the bind address's.
        listenAddress = "0.0.0.0";
        # Would open the port to everyone; the rules below are per source.
        openFirewall = false;
        enabledCollectors = ["systemd"];
        extraFlags = [
          "--collector.filesystem.mount-points-exclude=^/(dev|mnt|proc|run/credentials/.+|sys|var/lib/docker/.+|var/lib/containers/storage/.+)($$|/)"
          "--collector.filesystem.fs-types-exclude=^(autofs|binfmt_misc|bpf|cgroup2?|cifs|cifsdfs|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|iso9660|mqueue|nsfs|nfs|nfs4|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|selinuxfs|smb2|smb3|squashfs|erofs|sysfs|tracefs)$$"
          "--collector.systemd.unit-exclude=.+[.](automount|device|scope|slice)"
        ];
      };

      # One rule per source, in whichever backend the host uses. iptables:
      # plain `iptables`, since an IPv4 source is a parse error for ip6tables.
      networking.firewall = mkIf config.networking.firewall.enable (
        if config.networking.nftables.enable
        then {
          extraInputRules = ''
            ip saddr { ${concatStringsSep ", " (builtins.attrValues cfg.scrapeSources)} } tcp dport ${toString cfg.port} accept comment "prometheus-node-exporter"
          '';
        }
        else {
          extraCommands = concatMapStringsSep "\n" ({
            name,
            ip,
          }: ''
            iptables -w -A nixos-fw -p tcp --dport ${toString cfg.port} -s ${ip}/32 -m comment --comment prometheus-node-exporter:${name} -j nixos-fw-accept
          '') (mapAttrsToList (name: ip: {inherit name ip;}) cfg.scrapeSources);
        }
      );
    };
  };
}
