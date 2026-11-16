# Taghmata, the RKE2 cluster.
#
# Two roles, and a machine may hold either or both:
#
#   fabricator  runs the control plane: RKE2 server, etcd, the ArgoCD chart,
#               the cluster's secret generators
#   skitarii    takes workloads: the storage helpers Longhorn and the NFS CSI
#               driver need on the host
#
# What a machine runs follows from the roles it holds:
#
#   fabricator + skitarii   RKE2 server that also schedules workloads
#   fabricator              RKE2 server, tainted so nothing else lands on it
#   skitarii                RKE2 agent
#
# Roles are assigned by the machine tags of the same name in
# inventory/machines.nix. Turning a control-plane/worker machine into a plain
# worker is therefore removing its `fabricator` tag. That is only the target
# state: on the machine itself the node still has to be drained, its etcd
# member removed and its server state cleared before it rejoins as an agent.
{lib, ...}: let
  inherit (lib) mkOption types optional optionalAttrs filterAttrs attrNames attrValues head;

  clusterName = "taghmata-omnissiah";
  supervisorPort = 9345;

  holds = roles: role: machine: (roles.${role}.machines or {}) ? ${machine.name};

  # Where a node registers with the cluster: the address set on the
  # fabricator role, or else the founder's.
  joinAddressOf = self: roles: let
    fabricators = roles.fabricator.machines or {};
    explicit = (head (attrValues fabricators)).settings.joinAddress;
    founders = attrNames (filterAttrs (_: machine: machine.settings.founder) fabricators);
  in
    if explicit != null
    then explicit
    else "https://${self.lib.hosts.${head founders}}:${toString supervisorPort}";

  # What every node needs, whichever roles it holds. Imported exactly once per
  # machine: by fabricator, or by skitarii on a machine that is not one.
  common = {
    pkgs,
    self,
    ...
  }: {
    imports = [
      self.nixosModules.noosphere
      self.nixosModules.taghmata
    ];

    nixpkgs.overlays = [self.overlays.rke2];

    services.rke2.package = pkgs.rke2_1_35;

    # Calico's VXLAN traffic arrives on an interface other than the one the
    # route table would pick for the source address, so strict reverse-path
    # filtering drops it.
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 0;
    };

    services.imperium.taghmata.rke2.registryCache = {
      enable = true;
      dockerProject = "docker_cache";

      # ghcr.io is deliberately NOT mirrored, to keep CNPG off Harbor.
      #
      # Harbor's own database is a CNPG cluster, so routing
      # ghcr.io/cloudnative-pg/* through Harbor makes Harbor a prerequisite for
      # starting the thing Harbor depends on. On 2026-10-02 that closed into a
      # deadlock: a node lost the Longhorn CSI driver, the Harbor DB primary
      # living on it could not restart, Harbor served nothing, and the node had
      # no working mirror to pull its way out. It took ~17 minutes to break out
      # on its own, via containerd's last-resort fallback to the upstream.
      #
      # This cannot be expressed as an exclusion: RKE2 mirror keys are
      # hostnames only, so the choice is per registry, not per repository.
      # ghcr.io costs little to give up -- 12 distinct images cluster-wide
      # against 63 on docker.io -- and four of those twelve are the CNPG ones
      # this is about.
      #
      # Still unbroken, and not fixable the same way: docker.io/goharbor/* and
      # docker.io/longhornio/* are the other two links, and dropping the
      # docker.io mirror wholesale is too high a price. Those need the images
      # preloaded on every node instead.
      ghcrProject = null;
    };
  };
