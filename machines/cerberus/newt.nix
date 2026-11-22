# The Pangolin tunnel client (newt): how this site reaches the VPS, and which
# local destinations it offers to remote clients.
{
  self,
  lib,
  config,
  pkgs,
  ...
}: {
  # Pin the client WireGuard port so remote clients have a STABLE endpoint.
  #
  # Phone access to ntfy (machines/cerberus/ntfy.nix, https://ntfy.ugalabugala.org)
  # needs NO new connector resource: the `ugala-bugala` host resource below already
  # carries alias *.ugalabugala.org with tcp-ports including 443 to 192.168.1.105,
  # which is exactly where Caddy fronts ntfy. What the phone needs is SITE ACCESS --
  # in the Pangolin dashboard, add the phone's user/role to the site this newt
  # client belongs to (site niceId downright-southern-red-backed-salamander), so
  # newt delivers that wildcard route to the phone, and olm answers
  # ntfy.ugalabugala.org locally. Do NOT add an "ntfy" host resource for
  # 192.168.1.105: newt keeps one route per destination IP and the last written
  # port list wins, which is what blackholed 53/80/22/2222 on 2026-08-29.
  #
  # If a dashboard-clickable Endpoint is wanted instead (Perimeter/browser access),
  # point it at 192.168.1.105:102 with no Access Policy: ntfy does its own login,
  # and Pangolin's own cookie wall would break the ntfy mobile apps (they send
  # Basic/Bearer auth, not a Perimeter session).
  #
  # This router does symmetric NAT: it hands out a different external port per
  # destination and stops preserving the internal port under load. Pangolin
  # learns the site endpoint from newt's packets to gerbil and advertises that
  # to clients, so on 2026-08-29 it was telling phones to dial
  # 89.172.33.226:57404 while newt's live external port was 51211 — every remote
  # handshake vanished and olm clients re-registered in a loop every ~7 min.
  # LAN clients (e.g. phalanx) were unaffected because they never traverse NAT,
  # which makes this look client-specific when it is not.
  #
  # REQUIRES a matching static port-forward on the router:
  #   UDP 51820 -> 192.168.1.105:51820
  # Diagnose recurrence with:
  #   sqlite3 db.sqlite 'SELECT endpoint, listenPort FROM sites;'
  # and compare against the live source port gerbil sees:
  #   tcpdump -ni ens3 'udp port 21820 and src host <home-wan-ip>'
  networking.firewall.allowedUDPPorts = [51820];

  services.newt = {
    enable = true;
    settings.endpoint = "https://${self.lib.lab.domain}";
    settings.port = "51820";
    environmentFile = config.clan.core.vars.generators.newt.files."newt.env".path;

    blueprint = let
      # Must match sites.niceId in Pangolin's DB, otherwise the whole blueprint
      # silently no-ops with "Blueprint application failed: Site not found".
      # Check with: sqlite3 /var/lib/pangolin/config/db/db.sqlite 'select niceId from sites;'
      siteCerberus = "downright-southern-red-backed-salamander";
    in {
      private-resources = {
        # THE ONLY `mode = "host"` resource for 192.168.1.105 — keep it that way.
        # newt keeps exactly ONE route per destination IP and the last one
        # written wins, so a second resource on this destination silently
        # shadows this one with its own (narrower) port list. On 2026-08-29 a
        # `plex` host resource with ports 443,32400 won and blackholed 53/80/22
        # /2222: clients get 192.168.1.105 as their DNS server and olm installs
        # a /32 route for it through the tunnel, so every public lookup died
        # while *.ugalabugala.org kept working (olm answers aliases locally).
        # Which resource wins flips on newt's next FULL resource fetch, so it
        # can look healthy for days. Verify with:
        #   for p in 443 32400 2222 80; do bash -c "</dev/tcp/192.168.1.105/$p"; done
        # Ports below are the union of everything that host serves.
        ugala-bugala = {
          name = "Ugala Bugala";
          mode = "host";
          destination = self.lib.hosts.cerberus;
          alias = "*.${self.lib.lab.domain}";
          site = siteCerberus;
          disable-icmp = true;
          tcp-ports = "443,80,53,2222,22,32400";
          udp-ports = "443,80,53,2222,22,32400";
        };

        # Shares destination 192.168.1.105 with ugala-bugala, so its port list
        # MUST stay identical to that one — newt keeps a single route per
        # (client, destination) and the last write wins, so a narrower list here
        # silently blackholes whatever it omits. This resource previously had
        # 443,32400 and took out DNS (53), http (80) and ssh (22/2222) on
        # 2026-08-29. If you change ugala-bugala's ports, change these too.
        plex = {
          name = "plex";
          mode = "host";
          destination = self.lib.hosts.cerberus;
          alias = "plex.${self.lib.lab.domain}";
          site = siteCerberus;
          disable-icmp = true;
          tcp-ports = "443,80,53,2222,22,32400";
          udp-ports = "443,80,53,2222,22,32400";
          roles = ["plex"];
        };

        noosphere = {
          name = "Noosphere";
          mode = "host";
          destination = self.lib.vips.traefik;
          alias = "*.noosphere.uk";
          site = siteCerberus;
          disable-icmp = true;
          tcp-ports = "443,80,22";
          udp-ports = "443,80,22";
        };
      };
    };
  };

  clan.core.vars.generators.newt = {
    files."newt.env" = {
      secret = true;
      mode = "0400";
    };

    prompts.id = {
      description = "Newt client ID from Pangolin dashboard";
      type = "hidden";
      persist = true;
    };

    prompts.secret = {
      description = "Newt client secret from Pangolin dashboard";
      type = "hidden";
      persist = true;
    };

    runtimeInputs = [pkgs.coreutils];

    script = ''
            set -euo pipefail
            id="$(cat "$prompts/id")"
            secret="$(cat "$prompts/secret")"

            cat > "$out/newt.env" <<EOF
      NEWT_ID=$id
      NEWT_SECRET=$secret
      EOF
    '';
  };
}
