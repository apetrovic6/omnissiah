# Eval check for the slot's directories (HOM-30 live fix). Runs as the flake
# check checks.x86_64-linux.forgejo-ephemeral-jobdir; by hand:
#   nix eval --impure --json .#nixosConfigurations.ryza --apply \
#     'ryza: import ./modules/rites/_forgejo-ephemeral-jobdir-test.nix { inherit ryza; }'
#
# systemd builds a mount namespace for every Exec*= process, '+' ones
# included (they still get ReadWritePaths=), and chdirs into
# WorkingDirectory=. A missing non-'-' path fails that process with
# 226/NAMESPACE or 200/CHDIR. A mandatory path is "/" or created before
# startup by the required installer or the ordered tmpfiles service.
# An optional '-' path missing at start stays read-only, so the dispatcher
# must not use such paths for writes.
{ryza}: let
  inherit (ryza.pkgs) lib;
  inventory = ryza.config.services.imperium.forgejoEphemeral.inventory;
  host = inventory.ryza;
  withPools = pools:
    ryza.extendModules {
      modules =
        [
          {
            services.imperium.forgejoEphemeral = {
              enable = lib.mkForce true;
              pools = lib.mkForce pools;
              inventory =
                inventory
                // {
                  ryza =
                    host
                    // {
                      slots =
                        host.slots
                        // {
                          ryza-eph-2 =
                            host.slots.ryza-eph-1
                            // {
                              index = 2;
                              class = "large";
                            };
                        };
                    };
                };
            };
            clan.core.vars.generators.forgejo-ephemeral-ugalabugala.files.token.path = lib.mkForce "/run/secrets/ephemeral-test-pat";
          }
        ]
        ++ lib.optional (lib.any (pool: pool.forge == "noosphere") (builtins.attrValues pools)) {
          clan.core.vars.generators.forgejo-ephemeral-noosphere.files.token.path = lib.mkForce "/run/secrets/noosphere-test-pat";
        };
    };
  pilotPools.ugalabugala = builtins.removeAttrs pilot ["host" "login" "maxSlots"];
  enabled = withPools pilotPools;
  c = enabled.config;
  multiPool =
    (withPools (pilotPools
      // {
        noosphere = {
          forge = "noosphere";
          scope.user = "noosphere-ci";
          labels = ["nix-eph" "nix-nightly"];
          dispatch = [7];
          maxSlots = 1;
        };
        monolith-softworks = {
          forge = "noosphere";
          scope.org = "monolith-softworks";
          labels = ["nix-eph"];
          dispatch = "owner";
          trust = {
            repos."42" = {
              owner = "Monolith-Softworks";
              name = "inanna";
            };
            users = ["manjo"];
          };
        };
      })).config;
  poolsFor = machine: builtins.fromJSON machine.services.imperium.forgejoEphemeral.internal.poolsFile.text;
  pilot = {
    forge = "ugalabugala";
    host = "forge.ugalabugala.org";
    login = "manjo";
    scope.user = "manjo";
    labels = ["nix-eph"];
    dispatch = [9];
    maxSlots = 1;
    trust = {
      repos."9" = {
        owner = "manjo";
        name = "rust-app-template";
        schedules = false;
      };
      users = ["manjo"];
    };
  };
  patGenerators = machine: builtins.filter (lib.hasPrefix "forgejo-ephemeral-") (builtins.attrNames machine.clan.core.vars.generators);
  dispatcherCredentials = machine: machine.systemd.services.${dispatchTemplate}.serviceConfig.LoadCredential;
  multiPools = poolsFor multiPool;
  persistent = ryza.extendModules {
    modules = [{services.imperium.forgejoEphemeral.enable = lib.mkForce false;}];
  };
  split = enabled.extendModules {
    modules = [
      {
        services.imperium.forgejoEphemeral.inventory = lib.mkForce {
          ryza = host;
          terra = host // {slots.terra-eph-1 = host.slots.ryza-eph-1;};
        };
      }
    ];
  };
  trusted = enabled.extendModules {
    modules = [{services.imperium.forgejoEphemeral.trustedJobs.enable = lib.mkForce true;}];
  };
  trustedConfig = trusted.config;
  # One extra pool on the enabled fixture; for assertions, option types and PAT prompts.
  withPool = pool:
    (withPools (pilotPools // {extra = pool;})).config;
  failsWith = machine: message: lib.any (check: check.message == message && !check.assertion) machine.assertions;
  noosphereUser = {
    forge = "noosphere";
    scope.user = "manjo";
    labels = ["nix-eph"];
    dispatch = [7];
  };
  inanna = {
    owner = "manjo";
    name = "inanna";
  };
  prompt = machine: forge: machine.clan.core.vars.generators."forgejo-ephemeral-${forge}".prompts.token.description;
  trustedSlotctlSlots = trustedConfig.services.imperium.forgejoEphemeral.internal.slotctlSlots;
  configuredSlots = builtins.attrNames c.services.imperium.forgejoEphemeral.inventory.ryza.slots;
  services = c.systemd.services;
  inherit (c.services.imperium.forgejoEphemeral.internal) slots slotctlSlots remotePropertyNames;
  # These service properties are accepted by systemd-run on the slot host.
  # Static-unit-only settings such as JobTimeoutSec must not reach this list.
  transientAllowlist = [
    "After"
    "CapabilityBoundingSet"
    "Group"
    "IPAddressDeny"
    "InaccessiblePaths"
    "LimitCORE"
    "NoNewPrivileges"
    "PrivateTmp"
    "ProtectHome"
    "ProtectSystem"
    "ReadWritePaths"
    "Requires"
    "RestrictAddressFamilies"
    "RuntimeMaxSec"
    "TimeoutStopSec"
    "UMask"
    "User"
  ];
  dispatchTemplate = "forgejo-ephemeral-dispatcher@";
  claims = "/run/forgejo-ephemeral/claims";
  lockRoot = "/run/forgejo-slotctl";
  checkSlot = slot: internal: let
    vmName = "microvm@${slot}";
    install = "install-microvm-${slot}";
    installUnit = "${install}.service";
    slotctl = slotctlSlots.${slot};
    trustedSlotctl = trustedSlotctlSlots.${slot};
    credParent =
      if slot == "ryza-eph-1"
      then "/run/microvm-credentials"
      else "/run/microvm-credentials/forgejo-${slot}";
    control = "${c.microvm.stateDir}/${slot}";
    job = "${control}/job";
    trustDir = "${credParent}/${slot}-trust";
    writable = path:
      lib.any (rw: path == rw || lib.hasPrefix "${rw}/" path) dispatcher.serviceConfig.ReadWritePaths;
    isTrustShare = share: share.tag == "ci-trust";
    trustShare = lib.findFirst isTrustShare null trustedConfig.microvm.vms.${slot}.config.config.microvm.shares;
    installer = services.${install};
    dispatchName = "${dispatchTemplate}${slot}";
    dispatchDefinition = services.${dispatchName};
    dispatcher = instance dispatchName;
    vm = services.${vmName};
    prepares = installer.serviceConfig.ExecStartPre;
    prepare = builtins.head prepares;
    # Instances are drop-ins over upstream templates; merge the two views.
    instance = name: let
      template = services."${lib.head (lib.splitString "@" name)}@" or {};
      base = template.serviceConfig or {};
      overrides = services.${name}.serviceConfig;
      paths = attrs: field: attrs.${field} or [];
      merged =
        base
        // overrides
        // {
          ReadWritePaths = paths base "ReadWritePaths" ++ paths overrides "ReadWritePaths";
          InaccessiblePaths = paths base "InaccessiblePaths" ++ paths overrides "InaccessiblePaths";
        };
    in {
      inherit name;
      requires = (template.requires or []) ++ services.${name}.requires;
      after = (template.after or []) ++ services.${name}.after;
      serviceConfig = lib.mapAttrs (_: v:
        if builtins.isString v
        then builtins.replaceStrings ["%i"] [slot] v
        else if builtins.isList v
        then map (builtins.replaceStrings ["%i"] [slot]) v
        else v)
      merged;
    };
    units = map instance [install vmName "microvm-set-booted@${slot}" "microvm-virtiofsd@${slot}" dispatchName];
    namespacePaths = s:
      [(s.WorkingDirectory or "/")] ++ (s.ReadWritePaths or []) ++ (s.InaccessiblePaths or []);
    mandatory = paths: builtins.filter (path: !(lib.hasPrefix "-" path)) paths;
    # What the installer really creates: the module's list, checked below
    # against the script's install lines (an edit that drops one must fail).
    created = map (dir: dir.path) internal.slotDirs;
    scriptLines = lib.splitString "\n" internal.prepareDirs.text;
    installLines = builtins.filter (lib.hasPrefix ''"$install" -d'') scriptLines;
    expectedLines = map (dir: ''"$install" -d -o ${dir.owner} -g ${dir.group} -m ${dir.mode} -- ${dir.path}'') internal.slotDirs;
    symlinkCheck = "for dir in ${lib.concatStringsSep " " created}; do";
    orderedAfterInstaller = u:
      builtins.elem installUnit u.requires
      && (builtins.elem installUnit u.after || builtins.elem "${u.name}.service" installer.before);
    beforeNamespace = u: path:
      (builtins.elem path created && orderedAfterInstaller u)
      || (path
        == claims
        && u.name == dispatchName
        && builtins.elem "systemd-tmpfiles-setup.service" u.after
        && builtins.elem "d ${path} 0700 root root - -" c.systemd.tmpfiles.rules);
    unsafe = u:
      builtins.filter (path: path != "/" && !(beforeNamespace u path))
      (mandatory (namespacePaths u.serviceConfig));
    violations = lib.filterAttrs (_: v: v != []) (lib.listToAttrs (map (u: lib.nameValuePair u.name (unsafe u)) units));
    dispatcherOptional = builtins.filter (lib.hasPrefix "-") (dispatcher.serviceConfig.ReadWritePaths or []);
    settings = c.systemd.tmpfiles.settings."10-microvm";
    guest = c.microvm.vms.${slot}.config.config;
    guestFs = guest.fileSystems."/nix/.ro-store";
    guestRunner = guest.systemd.services.forgejo-one-job;
    minutes = value: lib.toInt (builtins.head (builtins.match "([0-9]+)min" value));
    deadline = {
      runner = internal.runnerMinutes;
      guest = minutes guestRunner.serviceConfig.RuntimeMaxSec;
      host = minutes vm.serviceConfig.RuntimeMaxSec;
    };
    expected =
      if slot == "ryza-eph-1"
      then {
        runner = 180;
        guest = 185;
        host = 190;
        overlayGiB = 50;
      }
      else {
        runner = 360;
        guest = 365;
        host = 370;
        overlayGiB = 150;
      };
    estimate = deadline.host * 60 + 90 + 30;
    gib = 1024 * 1024 * 1024;
    guestCredentials = ["job-handle" "runner-token" "runner-uuid"];
    guestDNS = builtins.head guest.systemd.network.networks."10-uplink".dns;
    poolPath = c.services.imperium.forgejoEphemeral.internal.poolsFile;
    vmStop = services."microvm@".serviceConfig.ExecStopPost ++ vm.serviceConfig.ExecStopPost;
    peers = builtins.filter (peer: peer != slot) (builtins.attrNames slots);
    peerPaths = lib.concatMap (peer: let
      peerCredentials = slotctlSlots.${peer}.credential_dir;
      peerParent = builtins.dirOf peerCredentials;
    in
      [
        "-${peerCredentials}"
        "-${slotctlSlots.${peer}.trust_dir}"
        "-${builtins.dirOf slotctlSlots.${peer}.vm_dir}"
      ]
      ++ lib.optional (peerParent != "/run/microvm-credentials") "-${peerParent}")
    peers;
  in
    assert lib.assertMsg (violations == {}) "mandatory namespace paths not created first: ${builtins.toJSON violations}";
    assert lib.assertMsg (dispatcherOptional == []) "dispatcher has optional writable paths: ${toString dispatcherOptional}";
    assert lib.assertMsg (lib.all (name: builtins.elem name transientAllowlist) remotePropertyNames.${slot})
    "unsupported transient service property in ${slot}: ${toString remotePropertyNames.${slot}}";
    assert builtins.elem "f ${lockRoot}/${slot}.lock 0600 root root - -" c.systemd.tmpfiles.rules;
    assert credParent == "/run/microvm-credentials" || builtins.elem "d ${credParent} 0755 root root - -" c.systemd.tmpfiles.rules;
    assert lib.sort builtins.lessThan dispatcher.serviceConfig.ReadWritePaths == lib.sort builtins.lessThan [claims credParent job];
    assert dispatchDefinition.overrideStrategy == "asDropin";
    assert builtins.elem "multi-user.target" dispatchDefinition.wantedBy;
    assert builtins.elem "${dispatchName}.service" services.${dispatchTemplate}.aliases;
    assert lib.hasInfix (builtins.unsafeDiscardStringContext "--pools ${poolPath} ") (builtins.unsafeDiscardStringContext dispatcher.serviceConfig.ExecStart);
    assert !(lib.hasInfix "--trusted-jobs" dispatcher.serviceConfig.ExecStart);
    assert lib.hasSuffix " --trusted-jobs" trustedConfig.systemd.services.${dispatchName}.serviceConfig.ExecStart;
    assert deadline.runner < deadline.guest && deadline.guest < deadline.host;
    assert deadline == builtins.removeAttrs expected ["overlayGiB"];
    assert lib.hasSuffix " --vm-deadline ${toString estimate}" dispatcher.serviceConfig.ExecStart;
    assert (lib.findFirst (volume: volume.image == "nix-store-overlay.img") null guest.microvm.volumes).size == expected.overlayGiB * 1024;
    assert guest.nix.settings.min-free == expected.overlayGiB / 5 * gib;
    assert guest.nix.settings.max-free == expected.overlayGiB / 2 * gib;
    assert slotctl.min_free_bytes == (expected.overlayGiB + 20 + 10) * gib;
    assert lib.all (path:
      builtins.elem path vm.serviceConfig.InaccessiblePaths
      && builtins.elem path dispatcher.serviceConfig.InaccessiblePaths)
    peerPaths;
    # The installer creates the directories with no slot directory present.
    assert installer.unitConfig.RequiresMountsFor == [c.microvm.stateDir];
    assert prepare == "+${internal.prepareDirs}";
    assert lib.assertMsg (installLines == expectedLines) "prepare-dirs creates ${builtins.toJSON installLines}, expected ${builtins.toJSON expectedLines}";
    assert builtins.elem symlinkCheck scriptLines;
    # Parents first: each directory's parent exists or is created before it.
    assert lib.all (i: let
      parent = builtins.dirOf (builtins.elemAt created i);
    in
      !(builtins.elem parent created) || lib.lists.findFirstIndex (p: p == parent) null created < i)
    (lib.range 0 (builtins.length created - 1));
    # Manual restarts must not rate-limit the installer (start-limit-hit).
    assert (installer.unitConfig.StartLimitIntervalSec or null) == 0;
    # QEMU needs no kvm group (the devices are 0666); keep it out of 0775 microvm:kvm dirs.
    assert !(builtins.elem "kvm" c.users.users.${slotctlSlots.${slot}.user}.extraGroups)
    && c.users.users.${slotctlSlots.${slot}.user}.group == slotctlSlots.${slot}.group;
    # The slot unit also repairs them first, before its sandboxed preflight.
    assert builtins.head vm.serviceConfig.ExecStartPre == prepare;
    assert mandatory (namespacePaths vm.serviceConfig) == [];
    # No bind mount on the credentials dir the '+' scrub removes (EBUSY).
    assert !(lib.any (lib.hasInfix "${credParent}/${slot}") vm.serviceConfig.ReadWritePaths);
    assert lib.all (lib.hasPrefix "+") vmStop;
    # tmpfiles: nothing under the microvm-owned state dir that changes owner.
    assert !((settings.${control} or {}) ? d) && !(builtins.hasAttr job settings);
    # Guest lower store is mounted ro, after "defaults".
    assert lib.last guestFs.options == "ro";
    assert guest.microvm.credentialFiles == lib.genAttrs guestCredentials (id: "${slotctl.credential_dir}/${id}");
    assert lib.sort builtins.lessThan guestRunner.serviceConfig.LoadCredential == guestCredentials;
    assert lib.hasInfix "--url https://forge.ugalabugala.org " guestRunner.script && lib.hasInfix "--label nix-eph:host " guestRunner.script;
    assert guest.networking.hosts.${guestDNS} == ["forge.ugalabugala.org" "ncps.noosphere.uk"];
    # The dispatcher can modify this slot's directories, not a peer's.
    assert slotctl.vm_dir == job && slotctl.credential_dir == "${credParent}/${slot}";
    assert slotctl.fixed_pilot;
    assert lib.all writable [slotctl.vm_dir slotctl.credential_dir slotctl.trust_dir];
    # Cleanup always has a trust path; only the trusted fixture permits delivery.
    assert slotctl.trust_dir == trustDir && !slotctl.deliver && trustedSlotctl.deliver;
    assert trustedSlotctl == (slotctl // {deliver = true;});
    assert !(lib.any isTrustShare c.microvm.vms.${slot}.config.config.microvm.shares);
    assert trustShare != null && trustShare.source == trustedSlotctl.trust_dir; {
      inherit (dispatcher.serviceConfig) StateDirectory RuntimeDirectory;
      inherit (vm.serviceConfig) Slice User;
      guestDrv = c.microvm.vms.${slot}.config.config.system.build.toplevel.drvPath;
      inherit prepare created installLines;
      inherit deadline estimate;
      inherit slotctl trustedSlotctl;
      transientProperties = remotePropertyNames.${slot};
      prepareDrv = builtins.attrNames (builtins.getContext prepare);
      scrubDrv = builtins.attrNames (builtins.getContext (lib.last vmStop));
      vmExecStartPre = vm.serviceConfig.ExecStartPre;
      vmWorkingDirectory = vm.serviceConfig.WorkingDirectory;
      vmReadWritePaths = vm.serviceConfig.ReadWritePaths;
      vmExecStopPost = vmStop;
      dispatcherReadWritePaths = dispatcher.serviceConfig.ReadWritePaths;
      dispatcherRequires = dispatcher.requires;
      dispatcherAfter = dispatcher.after;
      installerBefore = installer.before;
      roStoreOptions = guestFs.options;
      tmpfilesSlot = settings.${control} or null;
      tmpfilesRules = builtins.filter (lib.hasInfix "microvm-credentials") c.systemd.tmpfiles.rules;
    };
  results = lib.mapAttrs checkSlot slots;
  uniqueBy = field:
    lib.length (lib.unique (lib.mapAttrsToList (_: slot: slot.${field}) results)) == lib.length (builtins.attrNames slots);
  dynamicSlot = multiPool.services.imperium.forgejoEphemeral.internal.slotctlSlots.ryza-eph-1;
  dynamicGuest = multiPool.microvm.vms.ryza-eph-1.config.config;
  dynamicRunner = dynamicGuest.systemd.services.forgejo-one-job;
  dynamicDNS = builtins.head dynamicGuest.systemd.network.networks."10-uplink".dns;
  dynamicCredentials = ["forgejo-url" "job-handle" "runner-label" "runner-token" "runner-uuid"];
in
  assert persistent.config.microvm.host.enable;
  assert patGenerators persistent.config == [];
  assert poolsFor c == {ugalabugala = pilot // {maxSlots = 2;};};
  assert !ryza.config.services.imperium.forgejoEphemeral.trustedJobs.enable;
  assert patGenerators c == ["forgejo-ephemeral-ugalabugala"];
  assert prompt c "ugalabugala" == "Forgejo dispatcher PAT for manjo on forge.ugalabugala.org (Public only; write:user only)";
  assert lib.all (check: check.assertion) multiPool.assertions;
  # Review M1/L2: trust needs users, trusted repos must be dispatched, dispatch lists are nonempty.
  assert failsWith (withPool (noosphereUser // {trust.repos."7" = inanna;}))
  "forgejoEphemeral: pool extra lists trusted repos, so trust.users must not be empty.";
  assert failsWith (withPool (noosphereUser
    // {
      trust = {
        repos."8" = inanna;
        users = ["manjo"];
      };
    }))
  "forgejoEphemeral: every trusted repo of pool extra must also be in its dispatch list.";
  assert lib.all (check: check.assertion)
  (withPool (noosphereUser
    // {
      trust = {
        repos."7" = inanna;
        users = ["manjo"];
      };
    })).assertions;
  assert !(builtins.tryEval (builtins.deepSeq (withPool (noosphereUser // {dispatch = [];})).services.imperium.forgejoEphemeral.pools.extra.dispatch true)).success;
  assert (poolsFor (withPool (noosphereUser
    // {
      trust = {
        repos."7" = inanna // {schedules = true;};
        users = ["manjo"];
      };
    }))).extra.trust.repos."7".schedules;
  # Review L3: Public only unless the forge has an org pool; read:repository only with trust on.
  assert prompt (withPool noosphereUser) "noosphere" == "Forgejo dispatcher PAT for manjo on forge.noosphere.uk (Public only; write:user only)";
  assert prompt multiPool "noosphere" == "Forgejo dispatcher PAT for noosphere-ci on forge.noosphere.uk (write:user and write:organization)";
  assert prompt trustedConfig "ugalabugala" == "Forgejo dispatcher PAT for manjo on forge.ugalabugala.org (Public only; write:user and read:repository)";
  assert !dynamicSlot.fixed_pilot;
  assert dynamicGuest.microvm.credentialFiles == lib.genAttrs dynamicCredentials (id: "${dynamicSlot.credential_dir}/${id}");
  assert lib.sort builtins.lessThan dynamicRunner.serviceConfig.LoadCredential == dynamicCredentials;
  assert lib.hasInfix ''--url "$url"'' dynamicRunner.script && lib.hasInfix ''--label "$label:host"'' dynamicRunner.script;
  assert dynamicGuest.networking.hosts.${dynamicDNS} == ["forge.ugalabugala.org" "ncps.noosphere.uk" "forge.noosphere.uk"];
  assert multiPools
  == {
    ugalabugala = pilot // {maxSlots = 2;};
    noosphere = {
      forge = "noosphere";
      host = "forge.noosphere.uk";
      login = "noosphere-ci";
      scope.user = "noosphere-ci";
      labels = ["nix-eph" "nix-nightly"];
      dispatch = [7];
      maxSlots = 1;
      trust = {
        repos = {};
        users = [];
      };
    };
    monolith-softworks = {
      forge = "noosphere";
      host = "forge.noosphere.uk";
      login = "noosphere-ci";
      scope.org = "monolith-softworks";
      labels = ["nix-eph"];
      dispatch = "owner";
      maxSlots = 2;
      trust = {
        repos."42" = {
          owner = "Monolith-Softworks";
          name = "inanna";
          schedules = false;
        };
        users = ["manjo"];
      };
    };
  };
  assert patGenerators multiPool == ["forgejo-ephemeral-noosphere" "forgejo-ephemeral-ugalabugala"];
  assert dispatcherCredentials c == ["forgejo-pat-ugalabugala:/run/secrets/ephemeral-test-pat"];
  assert lib.sort builtins.lessThan (dispatcherCredentials multiPool)
  == [
    "forgejo-pat-noosphere:/run/secrets/noosphere-test-pat"
    "forgejo-pat-ugalabugala:/run/secrets/ephemeral-test-pat"
  ];
  assert lib.any (check:
    check.message
    == "forgejoEphemeral: every inventory entry must use the same dispatcher machine."
    && !check.assertion)
  split.config.assertions;
  assert builtins.attrNames slots == configuredSlots;
  assert builtins.attrNames slotctlSlots == configuredSlots;
  assert builtins.attrNames trustedSlotctlSlots == configuredSlots;
  assert lib.all uniqueBy ["StateDirectory" "RuntimeDirectory" "Slice" "User"]; {
    hostDrv = c.system.build.toplevel.drvPath;
    pools = multiPools;
    slots = results;
  }
