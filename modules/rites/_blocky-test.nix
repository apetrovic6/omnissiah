# VM test of modules/rites/blocky.nix, adapted from the earlier Blocky spike.
# (Underscore prefix: import-tree would otherwise load it as a flake module.)
# Not a flake output (the flake does not import it); run with
#   nix build --impure -L --no-link --expr \
#     'import ./modules/rites/_blocky-test.nix { flake = builtins.getFlake "git+file://'$PWD'"; }'
# `git add` new files first, or the flake's git-tree copy will not see them.
#
# Out of scope (no internet in the VM): the real DoT connection to Quad9 (the
# IP-SAN validity was checked by hand with `openssl s_client -verify_ip`), the
# real list downloads and their formats. x86_64 only; servitor (aarch64) relies
# on nixpkgs' build-time `blocky validate`. The HTTP port is bound to
# localhost; the metrics-only proxy in front of /metrics is tested below. A `db` node stands in
# for cerberus's Postgres, for the query log.
{flake}: let
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  inherit (flake.lib) hosts vips;
  ip = {
    blocky = "192.168.1.11";
    blocky2 = "192.168.1.12";
    upstream = "192.168.1.30";
    db = "192.168.1.40";
    client = "192.168.1.20";
  };
  # Production's port.
  port = 53;
  # The test database's password, as the clan var's pgpass would hold it.
  pgpass = pkgs.writeText "pgpass" "*:*:*:blocky:testpw\n";
  # NB: test names use .net, not .test: Blocky itself answers NXDOMAIN for the
  # RFC 6761 special-use TLD `.test`, which would make every block assertion
  # pass trivially.
  static = name: {lib, ...}: {
    networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
      {
        address = ip.${name};
        prefixLength = 24;
      }
    ];
  };
  # The module as production uses it; only what cannot work offline is
  # replaced: the upstream, the bootstrap resolver and the real list URLs.
  blockyNode = name: dnsPort: {lib, ...}: {
    imports = [(static name) flake.nixosModules.blocky];
    # Serves the NRD source for the conversion test.
    services.nginx = {
      enable = true;
      virtualHosts.localhost.root = pkgs.writeTextDir "nrd" ''
        # comment line
        newly.net

        other.net
      '';
    };
    # The real timer would fire 2-12 min after boot and race the test; the
    # service is started explicitly instead.
    systemd.timers.blocky-nrd.enable = lib.mkForce false;
    services.imperium.blocky = {
      enable = true;
      port = dnsPort;
      listenAddresses = [ip.${name} "127.0.0.1"];
      metricsProxy = {
        listenAddress = ip.${name};
        # blocky: the client is a scraper; blocky2 keeps the default (the k8s
        # nodes), so the client must be shut out there.
        sources = lib.optionalAttrs (name == "blocky") {client = ip.client;};
      };
      nrdUrl = "http://localhost/nrd";
      queryLog = {
        host = ip.db;
        pgpassFile = pgpass;
      };
    };
    # Triggered by the test, not by time.
    systemd.timers.blocky-querylog-watchdog.enable = lib.mkForce false;
    services.blocky.settings = {
      # Flush within the test's patience (30 s in production).
      queryLog.flushInterval = "2s";
      upstreams.groups.default = lib.mkForce [ip.upstream];
      bootstrapDns = lib.mkForce [{upstream = ip.upstream;}];
      blocking.denylists.ads = lib.mkForce [
        "http://${ip.upstream}/list.txt"
        "*.blocked.net\n"
      ];
      blocking.denylists.nrd = lib.mkForce ["/var/lib/blocky-nrd/nrd.wildcard.txt"];
      blocking.clientGroupsBlock.default = lib.mkForce ["ads" "nrd"];
      blocking.loading.downloads = {
        attempts = 1;
        timeout = "2s";
      };
    };
    environment.systemPackages = [pkgs.dig pkgs.curl];
  };
