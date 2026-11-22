# Blocky: the LAN's DNS resolver, replacing Technitium (which was configured
# imperatively in its web UI). Run as three identical, fully declarative
# instances (cerberus, ryza, servitor) so that losing one host does not take
# DNS down with it.
#
# Everything a client could observe (split-horizon names, blocklists, upstream)
# is generated here, from cartographa, so the three instances cannot drift.
{self, ...}: {
  flake.nixosModules.blocky = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption types concatMapStringsSep concatStringsSep mapAttrs' mapAttrsToList nameValuePair filter hasSuffix removePrefix removeSuffix;
    cfg = config.services.imperium.blocky;

    # The value of Caddy's `{$LAB_DOMAIN}` runtime placeholder on cerberus. It
    # appears literally in the virtual host names, so it has to be matched as a
    # string and cannot be read back from the Caddy config.
    labDomain = "ugalabugala.org";
    labPlaceholder = "{$LAB_DOMAIN}";

    # Cerberus's Caddy virtual hosts, read from cerberus's configuration on
    # EVERY host (not `config.services.caddy` on cerberus), so the three
    # instances generate the identical set. Lazy: this only forces cerberus's
    # caddy options, which do not depend on Blocky, so no recursion on cerberus.
    cerberusVhosts = builtins.attrNames self.nixosConfigurations.cerberus.config.services.caddy.virtualHosts;

    # `ha.{$LAB_DOMAIN}` / `https://ha.{$LAB_DOMAIN}` -> `ha.ugalabugala.org`.
    # Anything not under the placeholder (`*.noosphere.uk`, `*.keksic.xyz`) is
    # dropped: those zones are mapped below as a whole.
    stripScheme = n: removePrefix "https://" (removePrefix "http://" n);
    labVhosts = map (n: "${removeSuffix labPlaceholder (stripScheme n)}${labDomain}") (
      filter (n: hasSuffix ".${labPlaceholder}" (stripScheme n)) cerberusVhosts
    );

    # Technitium had `*.ugalabugala.org -> cerberus` but the apex and
    # matrix.ugalabugala.org -> the VPS. Blocky cannot say "wildcard but not
    # the apex" (a mapping always covers its apex; a `customDNS.zone` takes over
    # the whole domain and ignores `*`), so every real cerberus vhost gets its
    # own mapping and everything else under the domain is left unmapped and
    # resolves publicly (apex and matrix -> the VPS).
    labMappings = lib.genAttrs labVhosts (_: self.lib.hosts.cerberus);

    # The cluster's CoreDNS answers the same zone the same way
    # (modules/taghmata/nixidy/apps/enginarium/rke2-config/default.nix).
    internalMappings = mapAttrs' (name: ip: nameValuePair "${name}.omnissiah.internal" ip) self.lib.hosts;

    nrdFile = "/var/lib/blocky-nrd/nrd.wildcard.txt";
  in {
    options.services.imperium.blocky = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      port = mkOption {
        type = types.port;
        default = 53;
        description = "The DNS port. 5335 while Technitium still owns 53.";
      };
      metricsPort = mkOption {
        type = types.port;
        default = 4000;
        description = "Blocky's HTTP port, serving /metrics.";
      };
      scrapeSources = mkOption {
        type = types.attrsOf types.str;
        default = {inherit (self.lib.hosts) luna terra sol mars;};
        description = "name -> IPv4 address allowed to scrape the metrics port: the cluster nodes.";
      };
      nrdUrl = mkOption {
        type = types.str;
        default = "https://shreshtait.com/newly-registered-domains/nrd-1w";
        description = "Plain domain list (one per line, `#` comments) of newly registered domains.";
      };
    };

    config = mkIf cfg.enable {
      services.blocky = {
        enable = true;
        settings = {
          ports = {
            dns = cfg.port;
            http = cfg.metricsPort;
          };

          # Quad9 over DNS-over-TLS, as Technitium had it. Addresses, not
          # hostnames, so no bootstrapDns is needed (Blocky documents
          # bootstrapDns as required only when an upstream is given as a
          # hostname: https://0xerr0r.github.io/blocky/latest/configuration/).
          # Quad9's certificates carry the IPs as SANs, so verification works.
          upstreams.groups.default = [
            "tcp-tls:9.9.9.9:853"
            "tcp-tls:149.112.112.112:853"
          ];

          # Technitium: minimum TTL 10 s, maximum 7 days.
          caching = {
            minTime = "10s";
            maxTime = "168h";
          };

          prometheus.enable = true;

          # Blocky logs every query to the journal by default. Off for now; a
          # central query log is a later step.
          queryLog.type = "none";

          customDNS = {
            customTTL = "5m";
            # Do not leak the public AAAA/MX/... of a name we answer locally.
            filterUnmappedTypes = true;
            mapping =
              {
                # A mapping covers the apex and every subdomain, which replaces
                # Technitium's `*.noosphere.uk` record.
                "noosphere.uk" = self.lib.vips.traefik;
                "keksic.xyz" = self.lib.hosts.keksic;
              }
              // labMappings
              // internalMappings;
          };

          blocking = {
            # In Blocky a plain list entry blocks only that exact name;
            # `*.example.org` blocks the apex and every subdomain (verified in
            # a VM test). Technitium blocked subdomains of plain entries, so
            # the `-onlydomains` variants it used would weaken blocking here:
            # these are the `*.`-prefixed (wildcard) variants. hagezi `pro` was
            # dropped because `pro.plus` is a superset.
            denylists.ads = [
              "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.plus.txt"
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/native.apple.txt"
              nrdFile
            ];
            clientGroupsBlock.default = ["ads"];
            blockType = "nxDomain";
            # `fast`: start answering at once and download lists in the
            # background, so boot never waits for or fails on a list (or on a
            # missing NRD file at first boot).
            loading = {
              strategy = "fast";
              refreshPeriod = "24h";
            };
          };
        };
      };

      # NRD list: the source is a plain domain list with no `*.` variant, so
      # convert it. Written atomically (temp + rename) so Blocky never reads a
      # half-written file; on failure the previous file stays and the unit
      # fails loudly.
      #
      # nixpkgs runs Blocky with DynamicUser, so the file cannot be owned by
      # it. A separate StateDirectory with mode 0755 and a world-readable file
      # is readable by whichever transient uid Blocky gets (ProtectSystem=strict
      # still allows reads).
      systemd.services.blocky-nrd = {
        description = "Fetch the newly-registered-domains list for Blocky";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        path = [pkgs.curl pkgs.gawk pkgs.coreutils];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "blocky-nrd";
          StateDirectoryMode = "0755";
          UMask = "0022";
          ProtectSystem = "strict";
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        script = ''
          set -eu
          dir=/var/lib/blocky-nrd
          tmp=$(mktemp "$dir/.nrd.XXXXXX")
          trap 'rm -f "$tmp"' EXIT
          if ! curl -fsS --retry 3 --max-time 120 ${lib.escapeShellArg cfg.nrdUrl} -o "$tmp.raw"; then
            echo "blocky-nrd: download of ${cfg.nrdUrl} failed; keeping the previous list" >&2
            rm -f "$tmp.raw"
            exit 1
          fi
          # Drop comments and blank lines, trim whitespace/CR, prefix `*.`.
          awk '{ sub(/\r$/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "" && $0 !~ /^#/) print "*." $0 }' "$tmp.raw" > "$tmp"
          rm -f "$tmp.raw"
          if [ ! -s "$tmp" ]; then
            echo "blocky-nrd: downloaded list is empty; keeping the previous list" >&2
            exit 1
          fi
          chmod 0644 "$tmp"
          mv -f "$tmp" ${nrdFile}
        '';
      };
      systemd.timers.blocky-nrd = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "2min";
          OnUnitActiveSec = "1d";
          RandomizedDelaySec = "10min";
        };
      };

      # DNS is open to everyone, as Technitium's was. The metrics port is open
      # per cluster node only, exactly as node-exporter does it (see the
      # reasoning in modules/rites/node-exporter.nix: Prometheus's scrape leaves
      # through whichever node the pod is on, masqueraded to that node's IP).
      networking.firewall = mkIf config.networking.firewall.enable (
        {
          allowedTCPPorts = [cfg.port];
          allowedUDPPorts = [cfg.port];
        }
        // (
          if config.networking.nftables.enable
          then {
            extraInputRules = ''
              ip saddr { ${concatStringsSep ", " (builtins.attrValues cfg.scrapeSources)} } tcp dport ${toString cfg.metricsPort} accept comment "blocky-metrics"
            '';
          }
          else {
            extraCommands = concatMapStringsSep "\n" ({
              name,
              ip,
            }: ''
              iptables -w -A nixos-fw -p tcp --dport ${toString cfg.metricsPort} -s ${ip}/32 -m comment --comment blocky-metrics:${name} -j nixos-fw-accept
            '') (mapAttrsToList (name: ip: {inherit name ip;}) cfg.scrapeSources);
          }
        )
      );
    };
  };
}