in {
  _class = "clan.service";
  manifest.name = "taghmata";
  manifest.readme = "The taghmata RKE2 cluster: control-plane (fabricator) and workload (skitarii) nodes.";

  roles.fabricator = {
    description = "Control plane: RKE2 server and etcd member. Tainted unless the machine is also skitarii.";

    interface.options = {
      founder = mkOption {
        type = types.bool;
        default = false;
        description = ''
          The node that initialised the cluster. It is the one server with no
          join address, and where the others register unless `joinAddress` is
          set. Set it on one machine.
        '';
      };

      joinAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://192.168.1.240:9345";
        description = ''
          Supervisor address every other node registers with. Set it on the
          role, not on a machine. Default: the founder's address.

          It has to be set before the founder stops being a fabricator: a
          worker does not serve the supervisor port.
        '';
      };
    };

    perInstance = {
      settings,
      machine,
      roles,
      ...
    }: let
      worksToo = holds roles "skitarii" machine;
    in {
      nixosModule = {
        config,
        self,
        ...
      }: {
        imports = [
          common
          self.nixosModules.reliquary
        ];

        # A machine that is only a fabricator has none of skitarii's
        # NetworkManager exclusions, and needs this one.
        #
        # base turns on NetworkManager and clan-core turns on systemd-networkd,
        # so without it both run DHCP on the NIC and lease two different
        # addresses. The etcd peer cert gets the primary one while outbound
        # traffic leaves from the other, and the existing members reject the
        # join with `tls: "<ip>" does not match`. networkd alone owns the
        # wired link.
        #
        # Not networking.networkmanager.unmanaged: that lands in the main
        # NetworkManager.conf, and the rke2 module's conf.d/rke2-canal.conf
        # sets unmanaged-devices again, which replaces rather than merges.
        # This file sorts after it and appends with `+=`, keeping the CNI
        # exclusions.
        environment.etc = optionalAttrs (!worksToo) {
          "NetworkManager/conf.d/rke2-wired.conf".text = ''
            [keyfile]
            unmanaged-devices+=type:ethernet
          '';
        };

        services.rke2.autoDeployCharts.argo-cd = {
          enable = true;
          name = "argo-cd";
          repo = "https://argoproj.github.io/argo-helm";
          version = "10.9.6";
          hash = "sha256-btqQvdGN5ThRHJuayhynunocpbkZ9ZhxTQ6RzXFV0Rk=";
          createNamespace = true;
          targetNamespace = "argocd";

          values = {
            configs = {
              cm = {
                url = "https://argocd.${config.noosphere.domain}";
                "oidc.config" = ''
                  name: PocketID
                  issuer: https://${config.noosphere.sso.url}
                  clientID: $argo-oidc:client-id
                  clientSecret: $argo-oidc:client-secret
                  enablePKCEAuthentication: false
                  requestedScopes:
                    - openid
                    - profile
                    - email
                    - groups
                  logoutURL: https://${config.noosphere.sso.url}/api/oidc/end-session
                '';
              };

              params = {
                "server.insecure" = true;
              };

              rbac = {
                "policy.default" = "";
                scopes = "[groups]";
                "policy.csv" = ''
                  g, ArgoCDAdmins, role:admin
                  g, ArgoCDUsers, role:readonly
                '';
              };
            };
          };
        };

        services.imperium.taghmata.rke2.server =
          {
            enable = true;
            inherit clusterName;
            cni = "calico";
            multus = true;
            nodeLabels = [
              "role=control-plane"
              "cluster=${clusterName}"
            ];

            extraFlags = [
              "--ingress-controller=traefik"
            ];

            tokenFile = config.clan.core.vars.generators.taghmata-node-token.files.node-token.path;

            openFirewall = true;
          }
          // optionalAttrs (!settings.founder) {
            serverAddr = joinAddressOf self roles;
          }
          // optionalAttrs (!worksToo) {
            nodeTaints = ["node-role.kubernetes.io/control-plane=:NoSchedule"];
          };
      };
    };
  };

  roles.skitarii = {
    description = "Takes workloads. An RKE2 agent, unless the machine is also a fabricator.";

    interface.options = {};

    perInstance = {
      machine,
      roles,
      ...
    }: let
      commands = holds roles "fabricator" machine;
    in {
      nixosModule = {
        config,
        lib,
        pkgs,
        self,
        ...
      }: {
        imports = optional (!commands) common;

        services.tailscale = {
          enable = lib.mkForce false;
        };

        swapDevices = [
          {
            size = 50 * 1024;
            device = "/mnt/storage/swapFile";
          }
        ];

        systemd.services.iscsid.serviceConfig = {
          PrivateMounts = "yes";
          BindPaths = "/run/current-system/sw/bin:/bin";
        };

        # Make mount helpers visible in FHS-ish locations Longhorn expects via nsenter
        systemd.tmpfiles.rules = [
          "d /mnt/storage/garage 0755 root root -"
          "d /var/lib/nfs 0755 root root -"
          "d /var/lib/nfs/sm 0755 root root -"
          "d /var/lib/nfs/sm.bak 0755 root root -"
          "L+ /bin/mount - - - - ${pkgs.util-linux}/bin/mount"
          "L+ /usr/bin/mount - - - - ${pkgs.util-linux}/bin/mount"

          # NFS helper name can vary by distro; these two paths cover common expectations
          "L+ /sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"
          "L+ /usr/sbin/mount.nfs - - - - ${pkgs.nfs-utils}/bin/mount.nfs"

          # iSCSI tools for Longhorn volume attachment
          "L+ /sbin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"
          "L+ /usr/bin/iscsiadm - - - - ${pkgs.openiscsi}/bin/iscsiadm"

          # fstrim for Longhorn trimFilesystem action (nsenter uses this path)
          "L+ /usr/bin/fstrim - - - - ${pkgs.util-linux}/bin/fstrim"
        ];

        environment.systemPackages = with pkgs; [nfs-utils util-linux openiscsi cryptsetup];
        boot.kernelModules = ["iscsi_tcp" "dm_crypt"];

        services.rpcbind.enable = true;
        systemd.packages = [pkgs.nfs-utils];
        systemd.services.rpc-statd.wantedBy = ["multi-user.target"];

        services.openiscsi = {
          enable = true;
          name = "iqn.2005-10.org.open-iscsi:${config.networking.hostName}";
        };

        networking.interfaces.enp2s0.useDHCP = false;

        # Prevent NetworkManager from managing k8s node interfaces
        environment.etc."NetworkManager/conf.d/storage-network.conf".text = ''
          [keyfile]
          unmanaged-devices=interface-name:enp2s0;interface-name:enp1s0
        '';

        # No autoDeployCharts or manifests on an agent: charts and manifests
        # are applied by server nodes only.
        #
        # Not exercised yet: every skitarii is still a fabricator, so this
        # has only ever been evaluated, never run.
        services.imperium.taghmata.rke2.agent = lib.mkIf (!commands) {
          enable = true;
          inherit clusterName;
          serverAddr = joinAddressOf self roles;
          tokenFile = config.clan.core.vars.generators.taghmata-node-token.files.node-token.path;
          nodeLabels = [
            "role=worker"
            "cluster=${clusterName}"
          ];
          openFirewall = true;
        };
      };
    };
  };
}
