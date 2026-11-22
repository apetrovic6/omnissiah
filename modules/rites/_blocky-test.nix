# VM test of modules/rites/blocky.nix, adapted from the earlier Blocky spike.
# (Underscore prefix: import-tree would otherwise load it as a flake module.)
# Not a flake output (the flake does not import it); run with
#   nix build --impure -L --no-link --expr \
#     'import ./modules/rites/_blocky-test.nix { flake = builtins.getFlake "git+file://'$PWD'"; }'
# `git add` new files first, or the flake's git-tree copy will not see them.
{flake}: let
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  hosts = flake.lib.hosts;
  vips = flake.lib.vips;
  ip = {
    blocky = "192.168.1.11";
    upstream = "192.168.1.30";
    client = "192.168.1.20";
  };
  static = name: {lib, ...}: {
    networking.firewall.enable = false;
    networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
      {
        address = ip.${name};
        prefixLength = 24;
      }
    ];
  };
in
  pkgs.testers.runNixOSTest {
    name = "blocky-module";
    skipLint = true;
    skipTypeCheck = true;
    nodes = {
      # The "public internet": gives the PUBLIC answers, so a leak through the
      # split-horizon shows up as these values.
      upstream = {...}: {
        imports = [(static "upstream")];
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            no-resolv = true;
            address = [
              "/ugalabugala.org/152.53.34.16"
              "/noosphere.uk/152.53.34.16"
              "/example.org/93.184.216.34"
              "/blocked.test/10.9.9.9"
            ];
          };
        };
      };

      blocky = {lib, ...}: {
        imports = [(static "blocky") flake.nixosModules.blocky];
        # Serves the NRD source for the conversion test.
        services.nginx = {
          enable = true;
          virtualHosts.localhost.root = pkgs.writeTextDir "nrd" ''
            # comment line
            newly.test

            other.test
          '';
        };
        services.imperium.blocky = {
          enable = true;
          port = 53;
          nrdUrl = "http://localhost/nrd";
        };
        # The test VM has no internet: swap the real upstream for the fake one
        # and the real lists for an inline one. Everything else (customDNS,
        # blocking type, NRD file path) is the module's own.
        services.blocky.settings = {
          upstreams.groups.default = lib.mkForce [ip.upstream];
          blocking.denylists.ads = lib.mkForce [
            "http://lists.invalid/hosts.txt"
            "*.blocked.test\n"
            "/var/lib/blocky-nrd/nrd.wildcard.txt"
          ];
          blocking.loading.downloads = {
            attempts = 1;
            timeout = "2s";
          };
        };
        environment.systemPackages = [pkgs.dig pkgs.curl];
      };

      client = {...}: {
        imports = [(static "client")];
        environment.systemPackages = [pkgs.dig];
      };
    };

    testScript = ''
      def q(name, typ="A", server="${ip.blocky}"):
          return client.succeed(f"dig +short +time=3 +tries=2 @{server} {name} {typ}").strip()

      def status(name, typ="A"):
          out = client.succeed(f"dig +time=3 +tries=2 @${ip.blocky} {name} {typ}")
          return out.split("status: ")[1].split(",")[0]

      start_all()
      upstream.wait_for_unit("dnsmasq.service")

      with subtest("blocky starts with the NRD file missing and a dead list URL"):
          blocky.wait_for_unit("blocky.service")
          blocky.wait_for_open_port(53)
          blocky.fail("test -e /var/lib/blocky-nrd/nrd.wildcard.txt")
          client.wait_until_succeeds("dig +short @${ip.blocky} example.org | grep -q .", timeout=60)

      with subtest("mapped ugalabugala vhost goes to cerberus"):
          assert q("ha.ugalabugala.org") == "${hosts.cerberus}", q("ha.ugalabugala.org")
          assert q("forge.ugalabugala.org") == "${hosts.cerberus}"

      with subtest("ugalabugala apex and unmapped names are NOT mapped"):
          assert q("ugalabugala.org") == "152.53.34.16", q("ugalabugala.org")
          assert q("matrix.ugalabugala.org") == "152.53.34.16"

      with subtest("noosphere.uk (apex and subdomains) goes to the traefik VIP"):
          assert q("noosphere.uk") == "${vips.traefik}"
          assert q("argocd.noosphere.uk") == "${vips.traefik}"

      with subtest("per-machine .omnissiah.internal names"):
          assert q("ryza.omnissiah.internal") == "${hosts.ryza}"
          assert q("cerberus.omnissiah.internal") == "${hosts.cerberus}"

      with subtest("blocking: inline list entry, NXDOMAIN, apex and subdomain"):
          assert status("sub.blocked.test") == "NXDOMAIN", status("sub.blocked.test")
          assert status("blocked.test") == "NXDOMAIN"
          assert q("example.org") == "93.184.216.34"

      with subtest("NRD service converts the list to *. form"):
          blocky.succeed("systemctl start blocky-nrd.service")
          out = blocky.succeed("cat /var/lib/blocky-nrd/nrd.wildcard.txt")
          print(out)
          assert out.split() == ["*.newly.test", "*.other.test"], out
          blocky.succeed("stat -c %a /var/lib/blocky-nrd/nrd.wildcard.txt | grep -qx 644")

      with subtest("blocky reads the NRD file (readable by its dynamic user)"):
          blocky.systemctl("restart blocky.service")
          blocky.wait_for_open_port(53)
          client.wait_until_succeeds("dig @${ip.blocky} x.newly.test | grep -q NXDOMAIN", timeout=60)

      with subtest("NRD download failure keeps the previous file and fails the unit"):
          blocky.succeed("systemctl stop nginx.service")
          blocky.fail("systemctl start blocky-nrd.service")
          blocky.succeed("grep -qx '[*].newly.test' /var/lib/blocky-nrd/nrd.wildcard.txt")

      with subtest("metrics"):
          assert "blocky_" in blocky.succeed("curl -fsS http://localhost:4000/metrics")
    '';
  }
