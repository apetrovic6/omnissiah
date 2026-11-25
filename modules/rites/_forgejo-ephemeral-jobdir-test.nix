# Eval check for the slot's directories (HOM-30 live fix). Runs as the flake
# check checks.x86_64-linux.forgejo-ephemeral-jobdir; by hand:
#   nix eval --impure --json .#nixosConfigurations.ryza --apply \
#     'ryza: import ./modules/rites/_forgejo-ephemeral-jobdir-test.nix { inherit ryza; }'
#
# systemd builds a mount namespace for every Exec*= process, '+' ones
# included (they still get ReadWritePaths=), and chdirs into
# WorkingDirectory=. A missing non-'-' path fails that process with
# 226/NAMESPACE or 200/CHDIR. Invariant: every mandatory path of a slot unit
# is "/" or a directory the installer creates, and the unit Requires= and is
# ordered after the installer. An optional '-' path that is missing at start
# stays read-only, so the dispatcher may not use them at all.
{ryza}: let
  inherit (ryza.pkgs) lib;
  enabled = ryza.extendModules {
    modules = [
      {
        services.imperium.forgejoEphemeral = {
          enable = lib.mkForce true;
          repoId = lib.mkForce 4242;
        };
        clan.core.vars.generators.forgejo-ephemeral-ugalabugala.files.token.path = lib.mkForce "/run/secrets/ephemeral-test-pat";
      }
    ];
  };
  c = enabled.config;
  services = c.systemd.services;
  # The one slot ryza has in modules/rites/_ci-slots.nix.
  inherit (c.services.imperium.forgejoEphemeral.internal) slot;
  vmName = "microvm@${slot}";
  install = "install-microvm-${slot}";
  installUnit = "${install}.service";
  credParent = "/run/microvm-credentials";
  control = "${c.microvm.stateDir}/${slot}";
  job = "${control}/job";
  installer = services.${install};
  dispatcher = services.forgejo-ephemeral-dispatcher;
  vm = services.${vmName};
  prepares = installer.serviceConfig.ExecStartPre;
  prepare = builtins.head prepares;
  # Instances are drop-ins over upstream templates; merge the two views.
  instance = name: let
    template = services."${lib.head (lib.splitString "@" name)}@" or {};
    merged = (template.serviceConfig or {}) // services.${name}.serviceConfig;
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
  units = map instance [install vmName "microvm-set-booted@${slot}" "microvm-virtiofsd@${slot}" "forgejo-ephemeral-dispatcher"];
  namespacePaths = s:
    [(s.WorkingDirectory or "/")] ++ (s.ReadWritePaths or []) ++ (s.InaccessiblePaths or []);
  mandatory = paths: builtins.filter (path: !(lib.hasPrefix "-" path)) paths;
  # What the installer really creates: the module's list, checked below
  # against the script's install lines (an edit that drops one must fail).
  internal = c.services.imperium.forgejoEphemeral.internal;
  created = map (dir: dir.path) internal.slotDirs;
  scriptLines = lib.splitString "\n" internal.prepareDirs.text;
  installLines = builtins.filter (lib.hasPrefix ''"$install" -d'') scriptLines;
  expectedLines = map (dir: ''"$install" -d -o ${dir.owner} -g ${dir.group} -m ${dir.mode} -- ${dir.path}'') internal.slotDirs;
  symlinkCheck = "for dir in ${lib.concatStringsSep " " created}; do";
  orderedAfterInstaller = u:
    builtins.elem installUnit u.requires
    && (builtins.elem installUnit u.after || builtins.elem "${u.name}.service" installer.before);
  unsafe = u:
    builtins.filter (path: path != "/" && !(builtins.elem path created && orderedAfterInstaller u))
    (mandatory (namespacePaths u.serviceConfig));
  violations = lib.filterAttrs (_: v: v != []) (lib.listToAttrs (map (u: lib.nameValuePair u.name (unsafe u)) units));
  dispatcherOptional = builtins.filter (lib.hasPrefix "-") (dispatcher.serviceConfig.ReadWritePaths or []);
  settings = c.systemd.tmpfiles.settings."10-microvm";
  guestFs = c.microvm.vms.${slot}.config.config.fileSystems."/nix/.ro-store";
  vmStop = services."microvm@".serviceConfig.ExecStopPost ++ vm.serviceConfig.ExecStopPost;
in
  assert lib.assertMsg (violations == {}) "mandatory namespace paths not created first: ${builtins.toJSON violations}";
  assert lib.assertMsg (dispatcherOptional == []) "dispatcher has optional writable paths: ${toString dispatcherOptional}";
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
  assert !(builtins.elem "kvm" c.users.users.microvm-eph.extraGroups) && c.users.users.microvm-eph.group == "microvm-eph";
  # The slot unit also repairs them first, before its sandboxed preflight.
  assert builtins.head vm.serviceConfig.ExecStartPre == prepare;
  assert mandatory (namespacePaths vm.serviceConfig) == [];
  # No bind mount on the credentials dir the '+' scrub removes (EBUSY).
  assert !(lib.any (lib.hasInfix "${credParent}/${slot}") vm.serviceConfig.ReadWritePaths);
  assert lib.all (lib.hasPrefix "+") vmStop;
  # tmpfiles: nothing under the microvm-owned state dir that changes owner.
  assert !((settings.${control} or {}) ? d) && !(builtins.hasAttr job settings);
  # Guest lower store is mounted ro, after "defaults".
  assert lib.last guestFs.options == "ro"; {
    hostDrv = c.system.build.toplevel.drvPath;
    guestDrv = c.microvm.vms.${slot}.config.config.system.build.toplevel.drvPath;
    inherit prepare created installLines;
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
  }
