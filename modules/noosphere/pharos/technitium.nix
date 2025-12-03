{self, ...}: {
  flake.nixosModules.noosphere = {config, lib, pkgs, ...}:
let
  serviceName = "technitium-dns-server";

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption toSentenceCase types;
    inherit (self.lib) mkRevProxyVHost mkDomain;

    cfg = config.services.imperium.${serviceName};
in
   {
     imports = [ imperiumBase ];

     options.services.imperium.${serviceName} = {
        firewallUDPPorts = mkOption {
          type = types.listOf types.port;
          default = [ 53 ];
          description = "List of UDP ports to open in firewall.";
        };

        firewallTCPPorts = mkOption {
          type = types.listOf types.port;
          default = [ 53 5380 53443 ];
          description = "List of TCP ports to open in firewall.";
        };

        dnsOverTLS = mkOption {
          type = types.bool;
          default = false;
          description = "Use DNS over TLS / HTTPS";
        };
     };

     config = mkIf cfg.enable {
        services.technitium-dns-server =  {
          enable = true;
          openFirewall = cfg.openFirewall;
          firewallUDPPorts = cfg.firewallUDPPorts;
          firewallTCPPorts = cfg.firewallTCPPorts ++ lib.optional cfg.dnsOverTLS [ 443 853 ];
        };

        services.caddy.virtualHosts."${mkDomain cfg.subdomain}" = {
          extraConfig = mkRevProxyVHost cfg.port;
        };
     };

  };

}
