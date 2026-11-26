# Caddy hosts for things that are not services of this machine: the NAS,
# Proxmox, and the wildcard forwards to the cluster and to keksic.
args @ {
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;
  # The slot inventory (modules/rites/_ci-slots.nix); fixtures pass their own.
  slotHosts = builtins.attrValues (args.ciSlots or self.lib.ciSlots);
  sources = kind: map (host: self.lib.lan.${host.egress.${kind}}) (builtins.filter (host: (host.egress.${kind} or null) != null) slotHosts);
  trustedSources = sources "trusted";
  guard = args.ciGuard or self.lib.ciGuard;
  s3Host = "${self.lib.sccacheCiKey.endpointPrefix}.${config.noosphere.domain}";
  # Trusted runs only (README "Trusted slot egress"): the untrusted names
  # plus Garage S3 (path style), Harbor and ntfy.
  # Empty without trusted sources, so the snippet stays byte-identical.
  trustedMatcher = lib.optionalString (trustedSources != []) (lib.concatMapStrings (line: "\n" + line) [
    ""
    "  @blockedEphemeralTrusted {"
    "    remote_ip ${lib.concatStringsSep " " trustedSources}"
    "    not host ${mkDomain "forge"} ncps.${config.noosphere.domain} forge.${config.noosphere.domain} ${s3Host} harbor.${config.noosphere.domain} ${mkDomain "ntfy"}"
    "  }"
    "  respond @blockedEphemeralTrusted 403"
  ]);
in {
  # TODO: Setup services so that they listen on localhost

  networking.firewall.allowedTCPPorts = [80 443 2222 53 22 8123];
  networking.firewall.allowedUDPPorts = [80 443 53 222];
  # Or disable the firewall altogether.
  networking.firewall.enable = true;

  imports = [
    {
      # Extend the vhost type so services adding a host inherit the same guard.
      options.services.caddy.virtualHosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          config.extraConfig = lib.mkBefore "invoke stygies-access";
        });
      };
    }
  ];

  # Slot guests reach only this host on the LAN (guard in _ci-slots.nix).
  assertions = [
    {
      assertion = guard == config.networking.hostName;
      message = "The nix-eph egress guard (_ci-slots.nix guard = \"${guard}\") must carry this Caddy guard; move it with the setting.";
    }
  ];

  services.imperium.caddy = {
    enable = true;
    openFirewall = true;
    package = pkgs.caddy.withPlugins {
      plugins = ["github.com/caddy-dns/cloudflare@v0.2.3"];
      hash = "sha256-OIQoJ+Q7rfJkoy/H01L2lEDysOlYzl63s6pOrSj9LlQ=";
    };
  };

  services.caddy = {
    # Check the socket peer before any site handler can proxy or respond.
    globalConfig = "order invoke first";
    # @blockedEphemeral matches every nix-eph slot host's untrusted source
    # address (modules/rites/_ci-slots.nix), @blockedEphemeralTrusted the
    # trusted ones, if any.
    extraConfig = ''
      &(stygies-access) {
        @blocked {
          remote_ip ${self.lib.hosts.stygies}
          not host ${mkDomain "forge"} ncps.${config.noosphere.domain} harbor.${config.noosphere.domain} forge.${config.noosphere.domain}
        }
        respond @blocked 403

        # Protect the slot source even if Ryza is on a different generation.
        @blockedEphemeral {
          remote_ip ${lib.concatStringsSep " " (sources "untrusted")}
          not host ${mkDomain "forge"} ncps.${config.noosphere.domain} forge.${config.noosphere.domain}
        }
        respond @blockedEphemeral 403${trustedMatcher}
      }
    '';
  };

  services.caddy.virtualHosts = {
    "${mkDomain "syn"}" = {
      extraConfig = mkRevProxyVHost {
        port = 5000;
        host = self.lib.hosts.manjaca;
      };
    };
  };

  services.caddy.virtualHosts = {
    "${mkDomain "proxmox"}" = {
      extraConfig = ''
        reverse_proxy "https://${self.lib.hosts.proxmox}:8006" {
          transport http {
            tls_insecure_skip_verify
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN}
          # Same reason as mkRevProxyVHost in modules/litanies/default.nix:
          # the local Technitium is authoritative for this zone and never has
          # the _acme-challenge TXT.
          resolvers 1.1.1.1 1.0.0.1
        }
      '';
    };
  };

  # Pangolin/Newt routes all *.noosphere.uk traffic to this machine because it
  # shares a site VPN IP with ugala-bugala. Caddy catches it here and forwards
  # to the k8s MetalLB VIP (Traefik), preserving the original SNI so Traefik
  # can select the right certificate and Ingress route.
  services.caddy.virtualHosts = {
    "*.noosphere.uk" = {
      extraConfig = ''
        reverse_proxy https://${self.lib.vips.traefik} {
          header_up Host {http.request.host}
          transport http {
            tls_server_name {http.request.host}
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN}
          # noosphere.uk is a Technitium primary zone on this host too — see
          # modules/litanies/default.nix.
          resolvers 1.1.1.1 1.0.0.1
        }
      '';
    };
  };

  # Garage S3 for trusted nix-eph runs (README "Trusted slot egress"). Four
  # labels, so `*.noosphere.uk` (one label) never matched it; LAN clients
  # resolve it straight to the VIP. Only the trusted slot sources may use
  # this vhost: everyone else reaching Caddy here (LAN, Pangolin/VPN, the
  # untrusted .249) gets 403, so S3 is not newly exposed through Cerberus.
  services.caddy.virtualHosts.${s3Host} = lib.mkIf (trustedSources != []) {
    extraConfig = ''
      @notTrustedCI not remote_ip ${lib.concatStringsSep " " trustedSources}
      respond @notTrustedCI 403
      reverse_proxy https://${self.lib.vips.traefik} {
        header_up Host {http.request.host}
        transport http {
          tls_server_name {http.request.host}
        }
      }
      tls {
        dns cloudflare {$CLOUDFLARE_API_TOKEN}
        # As for *.noosphere.uk above.
        resolvers 1.1.1.1 1.0.0.1
      }
    '';
  };

  # keksic.xyz is on a separate Cloudflare account — needs its own token.
  clan.core.vars.generators."caddy-keksic" = {
    files."keksic.env" = {
      secret = true;
      owner = config.services.caddy.user;
      group = config.services.caddy.group;
      mode = "0400";
    };
    prompts.token = {
      description = "Cloudflare API token for keksic.xyz DNS-01 challenge";
      type = "hidden";
      persist = true;
    };
    runtimeInputs = [pkgs.coreutils];
    script = ''
            token="$(cat "$prompts/token")"
            cat > "$out/keksic.env" <<EOF
      CLOUDFLARE_API_TOKEN_KEKSIC=$token
      EOF
    '';
  };

  # Inject the keksic token alongside the existing caddy.env.
  systemd.services.caddy.serviceConfig.EnvironmentFile = lib.mkForce [
    config.services.caddy.environmentFile
    config.clan.core.vars.generators."caddy-keksic".files."keksic.env".path
  ];

  # Pangolin non-deterministically routes the shared VPN IP to either the
  # cerberus or keksic site peer depending on the client. Cerberus Caddy
  # proxies keksic.xyz on to the keksic VM for clients that land here.
  services.caddy.virtualHosts = {
    "*.keksic.xyz" = {
      extraConfig = ''
        reverse_proxy https://${self.lib.hosts.keksic} {
          header_up Host {http.request.host}
          transport http {
            tls_server_name {http.request.host}
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN_KEKSIC}
          # keksic.xyz is a Technitium primary zone on this host too — see
          # modules/litanies/default.nix.
          resolvers 1.1.1.1 1.0.0.1
        }
      '';
    };
  };
}
