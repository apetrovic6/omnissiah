# Blocky: the LAN's DNS resolver, which replaced Technitium (configured
# imperatively in its web UI). Three identical, fully declarative instances,
# the hosts in cartographa's `lan.resolvers`, so that losing one host does not
# take DNS down with it. Every query is logged to one Postgres database on
# cerberus (`queryLog`), for the Grafana query dashboard.
#
# Everything a client could observe (split-horizon names, blocklists, upstream)
# is generated here, from cartographa, so the three configs are identical by
# construction.
#
# Deploy DNS changes as a set: the ugalabugala.org mappings are derived from
# cerberus's Caddy virtual hosts, so adding or removing a vhost changes the
# Blocky config of ALL three hosts. Deploying only cerberus would leave ryza
# and servitor answering with the old vhost set. Use
#   clan machines update cerberus ryza servitor
{self, ...}: {
  flake.nixosModules.blocky = {
    config,
    options,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption types mapAttrs' nameValuePair filter hasSuffix removePrefix removeSuffix;
    cfg = config.services.imperium.blocky;

    # The value of Caddy's `{$LAB_DOMAIN}` runtime placeholder on cerberus. It
    # appears literally in the virtual host names, so it has to be matched as a
    # string and cannot be read back from the Caddy config.
    labDomain = (import ../cartographa/_cartographa.nix).lab.domain;
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

    ql = cfg.queryLog;
    hostName = config.networking.hostName;
    # The machine that holds the query log database creates its role.
    isDatabaseMachine = hostName == ql.databaseMachine;
    # systemd puts LoadCredential files here, readable by Blocky's dynamic
    # user; the path is fixed, so the config can name it.
    pgpassCredential = "/run/credentials/blocky.service/pgpass";
    # Clan vars exist only on clan machines; the VM test passes its own file.
    hasClan = options ? clan;
  in {
    options.services.imperium.blocky = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      port = mkOption {
        type = types.port;
        default = 53;
        description = "The DNS port. Only tests change it.";
      };
      metricsPort = mkOption {
        type = types.port;
        default = 4000;
        description = "Blocky's local HTTP API, including /metrics. Bound to 127.0.0.1 only.";
      };
      listenAddresses = mkOption {
        type = types.listOf types.str;
        default = lib.optional (self.lib.hosts ? ${config.networking.hostName}) self.lib.hosts.${config.networking.hostName} ++ ["127.0.0.1"];
        defaultText = "[ self.lib.hosts.<hostName> \"127.0.0.1\" ]";
        description = "IPv4 addresses the DNS port is bound to. Never the wildcard: see ports.dns.";
      };
      nrdUrl = mkOption {
        type = types.str;
        default = "https://raw.githubusercontent.com/hagezi/nrd/main/domains/nrd7.txt";
        description = "Plain domain list (one per line, `#` comments) of newly registered domains.";
      };

      # Prometheus runs in the cluster and scrapes this host through here; see
      # the metrics proxy in `config`.
      metricsProxy = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        port = mkOption {
          type = types.port;
          default = 4001;
        };
        listenAddress = mkOption {
          type = types.str;
          default = self.lib.hosts.${config.networking.hostName};
          defaultText = "self.lib.hosts.<hostName>";
          description = "The LAN address the proxy binds to. Never the wildcard.";
        };
        sources = mkOption {
          type = types.attrsOf types.str;
          default = {inherit (self.lib.hosts) luna terra sol mars;};
          description = "name -> IPv4 address allowed to reach the proxy: the cluster nodes (see modules/rites/node-exporter.nix for why those and nothing wider).";
        };
      };

      # Every query, from all three instances, into one Postgres database, so
      # the Grafana query dashboard sees the whole LAN. DNS never depends on
      # it: if the database is unreachable at startup Blocky falls back to
      # logging to the journal (the watchdog below switches it back), and a
      # failed write while running only drops those entries.
      queryLog = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        databaseMachine = mkOption {
          type = types.str;
          default = "cerberus";
          description = "The clan machine whose Postgres (services.imperium.postgresql) holds the log.";
        };
        host = mkOption {
          type = types.str;
          default = self.lib.hosts.${ql.databaseMachine};
          defaultText = "self.lib.hosts.<databaseMachine>";
          description = "Address Blocky connects to. An IP, so the query log never needs DNS.";
        };
        retentionDays = mkOption {
          type = types.ints.positive;
          default = 14;
          description = "Older entries are deleted. Every name every device looked up is in there.";
        };
        pgpassFile = mkOption {
          type = types.path;
          default = config.clan.core.vars.generators.blocky-querylog.files.pgpass.path;
          defaultText = "the blocky-querylog clan var";
          description = "A pgpass file (`*:*:*:blocky:<password>`) for the `blocky` role.";
        };
      };
    };

    config = mkIf cfg.enable (lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.listenAddresses != ["127.0.0.1"];
            message = "services.imperium.blocky: host '${config.networking.hostName}' is not in self.lib.hosts (modules/cartographa/_chart.nix), so there is no LAN address to listen on; set services.imperium.blocky.listenAddresses.";
          }
          {
            # Clients only ask the resolvers in that list, so an instance
            # outside it would never be asked, and one missing from it would be
            # a resolver nobody configured.
            assertion = !(self.lib.hosts ? ${hostName}) || lib.elem self.lib.hosts.${hostName} self.lib.lan.resolvers;
            message = "services.imperium.blocky: ${hostName} runs Blocky but is not in cartographa's lan.resolvers (modules/cartographa/_chart.nix).";
          }
        ];

        services.blocky = {
          enable = true;
          settings = {
            ports = {
              # Explicit addresses, not the wildcard: systemd-resolved's stub
              # holds 127.0.0.53:53 and 127.0.0.54:53 on these hosts, and
              # Blocky's wildcard `listen udp :53` fails with "address already
              # in use" (reproduced in the VM test; see NOTES-blocky-impl.md).
              # The LAN address serves clients, 127.0.0.1 the host itself.
              dns = map (a: "${a}:${toString cfg.port}") cfg.listenAddresses;
              # The HTTP port is Blocky's whole REST API, unauthenticated (it can
              # disable blocking, trigger list refreshes, run queries), not just
              # /metrics. Localhost only; the NRD fetcher below uses it. Prometheus scrapes
              # through the metrics proxy below, which exposes only /metrics.
              http = "127.0.0.1:${toString cfg.metricsPort}";
            };

            # Quad9 over DNS-over-TLS, as Technitium had it. By IP, so the
            # upstreams themselves need no resolution; Quad9's certificates carry
            # the IPs as SANs (checked with openssl s_client -verify_ip).
            upstreams.groups.default = [
              "tcp-tls:9.9.9.9:853"
              "tcp-tls:149.112.112.112:853"
            ];

            # Blocky also uses the bootstrap resolver for the HOSTS of the list
            # URLs. Unset, that is /etc/resolv.conf, which after the cutover is
            # systemd-resolved -> Blocky itself: list downloads at boot would
            # race Blocky's own listener, and a host whose Blocky is down could
            # not refresh. Quad9 over DoT by IP makes Blocky independent of the
            # host resolver. Schema: docs/configuration.md "Bootstrap DNS
            # configuration" (blocky 0.36.0): an upstream given by IP needs no
            # `ips`.
            bootstrapDns = [
              {upstream = "tcp-tls:9.9.9.9:853";}
              {upstream = "tcp-tls:149.112.112.112:853";}
            ];

            # Technitium: minimum TTL 10 s, maximum 7 days.
            caching = {
              minTime = "10s";
              maxTime = "168h";
              # Re-resolve often-used names when they expire (Blocky: queried
              # more than 5 times in 2 h), so hot names stay answerable from
              # cache while Quad9 is briefly unreachable. Costs some upstream
              # traffic; minTime above keeps that modest.
              prefetching = true;
            };

            prometheus.enable = true;

            # Postgres, or nothing at all: Blocky's default is every query in
            # the journal. The password comes from PGPASSFILE (below), never the
            # config. Plain TCP on the LAN, like the other clients of that
            # Postgres. Blocky creates and migrates its `log_entries` table
            # itself and deletes rows past the retention.
            queryLog =
              if ql.enable
              then {
                type = "postgresql";
                target = "postgres://blocky@${ql.host}:5432/blocky?sslmode=disable";
                logRetentionDays = ql.retentionDays;
              }
              else {type = "none";};

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
              # the hagezi lists below are the `*.`-prefixed wildcard variants
              # (not `-onlydomains`, which would weaken blocking). hagezi `pro`
              # was dropped because `pro.plus` is a superset.
              #
              # StevenBlack is in hosts format, which Blocky matches EXACTLY
              # (weaker than in Technitium); hagezi pro.plus largely covers it,
              # the list is kept for the names it adds.
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
              #
              # cachePath persists the downloaded lists: with `fast` Blocky seeds
              # them from disk at startup, and serves a source from disk while its
              # host is unreachable. Without it a restart while GitHub is
              # unreachable leaves ad blocking off until the next refresh.
              # nixpkgs' unit has StateDirectory=blocky under DynamicUser, so
              # /var/lib/blocky is writable. 6h: with the cache, conditional
              # requests make refreshing cheap, and a failed first download is
              # retried sooner.
              loading = {
                strategy = "fast";
                refreshPeriod = "6h";
                downloads.cachePath = "/var/lib/blocky/lists";
              };
            };
          };
        };

        # NRD list: hagezi's nrd7 (domains registered in the last 7 days, all
        # TLDs, ~3.0M entries / 48 MB). It replaced shreshtait.com's nrd-1w, which
        # only covered .se/.sk/.nu (7.7k entries). Memory was measured locally
        # with every list loaded (3.4M denylist entries): ~69 MiB RSS for Blocky,
        # so size is no reason to drop it on servitor. The source is a plain
        # domain list with no `*.` variant, so
        # convert it. Written atomically (temp + rename) so Blocky never reads a
        # half-written file; on failure the previous file stays and the unit
        # fails loudly.
        #
        # nixpkgs runs Blocky with DynamicUser, so the file cannot be owned by
        # it. A separate StateDirectory with mode 0755 and a world-readable file
        # is readable by whichever transient uid Blocky gets (ProtectSystem=strict
        # still allows reads). So this fetcher MUST stay a non-DynamicUser unit: a
        # DynamicUser StateDirectory lives under /var/lib/private (0700), which
        # Blocky's transient uid cannot traverse.
        systemd.services.blocky-nrd = {
          description = "Fetch the newly-registered-domains list for Blocky";
          wants = ["network-online.target"];
          after = ["network-online.target" "blocky.service"];
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
            trap 'rm -f "$tmp" "$tmp.raw"' EXIT
            if ! curl -fsS --retry 3 --max-time 600 ${lib.escapeShellArg cfg.nrdUrl} -o "$tmp.raw"; then
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
            # Blocky only re-reads its sources every refreshPeriod; tell it now.
            # Ignore failure: Blocky may be down, and it reads the file at start.
            curl -fsS -X POST http://127.0.0.1:${toString cfg.metricsPort}/api/lists/refresh >/dev/null \
              || echo "blocky-nrd: could not trigger a list refresh (blocky down?)" >&2
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

        # DNS is open to everyone, as Technitium's was. The HTTP API is not
        # opened (localhost only, see ports.http above); the metrics proxy has its own
        # rules.
        networking.firewall = mkIf config.networking.firewall.enable {
          allowedTCPPorts = [cfg.port];
          allowedUDPPorts = [cfg.port];
        };

        # Start after the network is up (nixpkgs only `wants` it), so the first
        # list download at boot does not fail for lack of a network.
        systemd.services.blocky = {
          after = ["network-online.target"];
          wants = ["network-online.target"];
        };
      }

      (mkIf ql.enable {
        # The pgpass file as a credential: Blocky's dynamic user can read it,
        # nothing else can, and pgx (the driver behind Blocky's Postgres
        # writer) reads PGPASSFILE when the URL has no password.
        systemd.services.blocky = {
          environment.PGPASSFILE = pgpassCredential;
          serviceConfig.LoadCredential = ["pgpass:${ql.pgpassFile}"];
          # On the database machine, try the log only once Postgres is up.
          after = lib.optionals isDatabaseMachine ["postgresql.service" "postgresql-password-init.service"];
        };

        # Blocky tries the database only at startup (3 attempts, 2 s apart),
        # then logs every query to the journal for as long as it runs. That
        # happens when this host boots while cerberus is down. Every 10 minutes:
        # if this Blocky runs on the fallback because the database was
        # UNREACHABLE and it answers again, restart it. The other resolvers
        # cover the restart (about 35 s on servitor, which loads the lists
        # before it opens port 53).
        #
        # Not when Postgres answered and refused: a wrong password, a missing
        # role or database (SQLSTATE class 28 or 3D). A restart cannot fix
        # that, and restarting every 10 minutes would be a DNS outage on this
        # host every 10 minutes. The unit fails instead, so it shows; fix the
        # config, and the deploy that carries the fix restarts Blocky. (A
        # login check would need psql: 150 MiB on servitor for this.)
        systemd.services.blocky-querylog-watchdog = {
          description = "Restart Blocky when its query log fell back to the journal";
          path = [pkgs.systemd pkgs.bash pkgs.coreutils pkgs.gnugrep];
          serviceConfig.Type = "oneshot";
          script = ''
            id=$(systemctl show -p InvocationID --value blocky.service)
            [ -n "$id" ] || exit 0
            journalctl -q -o cat _SYSTEMD_INVOCATION_ID="$id" -g "using console as fallback" | grep -q . || exit 0
            # The fallback message spans several journal lines; the last retry
            # warning carries the whole error on one.
            reason=$(journalctl -q -o cat _SYSTEMD_INVOCATION_ID="$id" -g "Error occurred on query writer creation" | tail -n 1)
            if grep -Eq 'SQLSTATE (28|3D)' <<<"$reason"; then
              echo "query log is on the journal fallback because the database refused it; not restarting: $reason" >&2
              exit 1
            fi
            if timeout 3 bash -c 'exec 3<>/dev/tcp/${ql.host}/5432'; then
              echo "query log is on the journal fallback and ${ql.host}:5432 answers; restarting blocky"
              systemctl restart blocky.service
            fi
          '';
        };
        systemd.timers.blocky-querylog-watchdog = {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "10min";
            OnUnitActiveSec = "10min";
          };
        };
      })

      # Metrics proxy. Blocky's HTTP port is its whole REST API (it can disable
      # blocking), so it stays on 127.0.0.1; this is the one thing that is
      # exposed: GET /metrics, and a 404 for everything else, /api above all.
      #
      # Prometheus runs in the cluster and its scrape arrives masqueraded to the
      # IP of the node the pod is on, so the firewall below admits the node IPs
      # (`sources`), the same way modules/rites/node-exporter.nix does, and the
      # proxy is what keeps every pod from reaching /api/blocking/disable.
      #
      # nginx, as its own unit rather than services.nginx (cerberus has Caddy;
      # this must not become a web server others add vhosts to): a ~20-line
      # config is the whole behaviour, the stock `nginx` is in the binary cache for
      # aarch64 too (an overridden, slimmer build would be compiled on servitor),
      # and nothing here needs a second language runtime or a
      # custom daemon to maintain. A socket-activated systemd-socket-proxyd
      # was ruled out: it forwards bytes and cannot filter by path or method.
      (mkIf cfg.metricsProxy.enable (let
        mp = cfg.metricsProxy;
        confFile = pkgs.writeText "blocky-metrics-nginx.conf" ''
          daemon off;
          pid /run/blocky-metrics/nginx.pid;
          error_log stderr warn;
          events { worker_connections 64; }
          http {
            access_log off;
            client_body_temp_path /run/blocky-metrics/body;
            proxy_temp_path /run/blocky-metrics/proxy;
            fastcgi_temp_path /run/blocky-metrics/fastcgi;
            uwsgi_temp_path /run/blocky-metrics/uwsgi;
            scgi_temp_path /run/blocky-metrics/scgi;
            server {
              listen ${mp.listenAddress}:${toString mp.port};
              server_tokens off;
              # Exact match, and the upstream path is fixed, so nothing but
              # /metrics is ever requested from Blocky, whatever the client
              # sends (encoded or doubled slashes included). Only GET (and
              # HEAD); any other method is refused here.
              location = /metrics {
                limit_except GET { deny all; }
                proxy_pass http://127.0.0.1:${toString cfg.metricsPort}/metrics;
              }
              location / { return 404; }
            }
          }
        '';
      in {
        systemd.services.blocky-metrics-proxy = {
          description = "Blocky metrics-only proxy (GET /metrics)";
          wantedBy = ["multi-user.target"];
          # The LAN address must exist to be bound.
          after = ["network-online.target" "blocky.service"];
          wants = ["network-online.target"];
          serviceConfig = {
            ExecStart = "${pkgs.nginx}/bin/nginx -e stderr -c ${confFile}";
            DynamicUser = true;
            RuntimeDirectory = "blocky-metrics";
            Restart = "on-failure";
            RestartSec = "5s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectControlGroups = true;
            RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
            CapabilityBoundingSet = "";
          };
        };

        # One rule per source, in whichever backend the host uses (as in
        # node-exporter.nix; an IPv4 source is a parse error for ip6tables).
        networking.firewall = mkIf config.networking.firewall.enable (
          if config.networking.nftables.enable
          then {
            extraInputRules = ''
              ip saddr { ${lib.concatStringsSep ", " (lib.attrValues mp.sources)} } tcp dport ${toString mp.port} accept comment "blocky-metrics"
            '';
          }
          else {
            extraCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: ip: ''
                iptables -w -A nixos-fw -p tcp --dport ${toString mp.port} -s ${ip}/32 -m comment --comment blocky-metrics:${name} -j nixos-fw-accept
              '')
              mp.sources);
          }
        );
      }))

      # The password: generated once, shared by every Blocky host and by the
      # database machine, where the postgresql module sets it on the role.
      (lib.optionalAttrs hasClan {
        clan.core.vars.generators.blocky-querylog = mkIf ql.enable {
          share = true;
          files.password.secret = true;
          files.pgpass.secret = true;
          runtimeInputs = [pkgs.openssl];
          script = ''
            openssl rand -hex 32 | tr -d '\n' > "$out/password"
            printf '*:*:*:blocky:%s\n' "$(cat "$out/password")" > "$out/pgpass"
          '';
        };
      })

      # The role and database, on the database machine only.
      (lib.optionalAttrs (options.services.imperium ? postgresql) {
        services.imperium.postgresql.users.blocky = mkIf (ql.enable && isDatabaseMachine) {
          databases = ["blocky"];
          ensureDBOwnership = true;
          passwordDependency = "blocky-querylog";
        };

        # Grafana's read-only role (the cluster side is reliquary/blocky-grafana).
        # It owns nothing and may only SELECT from what `blocky` creates, including
        # the table Blocky itself creates on first start, which may come after the
        # grants ran: readOnlyAccess uses default privileges for role `blocky`, so no
        # re-grant is needed after Blocky's migrations. Its password comes from the
        # shared `blocky-grafana` var, declared by reliquary-blocky-grafana, which the
        # database machine (cerberus) imports.
        services.imperium.postgresql.users.blocky_grafana = mkIf (ql.enable && isDatabaseMachine) {
          databases = [];
          readOnlyAccess.blocky.owner = "blocky";
          passwordDependency = "blocky-grafana";
        };
      })
    ]);
  };
}
