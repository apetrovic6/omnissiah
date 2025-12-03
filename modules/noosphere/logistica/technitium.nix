{self, ...}: {
  flake.nixosModules.noosphere = {config, lib, pkgs, ...}:
let
  serviceName = "tecnitium-dns-server";

    imperiumBase = import ../../rites/imperium-service.nix {
      inherit lib pkgs;
      name = serviceName;
    };

    inherit (lib) mkIf mkOption toSentenceCase;

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
          type = types.boolean;
          defalut = false;
          description = "Use DNS over TLS / HTTPS";
        };
     };

     config = mkIf cfg.enable {
        services.tecnitium-dns-server =  {
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
