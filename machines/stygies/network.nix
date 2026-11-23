{
  config,
  lib,
  self,
  ...
}: let
  inherit (self.lib) hosts lan vips;
  hermesUid = toString config.users.users.hermes.uid;
  nixBuildGid = toString config.users.groups.nixbld.gid;
  resolvers = lib.concatStringsSep ", " lan.resolvers;
in {
  networking = {
    networkmanager.enable = lib.mkForce false;
    useDHCP = lib.mkForce false;
    useNetworkd = true;

    firewall.extraInputRules = ''
      ip saddr ${lan.cidr} tcp dport 3000-9000 accept
    '';
    nftables = {
      enable = true;
      tables.stygies = {
        family = "inet";
        content = ''
          chain output {
            type filter hook output priority filter; policy accept;
            meta skuid ${hermesUid} jump restricted_egress
            # Nix builders open sockets with nixbld as their primary GID.
            # This deliberately limits apetrovic's builds too, but not the root daemon's ncps fetches.
            meta skgid ${nixBuildGid} jump restricted_egress
          }

          chain restricted_egress {
            oifname "lo" accept
            ct state { established, related } accept
            ip daddr { ${resolvers} } udp dport 53 accept
            ip daddr { ${resolvers} } tcp dport 53 accept
            # Caddy on Cerberus proxies many LAN services. The separate Cerberus policy
            # restricts HTTPS from Stygies (192.168.1.47) to the Forgejo vhost.
            ip daddr ${hosts.cerberus} tcp dport { 443, 2222 } accept
            # Every cluster web UI on this VIP is reachable from the Hermes user over TCP 443.
            # The fix is a Traefik IP allowlist on the other routers, outside this VM's scope.
            ip daddr ${vips.traefik} tcp dport { 22, 443 } accept
            ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } counter drop
            # Block new non-loopback IPv6 traffic so it cannot bypass the LAN restrictions.
            # This also blocks IPv6 internet access if the VM gains IPv6 routing later.
            meta nfproto ipv6 counter drop
          }
        '';
      };
    };
  };

  # Match the NIC tofunix pins rather than relying on the kernel's interface name.
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:5a:6e:02";
    address = ["${hosts.stygies}/24"];
    gateway = [lan.gateway];
    dns = lan.resolvers;
    networkConfig.IPv6AcceptRA = false;
    linkConfig.RequiredForOnline = "routable";
  };

  services.resolved.settings.Resolve.FallbackDNS = [];
}
