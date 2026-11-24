{...}: {
  flake.nixosModules.hermes-forgejo-bot = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (import ../../machines/ryza/_coder-projects.nix) forges projects;
    sshForge = forges.cerberus;
    httpsForge = forges.noosphere;
    vars = config.clan.core.vars.generators;
    sshKey = vars.hermes-forgejo-ssh.files."id_ed25519".path;
    tokenPath = forge: vars.${forge.tokenGenerator}.files.token.path;
    fj = lib.getExe' pkgs.forgejo-cli "fj";

    # The token goes only from the deployed var to Git's credential pipe.
    credentialHelper = pkgs.writeShellScript "hermes-git-credential-noosphere" ''
      [ "$1" = get ] || exit 0
      protocol= host= username= token=
      while IFS='=' read -r key value; do
        case "$key" in
          protocol) protocol=$value ;;
          host) host=$value ;;
          username) username=$value ;;
          "") break ;;
        esac
      done
      [ "$protocol" = https ] && [ "$host" = ${lib.escapeShellArg httpsForge.host} ] || exit 0
      [ -z "$username" ] || [ "$username" = hermes ] || exit 0

      file=${lib.escapeShellArg (tokenPath httpsForge)}
      [ -r "$file" ] && [ -s "$file" ] || exit 0
      # A Clan prompt file can end at EOF without a newline.
      IFS= read -r token < "$file" || :
      [ -n "$token" ] || exit 0
      printf 'username=hermes\npassword=%s\n\n' "$token"
    '';

    # Read-only (a store path, linked in below), so the agent can't change
    # whose name its commits carry or which key it pushes with.
    gitConfig = pkgs.writeText "hermes-gitconfig" ''
      [user]
        name = Hermes
        email = hermes@${sshForge.host}
      [url "${sshForge.gitBase}/"]
        insteadOf = https://${sshForge.host}/
      [credential "${httpsForge.gitBase}"]
        helper =
        helper = ${credentialHelper}
    '';

    appProjects = lib.attrNames projects;
    taskCommand = pkgs.writeShellScript "hermes-task" ''
      umask 077
      export HERMES_TASK_APP_PROJECTS=${lib.escapeShellArg (builtins.toJSON appProjects)}
      ${lib.getExe' pkgs.coreutils "mkdir"} -p "$HOME/work" || exit $?
      ${lib.getExe' pkgs.util-linux "flock"} -w 10 -E 75 "$HOME/work/.task-lock" \
        ${lib.getExe pkgs.python3} -I ${./_hermes-task.py} "''${0##*/}" "$@"
      status=$?
      if [ "$status" -eq 75 ]; then
        printf '%s\n' 'task lock busy, retry once' >&2
      fi
      exit "$status"
    '';
    taskTools = pkgs.runCommand "hermes-task-tools" {} ''
      mkdir -p "$out/bin"
      for command in task-status task-claim task-branch task-done task-clear task-drop; do
        ln -s ${taskCommand} "$out/bin/$command"
      done
    '';
  in {
    clan.core.vars.generators =
      {
        # This key authenticates to Forgejo, not from ryza into stygies.
        hermes-forgejo-ssh = {
          files."id_ed25519" = {
            owner = "hermes";
            group = "hermes";
            mode = "0400";
          };
          files."id_ed25519.pub".secret = false;

          runtimeInputs = [pkgs.openssh];
          script = ''
            ssh-keygen -q -t ed25519 -N "" -C hermes@stygies -f "$out/id_ed25519"
          '';
        };
      }
      // lib.mapAttrs' (_: forge:
        lib.nameValuePair forge.tokenGenerator {
          prompts.token = {
            description = "Hermes runtime PAT for ${forge.host}: All repositories, write:repository + write:issue (not an operator token)";
            type = "hidden";
          };
          files.token = {
            secret = true;
            owner = "hermes";
            group = "hermes";
            mode = "0400";
          };

          runtimeInputs = [pkgs.coreutils];
          script = ''
            cp "$prompts/token" "$out/token"
          '';
        })
      forges;

    # `fj`, the Forgejo CLI: Hermes opens PRs from its forks and reads review
    # comments with it. Its login comes from the token var (below).
    environment.systemPackages = [pkgs.forgejo-cli];
    users.users.hermes.packages = [taskTools];

    systemd.tmpfiles.settings.hermes-forgejo-bot = {
      "/home/hermes/.config".d = {
        user = "hermes";
        group = "hermes";
        mode = "0700";
      };
      "/home/hermes/.config/git".d = {
        user = "hermes";
        group = "hermes";
        mode = "0700";
      };
      "/home/hermes/.config/git/config"."L+".argument = "${gitConfig}";
    };

    # Git over SSH with the bot key, for the hermes user only. Forgejo's
    # built-in SSH server (START_SSH_SERVER) has just an RSA host key; this is
    # the one it serves from FORGEJO_WORK_DIR (/mnt/nas/git/data/ssh/gitea.rsa
    # on cerberus; /var/lib/forgejo/data/ssh holds a stale, unused one).
    programs.ssh = {
      knownHosts.forgejo-cerberus = {
        hostNames = ["[${sshForge.host}]:${toString sshForge.sshPort}"];
        publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDdOp8RNcy2qPdBGzQi8yPCiIPoJTwGd2TlvGKrjGQGIzSW4qXwVv6cPFZvGYDt00ZmaY4mXViMEIkRv4st9+Fzx5brDld7p2Osg2JGnitbrlbYhvbXtalmLR3K7SN1NhA8ClsJ26j9uSDF5CSBNew28MGO5VlE+wioYWzkDBqnzM+3j6aXCL+5YfmjJKVXbchoW1u48nxrNTq1y6/K73ogfwfKI/lye1QufPdazbh0HVOyQkaRxNi4J0jzLRKErKhG/qA3AjvVBchXOe6crbUT216XHFoIengo1zmpSp4zl+YPKB83HdzPz20/zOVgX8Q2M/q6dwrb4yrIkCZdax+eWq+8e4POA0SypoaKcJdbZV7R2JLWZtM5puMNOwnjzRWwDnAU8N2sUGD9cexguOGZdrWvhzr/+/nPcJSMpUY+tQhGrMWaAnYpxqMxq9r/dOYoQacUtmUHNPkBhVn56kQgm52bZTvfae/lU3ZJDrTP1gIVz3BS9n3Q8P3IPJ9/P4grEoJTOIHC5g3yQiGEh0TnqlsgqoJl0LeHOTS/D/nx7NsyiChTcey7/6+hqOgdvXUfFOpG/FU2rR8HtI42Gksh9kx1ZlFFMLrqxeQbcoG+5H5FlynMfx8uy47/4UugoDNTBo9om4vKxAdggor8OOUOLdfiXunSfA1gwQUiUa9+/w==";
      };
      extraConfig = ''
        Match localuser hermes host ${sshForge.host}
          Port ${toString sshForge.sshPort}
          User forgejo
          IdentityFile ${sshKey}
          IdentitiesOnly yes
          StrictHostKeyChecking yes
      '';
    };

    # fj stores both logins in ~hermes/.local/share/forgejo-cli/keys.json.
    # Update them in sequence; add-token refuses to replace an existing host
    # login (forgejo-cli 0.7.0 src/auth.rs). After rotating only a token:
    # `systemctl restart hermes-fj-login`.
    systemd.services.hermes-fj-login = {
      description = "Log fj in to the configured forges as the Hermes bot";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hermes";
        Group = "hermes";
        WorkingDirectory = "~";
      };
      script = ''
        umask 077
        status=0
        ${lib.concatMapStringsSep "\n" (forge: let
          token = lib.escapeShellArg (tokenPath forge);
        in ''
          if [ -s ${token} ]; then
            ${fj} auth logout ${forge.host} &&
              ${fj} -H ${forge.host} auth add-token < ${token} || status=$?
          fi
        '') (builtins.attrValues forges)}
        exit "$status"
      '';
    };
  };
}
