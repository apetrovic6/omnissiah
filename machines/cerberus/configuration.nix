{
  self,
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (self.lib) mkRevProxyVHost mkDomain;
  baseDomain = config.clan.core.vars.generators."caddy-env".files."domain".value;
in {
  imports = [
    self.nixosModules.smb
    self.nixosModules.nfs
    self.nixosModules.postgresql
    self.nixosModules.scriptorium
    self.nixosModules.librarium
    self.nixosModules.impermanence
    ./nopresh.nix
    ./kaneo.nix
    ./forgejo-runner.nix
    ./dagger.nix
    # self.inputs.impermanence.nixosModules.impermanence
    # self.nixosModules.noosphere
    # self.inputs.magos.nixosModules.default
  ];
  boot.kernelModules = ["i915"];
  hardware.graphics.enable = true;

  environment.systemPackages = [
    (self.inputs.dagger-cli.packages.${pkgs.system}.dagger)
  ];

  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];

  networking.nameservers = ["192.168.1.105" "9.9.9.9"];

  # nixpkgs.overlays = [self.overlays.newt];
  services.qemuGuest.enable = true;
  nixpkgs.config.allowUnfree = true; # can't set with external pkgs from pkgsForSystem

  services.caddy.virtualHosts = {
    "${mkDomain "syn"}" = {
      extraConfig = mkRevProxyVHost {
        port = 5000;
        host = "192.168.1.61";
      };
    };
  };

  services.caddy.virtualHosts = {
    "${mkDomain "proxmox"}" = {
      extraConfig = ''
        reverse_proxy "https://192.168.1.10:8006" {
          transport http {
            tls_insecure_skip_verify
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN}
        }
      '';
    };
  };

  users.users.audiobookshelf.extraGroups = ["media"];

  services.imperium.audiobookshelf = {
    enable = true;
    port = 8008;
    group = "media";
    openFirewall = false;
    subdomain = "audiobookshelf";
  };

  services.imperium.immich = {
    enable = true;

    host = "0.0.0.0";
    port = 2283;
    openFirewall = true;

    database = {
      name = "immich";
      host = "127.0.0.1";
      port = 5432;
    };

    subdomain = "immich";

    user = "immich";
    group = "photos";
    mediaLocation = "/mnt/nas/photos/immich";
    accelerationDevices = ["/dev/dri/renderD128"];
  };

  services.imperium.plex = {
    enable = true;
    port = 32400; # This is just for Caddy, Plex doesn't expose a port option.
    openFirewall = true;
    user = "plex";
    group = "media";
    accelerationDevices = ["*"];
  };

  services.imperium.tautulli = {
    enable = true;
    group = "media";
    user = "plexpy";
    port = 8181;
  };

  users.users.plex.extraGroups = ["media"];

  # Pin the client WireGuard port so remote clients have a STABLE endpoint.
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
    # package = newtOverride;
    settings.endpoint = "https://ugalabugala.org";
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
          destination = "192.168.1.105";
          alias = "*.ugalabugala.org";
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
          destination = "192.168.1.105";
          alias = "plex.ugalabugala.org";
          site = siteCerberus;
          disable-icmp = true;
          tcp-ports = "443,80,53,2222,22,32400";
          udp-ports = "443,80,53,2222,22,32400";
          roles = ["plex"];
        };

        noosphere = {
          name = "Noosphere";
          mode = "host";
          destination = "192.168.1.251";
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

  services.imperium.nfs = let
    serverRoot = "/mnt/nas";
  in {
    enable = true;

    hosts.manjaca = let
      nasRoot = "/volume1";
    in {
      host = "192.168.1.61";

      exports.backup = {
        remotePath = "${nasRoot}/postgres_backup"; # path on the NAS
        mountPoint = "${serverRoot}/postgres_backup";
      };

      exports.git = {
        remotePath = "${nasRoot}/git";
        mountPoint = "${serverRoot}/git";
        nfsVersion = "3";
        extraOptions = ["nolock"];
      };

      exports.photos = {
        remotePath = "${nasRoot}/photos";
        mountPoint = "${serverRoot}/photos";
      };

      # exports.media = {
      #   remotePath = "/volume1/media";
      #   mountPoint = "/mnt/nas/media";
      # };

      # exports.selfhosted = {
      #   remotePath = "/volume1/selfhosted";
      #   mountPoint = "/mnt/nas/selfhosted";
      # };
    };
  };

  clan.core.state.hass = {
    folders = [
      "/var/lib/hass"
    ];

    preBackupScript = ''
      export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

        systemctl stop home-assistant.service
    '';

    postBackupScript = ''
        export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

      systemctl start home-assistant.service
    '';
  };

  clan.core.state.audiobookshelf = {
    folders = [
      "/var/lib/audiobookshelf/metadata/backups"
    ];

    preBackupScript = ''
      export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

        systemctl stop audiobookshelf.service
    '';

    postBackupScript = ''
        export PATH=${
        lib.makeBinPath [
          config.systemd.package
        ]
      }

      systemctl start audiobookshelf.service
    '';
  };

  # clan.core.postgresql.enable = true;

  # Write /var/lib/hass/secrets.yaml at runtime so Home Assistant can use !secret db_url.
  # Password comes from the clan var generated by services.imperium.postgresql above.
  # NOTE: Use an alphanumeric password (avoid @, /, %, etc.) to prevent URL-encoding issues.
  systemd.services.ha-secrets-init = {
    description = "Write Home Assistant secrets.yaml";
    before = ["home-assistant.service"];
    wantedBy = ["home-assistant.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.coreutils];
    script = let
      passwordFile = config.clan.core.vars.generators."postgresql-hass".files.password.path;
    in ''
      PASSWORD=$(cat ${passwordFile})
      printf 'db_url: "postgresql://hass:%s@localhost/hass"\n' "$PASSWORD" \
        > /var/lib/hass/secrets.yaml
      chown hass:hass /var/lib/hass/secrets.yaml
      chmod 0600 /var/lib/hass/secrets.yaml
    '';
  };

  users.users.immich.extraGroups = ["photos"];
  users.groups.photos = {
    gid = 65541;
  };

  users.users.postgres.extraGroups = ["backup"];
  users.groups.backup = {
    gid = 65539;
  };

  # nix = {
  #   extraOptions = ''
  #     !include ${config.clan.core.vars.generators.attic-pull-token.files.token.path}
  #     netrc-file = /home/apetrovic/.config/nix/netrc
  #   '';

  #   settings = {
  #     trusted-public-keys = [
  #       "manjo:NYye+6m7jUVm3d9GUoIjXeX55/sz9xnRP/gl8THza6k="
  #     ];
  #   };
  # };
  #

  services.imperium.smb.enable = true;

  users.users.forgejo.extraGroups = ["git"];
  users.groups.git = {
    gid = 65540;
  };

  services.imperium.forgejo = {
    enable = true;
    package = pkgs.forgejo;

    user = "forgejo";
    group = "git";

    stateDir = "/mnt/nas/git";

    port = 9000;
    host = "127.0.0.1";
    subdomain = "forge";
    domain = baseDomain;

    sshPort = 2222;
    startSshServer = true;

    database = {
      host = "127.0.0.1";
      name = "forgejo";
      user = "forgejo";
    };

    sso = {
      enable = false;
      providerName = "Pocket ID";
      autoDiscoverUrl = "https://id.noosphere.uk/.well-known/openid-configuration";
    };
  };

  services.imperium.impermanence = {
    enable = false; # TODO: Setup impermanence
  };

  # environment.persistence."/persist" = {
  #   enable = false;
  #   directories = [
  #     "/etc"
  #     "/var/spool"
  #     "/root"
  #     "/srv"
  #     "/var/lib/nixos"
  #     "/var/db/sudo/lectured"
  #     "/var/lib/systemd/coredump"
  #     "/etc/NetworkManager/system-connections"
  #   ];
  # };

  users.groups.media = {
    gid = 1337;
  };

  # services.xserver.videoDrivers = [ "intel" ];
  # hardware.enableAllFirmware = true;

  # services.xserver.videoDrivers = [ "intel" ];
  # hardware.intel-gpu-tools.enable = true;
  # boot.kernelModules = [ "i915" ];

  services.imperium.smb.hosts.manjaca = {
    host = "192.168.1.61";
    credentialsVarName = "manjaca-nas-credentials";

    shares.data = {
      mountPoint = "/mnt/nas/data";
      gid = 1337;
    };

    # shares.docker = {
    #   mountPoint = "/mnt/nas/docker";
    # };

    shares.selfhosted = {
      mountPoint = "/mnt/nas/selfhosted";
    };
  };

  nix = {
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 10d";
    };
    settings = {
      trusted-users = ["apetrovic"];
      auto-optimise-store = true;
    };
  };

  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = false;
    };
  };

  services.dbus.enable = true;

  services.home-assistant = let
    yaml = pkgs.formats.yaml {};
  in {
    enable = true;

    extraPackages = ps:
      with ps; [
        psycopg2
        pyipp
        hassil
        home-assistant-intents
        pyturbojpeg
        mutagen
        pymicro-vad
        pyspeex-noise
        habluetooth
        home-assistant-bluetooth
      ];

    # stream/cloud/go2rtc/mobile_app/camera omitted — stream fails on numpy 2.4.x double-load
    # (nixpkgs packaging issue: av bundled with HA is built against numpy ≤2.3).
    # default_config will log errors for those at startup but HA runs fine for everything else.
    extraComponents = [
      "analytics"
      "google_translate"
      "met"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"
      "ffmpeg"
      "bluetooth"
      "bluetooth_le_tracker"
      "mobile_app"
    ];

    configDir = "/var/lib/hass";
    configWritable = false;

    config = {
      http = {
        server_host = ["0.0.0.0"];
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = ["127.0.0.1" "::1"];
      };

      # default_config = {
      # };
      mobile_app = {};
      recorder.db_url = "!secret db_url";

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        time_zone = "Europe/Zagreb";
        temperature_unit = "C";
      };

      automation = [
        {
          alias = "Turn on lamp on sunset";
          description = "";
          mode = "single";
          triggers = [
            {
              trigger = "time";
              at = "21:00:00";
              weekday = ["mon" "tue" "wed" "thu" "fri" "sat" "sun"];
            }
          ];
          conditions = [];
          actions = [
            {
              type = "turn_on";
              device_id = "aec38ac4e11c2de001daeb6a1c9d7ca2";
              entity_id = "bd1206a71a6b20abb3d7ad3be3ef5698";
              domain = "light";
              brightness_pct = 15;
            }
          ];
        }

        {
          alias = "Turn off lamp before sleep";
          description = "";
          mode = "single";
          triggers = [
            {
              trigger = "time";
              at = "23:30:00";
              weekday = ["mon" "tue" "wed" "thu" "fri" "sat" "sun"];
            }
          ];
          conditions = [];
          actions = [
            {
              type = "turn_off";
              device_id = "aec38ac4e11c2de001daeb6a1c9d7ca2";
              entity_id = "bd1206a71a6b20abb3d7ad3be3ef5698";
              domain = "light";
              metadata.secondary = false;
            }
          ];
        }
      ];
    };
  };

  services.caddy.virtualHosts = {
    "${mkDomain "ha"}" = {
      extraConfig = mkRevProxyVHost {port = 8123;};
    };
  };

  # Pangolin/Newt routes all *.noosphere.uk traffic to this machine because it
  # shares a site VPN IP with ugala-bugala. Caddy catches it here and forwards
  # to the k8s MetalLB VIP (Traefik), preserving the original SNI so Traefik
  # can select the right certificate and Ingress route.
  services.caddy.virtualHosts = {
    "*.noosphere.uk" = {
      extraConfig = ''
        reverse_proxy https://192.168.1.251 {
          header_up Host {http.request.host}
          transport http {
            tls_server_name {http.request.host}
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN}
        }
      '';
    };
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
        reverse_proxy https://192.168.1.243 {
          header_up Host {http.request.host}
          transport http {
            tls_server_name {http.request.host}
          }
        }
        tls {
          dns cloudflare {$CLOUDFLARE_API_TOKEN_KEKSIC}
        }
      '';
    };
  };
}
