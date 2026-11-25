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
  enabled = ryza.extendModules {
    modules = [
      {
        services.imperium.forgejoEphemeral = {
          enable = lib.mkForce true;
          repoId = lib.mkForce 4242;
          inventory =
            inventory
            // {
              ryza =
                host
                // {
                  slots =
                    host.slots
                    // {
                      ryza-eph-2 = host.slots.ryza-eph-1 // {index = 2;};
                    };
                };
            };
        };
        clan.core.vars.generators.forgejo-ephemeral-ugalabugala.files.token.path = lib.mkForce "/run/secrets/ephemeral-test-pat";
      }
    ];
  };
  c = enabled.config;
  trusted = enabled.extendModules {
    modules = [{services.imperium.forgejoEphemeral.trustedJobs.enable = lib.mkForce true;}];
  };
  trustedConfig = trusted.config;
  trustedSlotctlSlots = trustedConfig.services.imperium.forgejoEphemeral.internal.slotctlSlots;
  configuredSlots = builtins.attrNames c.services.imperium.forgejoEphemeral.inventory.ryza.slots;
  services = c.systemd.services;
  inherit (c.services.imperium.forgejoEphemeral.internal) slots slotctlSlots;
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
    guestFs = c.microvm.vms.${slot}.config.config.fileSystems."/nix/.ro-store";
    vmStop = services."microvm@".serviceConfig.ExecStopPost ++ vm.serviceConfig.ExecStopPost;
    peers = builtins.filter (peer: peer != slot) (builtins.attrNames slots);
    peerPaths =
      lib.concatMap (peer: [
        "-${slotctlSlots.${peer}.credential_dir}"
        "-${slotctlSlots.${peer}.trust_dir}"
        "-${builtins.dirOf slotctlSlots.${peer}.vm_dir}"
      ])
      peers;
  in
    assert lib.assertMsg (violations == {}) "mandatory namespace paths not created first: ${builtins.toJSON violations}";
    assert lib.assertMsg (dispatcherOptional == []) "dispatcher has optional writable paths: ${toString dispatcherOptional}";
    assert builtins.elem "f ${lockRoot}/${slot}.lock 0600 root root - -" c.systemd.tmpfiles.rules;
    assert lib.sort builtins.lessThan dispatcher.serviceConfig.ReadWritePaths == lib.sort builtins.lessThan [claims credParent job];
    assert dispatchDefinition.overrideStrategy == "asDropin";
    assert builtins.elem "multi-user.target" dispatchDefinition.wantedBy;
    assert builtins.elem "${dispatchName}.service" services.${dispatchTemplate}.aliases;
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
    # The dispatcher can modify this slot's directories, not a peer's.
    assert slotctl.vm_dir == job && slotctl.credential_dir == "${credParent}/${slot}";
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
      inherit slotctl trustedSlotctl;
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
in
  assert builtins.attrNames slots == configuredSlots;
  assert builtins.attrNames slotctlSlots == configuredSlots;
  assert builtins.attrNames trustedSlotctlSlots == configuredSlots;
  assert lib.all uniqueBy ["StateDirectory" "RuntimeDirectory" "Slice" "User"]; {
    hostDrv = c.system.build.toplevel.drvPath;
    slots = results;
  }