in
  pkgs.testers.runNixOSTest {
    name = "blocky-module";
    skipLint = true;
    skipTypeCheck = true;
    nodes = {
      # The "public internet": gives the PUBLIC answers, so a leak through the
      # split-horizon shows up as these values. Also serves a blocklist.
      upstream = {...}: {
        imports = [(static "upstream")];
        networking.firewall.enable = false;
        services.nginx = {
          enable = true;
          virtualHosts.localhost.root = pkgs.writeTextDir "list.txt" "*.listed.net\n";
        };
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            no-resolv = true;
            address = [
              "/ugalabugala.org/152.53.34.16"
              "/noosphere.uk/152.53.34.16"
              "/keksic.xyz/152.53.34.16"
              "/example.org/93.184.216.34"
              "/blocked.net/10.9.9.9"
              "/listed.net/10.7.7.7"
              "/newly.net/10.8.8.8"
            ];
            # A public AAAA for a mapped name: must NOT leak.
            host-record = ["ha.ugalabugala.org,2001:db8::1"];
          };
        };
      };

      # The query log's database, standing in for cerberus's Postgres.
      db = {...}: {
        imports = [(static "db")];
        networking.firewall.allowedTCPPorts = [5432];
        services.postgresql = {
          enable = true;
          enableTCPIP = true;
          ensureDatabases = ["blocky"];
          ensureUsers = [
            {
              name = "blocky";
              ensureDBOwnership = true;
            }
          ];
          initialScript = pkgs.writeText "init.sql" "CREATE ROLE blocky LOGIN PASSWORD 'testpw';";
          authentication = "host blocky blocky 192.168.1.0/24 scram-sha-256";
        };
      };

      # Production shape: port 53, firewall ON (the module must open it), the
      # query log on the db node.
      blocky = blockyNode "blocky" port;

      # B3: the cutover shape. systemd-resolved's stub holds 127.0.0.53:53,
      # Blocky wants :53 on every address.
      blocky2 = {lib, ...}: {
        imports = [(blockyNode "blocky2" 53)];
        services.imperium.blocky.queryLog.enable = false;
        services.resolved.enable = true;
        networking.nameservers = [ip.blocky2];
      };

      client = {...}: {
        imports = [(static "client")];
        networking.firewall.enable = false;
        environment.systemPackages = [pkgs.dig pkgs.curl];
      };
    };

    testScript = ''
      def q(name, typ="A", server="${ip.blocky}", p=${toString port}):
          return client.succeed(f"dig +short +time=3 +tries=2 -p {p} @{server} {name} {typ}").strip()

      def status(name, typ="A", server="${ip.blocky}", p=${toString port}):
          out = client.succeed(f"dig +time=3 +tries=2 -p {p} @{server} {name} {typ}")
          return out.split("status: ")[1].split(",")[0]

      start_all()
      upstream.wait_for_unit("dnsmasq.service")
      upstream.wait_for_unit("nginx.service")

      with subtest("blocky starts with the NRD file missing"):
          blocky.wait_for_unit("blocky.service")
          blocky.wait_for_open_port(${toString port})
          blocky.fail("test -e /var/lib/blocky-nrd/nrd.wildcard.txt")
          blocky.fail("systemctl is-active blocky-nrd.timer")
          client.wait_until_succeeds("dig +short -p ${toString port} @${ip.blocky} example.org | grep -q .", timeout=60)

      with subtest("DNS port is open through the firewall; HTTP API is not"):
          assert q("example.org") == "93.184.216.34"
          client.fail("curl -m 3 -fsS http://${ip.blocky}:4000/metrics")
          blocky.succeed("curl -fsS http://127.0.0.1:4000/metrics | grep blocky_ > /dev/null")

      with subtest("mapped ugalabugala vhost goes to cerberus"):
          assert q("ha.ugalabugala.org") == "${hosts.cerberus}", q("ha.ugalabugala.org")
          assert q("forge.ugalabugala.org") == "${hosts.cerberus}"

      with subtest("ugalabugala apex and unmapped names are NOT mapped"):
          assert q("ugalabugala.org") == "152.53.34.16", q("ugalabugala.org")
          assert q("matrix.ugalabugala.org") == "152.53.34.16"

      with subtest("noosphere.uk apex and subdomains go to the traefik VIP"):
          assert q("noosphere.uk") == "${vips.traefik}"
          assert q("argocd.noosphere.uk") == "${vips.traefik}"

      with subtest("keksic.xyz subdomains go to keksic"):
          assert q("x.keksic.xyz") == "${hosts.keksic}", q("x.keksic.xyz")

      with subtest("per-machine .omnissiah.internal names"):
          assert q("ryza.omnissiah.internal") == "${hosts.ryza}"
          assert q("cerberus.omnissiah.internal") == "${hosts.cerberus}"

      with subtest("filterUnmappedTypes: the public AAAA of a mapped name does not leak"):
          assert q("ha.ugalabugala.org", "AAAA", server="${ip.upstream}", p=53) == "2001:db8::1"
          aaaa = q("ha.ugalabugala.org", "AAAA")
          print("AAAA ha.ugalabugala.org via blocky:", repr(aaaa))
          assert aaaa == "", aaaa

      with subtest("sub-subdomain of a mapped vhost"):
          sub = q("x.ha.ugalabugala.org")
          print("x.ha.ugalabugala.org via blocky:", repr(sub), status("x.ha.ugalabugala.org"))
          # PIN: a mapping covers subdomains, so this goes to cerberus too.
          assert sub == "${hosts.cerberus}", sub

      with subtest("blocking: inline entry, NXDOMAIN, apex and subdomain"):
          assert status("sub.blocked.net") == "NXDOMAIN", status("sub.blocked.net")
          assert status("blocked.net") == "NXDOMAIN"
          assert q("example.org") == "93.184.216.34"

      with subtest("blocking: list served over HTTP"):
          client.wait_until_succeeds("dig -p ${toString port} @${ip.blocky} x.listed.net | grep -q NXDOMAIN", timeout=60)

      with subtest("NRD service converts the list and triggers a refresh, no restart"):
          print("pre x.newly.net:", repr(q("x.newly.net")), status("x.newly.net"), "upstream:", repr(q("x.newly.net", server="${ip.upstream}", p=53)))
          assert q("x.newly.net") == "10.8.8.8", q("x.newly.net")
          blocky.succeed("systemctl start blocky-nrd.service")
          out = blocky.succeed("cat /var/lib/blocky-nrd/nrd.wildcard.txt")
          print(out)
          assert out.split() == ["*.newly.net", "*.other.net"], out
          blocky.succeed("stat -c %a /var/lib/blocky-nrd/nrd.wildcard.txt | grep -qx 644")
          client.wait_until_succeeds("dig -p ${toString port} @${ip.blocky} x.newly.net | grep -q NXDOMAIN", timeout=30)
          # Reported per group: the NRD names are under "nrd", not "ads".
          blocky.wait_until_succeeds("curl -fsS http://127.0.0.1:4000/metrics | grep -x 'blocky_denylist_cache_entries{group=\"nrd\"} 2' > /dev/null", timeout=30)
          ads = blocky.succeed("curl -fsS http://127.0.0.1:4000/metrics | grep '^blocky_denylist_cache_entries{group=\"ads\"}'")
          print(ads)
          assert "nrd" not in ads
          blocky.succeed("systemctl show -p ActiveEnterTimestamp blocky.service")

      with subtest("NRD download failure keeps the previous file and fails the unit"):
          blocky.succeed("systemctl stop nginx.service")
          blocky.fail("systemctl start blocky-nrd.service")
          blocky.succeed("grep -qx '[*].newly.net' /var/lib/blocky-nrd/nrd.wildcard.txt")

      with subtest("lists survive a restart with the list host down (cachePath)"):
          blocky.succeed("ls -la /var/lib/blocky/lists/ || true")
          upstream.succeed("systemctl stop nginx.service")
          blocky.systemctl("restart blocky.service")
          blocky.wait_for_open_port(${toString port})
          client.wait_until_succeeds("dig -p ${toString port} @${ip.blocky} x.listed.net | grep -q NXDOMAIN", timeout=60)
          client.wait_until_succeeds("dig -p ${toString port} @${ip.blocky} x.newly.net | grep -q NXDOMAIN", timeout=60)

      with subtest("upstream DNS down: mapped names answer, blocked names stay blocked"):
          upstream.succeed("systemctl stop dnsmasq.service")
          assert q("ha.ugalabugala.org") == "${hosts.cerberus}"
          assert q("x.noosphere.uk") == "${vips.traefik}"
          assert status("x.listed.net") == "NXDOMAIN"
          assert status("sub.blocked.net") == "NXDOMAIN"
          upstream.succeed("systemctl start dnsmasq.service")

      with subtest("B3: port 53 next to systemd-resolved's stub"):
          blocky2.wait_for_unit("systemd-resolved.service")
          blocky2.wait_for_unit("blocky.service")
          blocky2.wait_for_open_port(53)
          print(blocky2.succeed("ss -lunpt | grep ':53 '"))
          assert q("ha.ugalabugala.org", server="${ip.blocky2}", p=53) == "${hosts.cerberus}"
          stub = blocky2.wait_until_succeeds("dig +short +time=3 @127.0.0.53 ha.ugalabugala.org", timeout=60).strip()
          print("via resolved stub:", repr(stub))
          assert stub == "${hosts.cerberus}", stub
          # Blocky itself still answers on loopback.
          assert blocky2.succeed("dig +short @127.0.0.1 ha.ugalabugala.org").strip() == "${hosts.cerberus}"

      with subtest("metrics proxy: /metrics through it, nothing else reaches Blocky; closed to other sources"):
          blocky.wait_for_unit("blocky-metrics-proxy.service")
          blocky.wait_for_open_port(4001, "${ip.blocky}")
          m = client.succeed("curl -m 5 -fsS http://${ip.blocky}:4001/metrics")
          assert "blocky_blocking_enabled 1" in m, m[:300]
          assert "blocky_denylist_cache_entries" in m
          for method in ["GET", "POST", "PUT", "DELETE", "PATCH"]:
              for path in ["/api/blocking/disable", "/api/blocking/disable?duration=1h", "/api/lists/refresh", "/", "/metrics/../api/blocking/disable", "/%2e%2e/api/blocking/disable", "//api/blocking/disable"]:
                  code = client.succeed(f"curl -m 5 -s -o /dev/null -w %{{http_code}} -X {method} --path-as-is 'http://${ip.blocky}:4001{path}'").strip()
                  assert code in ("404", "403", "400", "405"), (method, path, code)
          for method in ["POST", "PUT", "DELETE"]:
              code = client.succeed(f"curl -m 5 -s -o /dev/null -w %{{http_code}} -X {method} http://${ip.blocky}:4001/metrics").strip()
              assert code == "403", (method, code)
          # Blocking is still on, both in Blocky and as the scraper sees it.
          blocky.succeed("curl -fsS http://127.0.0.1:4000/api/blocking/status | grep -q '\"enabled\":true'")
          assert "blocky_blocking_enabled 1" in client.succeed("curl -m 5 -fsS http://${ip.blocky}:4001/metrics")
          assert status("sub.blocked.net") == "NXDOMAIN"
          # blocky2 runs the proxy too, but the client is not an allowed source.
          blocky2.wait_for_unit("blocky-metrics-proxy.service")
          blocky2.succeed("curl -m 5 -fsS http://${ip.blocky2}:4001/metrics | grep blocky_ > /dev/null")
          client.fail("curl -m 3 -fsS http://${ip.blocky2}:4001/metrics")
          # And the real API port is closed from the LAN on both.
          client.fail("curl -m 3 -fsS http://${ip.blocky}:4000/metrics")

      def logged(name):
          return db.succeed(
              f"sudo -u postgres psql -d blocky -tAc \"select count(*) from log_entries where question_name = '{name}'\""
          ).strip()

      def invocation():
          return blocky.succeed("systemctl show -p InvocationID --value blocky.service").strip()

      with subtest("query log: queries land in Postgres, password from PGPASSFILE"):
          db.wait_for_unit("postgresql.service")
          db.wait_for_open_port(5432)
          # Blocky may have started before the database and fallen back.
          blocky.systemctl("restart blocky.service")
          blocky.wait_for_open_port(${toString port})
          client.wait_until_succeeds("dig +short -p ${toString port} @${ip.blocky} probe1.example.org | grep -q 93.184.216.34", timeout=60)
          db.wait_until_succeeds(
              "sudo -u postgres psql -d blocky -tAc \"select count(*) from log_entries where question_name = 'probe1.example.org'\" | grep -qv '^0$'",
              timeout=60,
          )
          print(db.succeed("sudo -u postgres psql -d blocky -c 'select request_ts, client_ip, question_name, reason, hostname from log_entries order by request_ts desc limit 5'"))
          blocky.fail("journalctl -u blocky.service -b -q -g 'using console as fallback' | grep -q .")

      with subtest("query log: database down at startup; DNS answers, the watchdog restores the log"):
          db.systemctl("stop postgresql.service")
          blocky.systemctl("restart blocky.service")
          blocky.wait_for_open_port(${toString port})
          assert q("probe2.example.org") == "93.184.216.34"
          blocky.wait_until_succeeds("journalctl -u blocky.service -q -g 'using console as fallback' | grep -q .", timeout=60)
          # Database still down: the watchdog leaves Blocky alone.
          before = invocation()
          blocky.succeed("systemctl start blocky-querylog-watchdog.service")
          assert invocation() == before, "watchdog restarted blocky while the database was down"
          db.systemctl("start postgresql.service")
          db.wait_for_open_port(5432)
          blocky.succeed("systemctl start blocky-querylog-watchdog.service")
          assert invocation() != before, "watchdog did not restart blocky with the database back"
          blocky.wait_for_open_port(${toString port})
          client.wait_until_succeeds("dig +short -p ${toString port} @${ip.blocky} probe3.example.org | grep -q 93.184.216.34", timeout=60)
          db.wait_until_succeeds(
              "sudo -u postgres psql -d blocky -tAc \"select count(*) from log_entries where question_name = 'probe3.example.org'\" | grep -qv '^0$'",
              timeout=60,
          )
          # The fallback went to the journal only, never to the database.
          assert logged("probe2.example.org") == "0", logged("probe2.example.org")

      with subtest("query log: database refuses the login; the watchdog does NOT restart, it fails"):
          db.succeed("sudo -u postgres psql -c \"ALTER ROLE blocky PASSWORD 'wrong'\"")
          blocky.systemctl("restart blocky.service")
          blocky.wait_for_open_port(${toString port})
          assert q("probe4.example.org") == "93.184.216.34"
          blocky.wait_until_succeeds("journalctl -u blocky.service -q -g 'retry attempt 3/3.*SQLSTATE 28' | grep -q .", timeout=60)
          blocky.wait_until_succeeds("journalctl -u blocky.service -q -g 'using console as fallback' --since '-30s' | grep -q .", timeout=60)
          before = invocation()
          blocky.fail("systemctl start blocky-querylog-watchdog.service")
          assert invocation() == before, "watchdog restarted blocky although the database refused the login"
          print(blocky.succeed("journalctl -u blocky-querylog-watchdog.service -q -o cat | tail -n 2"))
          db.succeed("sudo -u postgres psql -c \"ALTER ROLE blocky PASSWORD 'testpw'\"")
    '';
  }
