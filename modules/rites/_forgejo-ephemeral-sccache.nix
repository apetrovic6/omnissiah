# Guest side of trusted cache delivery. The host share is root-only and
# read-only; the guest copy is readable by the job, but not replaceable by it.
{
  lib,
  pkgs,
}: let
  source = "/run/ci-trust/sccache-credentials";
  directory = "/run/ci-sccache";
  credentialsFile = "${directory}/credentials";
  name = "ci-sccache";
  user = "forgejo-one-job";
in {
  wrapper = import ./_sccache-wrapper.nix {
    inherit lib pkgs credentialsFile;
    requireCredentials = true;
  };

  guest = {
    systemd.paths.${name} = {
      wantedBy = ["multi-user.target"];
      unitConfig.RequiresMountsFor = ["/run/ci-trust"];
      pathConfig.PathExists = source;
    };
    # Host-side virtiofs changes need not emit a guest inotify event. Start
    # the same watcher via the timer if the path unit hasn't noticed it yet.
    systemd.timers.${name} = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnActiveSec = "2s";
        AccuracySec = "1s";
      };
    };
    systemd.services.${name} = {
      description = "Publish or withdraw the trusted CI cache credential";
      unitConfig.RequiresMountsFor = ["/run/ci-trust"];
      path = [pkgs.coreutils pkgs.diffutils];
      serviceConfig = {
        RuntimeDirectory = name;
        RuntimeDirectoryMode = "0755";
        UMask = "0077";
        ProtectSystem = "strict";
        PrivateNetwork = true;
        Restart = "on-failure";
        RestartSec = "2s";
      };
      script = ''
        set -eu
        while true; do
          if [[ -f ${source} ]]; then
            if ! cmp -s -- ${source} ${credentialsFile}; then
              install -m 0440 -o root -g ${user} -- ${source} ${directory}/.credentials.tmp
              mv -fT -- ${directory}/.credentials.tmp ${credentialsFile}
            fi
          elif [[ -e ${credentialsFile} ]]; then
            rm -f -- ${credentialsFile}
          fi
          sleep 2
        done
      '';
    };
  };
}
