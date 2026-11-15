# AWS CLI with its profiles kept in clan vars, one generator per profile.
#
#   services.imperium.awscli.profiles = {
#     natl = "sso";     # IAM Identity Center login
#     garage = "keys";  # static access key, e.g. an S3-compatible store
#   };
#
# Each entry gets a shared generator, aws-profile-<name>, that asks one
# question per field (start URL, account ID, ...) and renders that profile's
# ~/.aws/config section(s). An `sso` profile gets its own `[sso-session <name>]`,
# so `aws sso login --profile <name>` logs in for it. At activation the
# rendered sections are concatenated into /run/awscli/config, and ~/.aws/config
# is a home-manager symlink to it.
#
# Adding a profile: add it above, then
#   clan vars generate --generator aws-profile-<name>
# (shared, so one run covers every workstation). Editing one: the same command
# with --regenerate -- every answer is pre-filled with its previous value, so
# Enter keeps it. Removing one: drop it and delete vars/shared/aws-profile-<name>.
#
# Answers are stored encrypted in the repo (that is what the pre-fill reads)
# but not deployed; only the rendered section reaches the machines. Nothing
# enters the Nix store, and the stitched file lives on /run (tmpfs), rebuilt on
# every boot and switch, so it needs no impermanence entry. ~/.aws/config is
# read-only as a result: `aws configure …` cannot write to it. The SSO token
# and assumed-role caches (~/.aws/sso, ~/.aws/cli) are persisted in
# impermanence.nix.
{...}: {
  flake.nixosModules.awscli = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.awscli;
    generatorName = name: "aws-profile-${name}";
    chunkPath = name: config.clan.core.vars.generators.${generatorName name}.files.snippet.path;
    runDir = "/run/awscli";
    group = config.users.users.${cfg.user}.group;

    # Prompts are asked in attribute-name order, hence the numeric prefixes.
    # All persisted (so --regenerate pre-fills them), none deployed.
    prompt = description: type: {
      inherit description type;
      persist = true;
    };

    kinds = {
      sso = {
        prompts = {
          "1-start-url" = prompt "SSO start URL (https://<something>.awsapps.com/start)" "line";
          "2-sso-region" = prompt "SSO region, where IAM Identity Center lives (e.g. eu-central-1)" "line";
          "3-account-id" = prompt "AWS account ID (12 digits)" "line";
          "4-role-name" = prompt "Role / permission set name (e.g. AdministratorAccess)" "line";
          "5-region" = prompt "Default region for commands (empty = same as SSO region)" "line";
        };
        script = name: ''
          start_url="$(get 1-start-url)"
          sso_region="$(get 2-sso-region)"
          account_id="$(get 3-account-id)"
          role_name="$(get 4-role-name)"
          region="$(get 5-region)"
          region="''${region:-$sso_region}"

          case "$start_url" in https://*) ;; *) die "start URL must begin with https://" ;; esac
          check_region "$sso_region"
          check_region "$region"
          [[ "$account_id" =~ ^[0-9]{12}$ ]] || die "account ID must be exactly 12 digits"
          [ -n "$role_name" ] || die "role name is required"

          cat > "$out/snippet" <<EOF
          [sso-session ${name}]
          sso_start_url = $start_url
          sso_region = $sso_region
          sso_registration_scopes = sso:account:access

          [profile ${name}]
          sso_session = ${name}
          sso_account_id = $account_id
          sso_role_name = $role_name
          region = $region
          EOF
        '';
      };

      keys = {
        prompts = {
          "1-access-key-id" = prompt "Access key ID" "line";
          "2-secret-access-key" = prompt "Secret access key" "hidden";
          "3-region" = prompt "Region (e.g. eu-central-1; for Garage/MinIO, its configured region)" "line";
          "4-endpoint-url" = prompt "Endpoint URL (empty = AWS itself; e.g. https://s3.example.org)" "line";
        };
        script = name: ''
          key_id="$(get 1-access-key-id)"
          secret="$(get 2-secret-access-key)"
          region="$(get 3-region)"
          endpoint="$(get 4-endpoint-url)"

          [ -n "$key_id" ] || die "access key ID is required"
          [ -n "$secret" ] || die "secret access key is required"
          [ -n "$region" ] || die "region is required"
          case "$endpoint" in "" | https://* | http://*) ;; *) die "endpoint URL must begin with http(s)://" ;; esac

          {
            printf '[profile %s]\n' ${lib.escapeShellArg name}
            printf 'aws_access_key_id = %s\n' "$key_id"
            printf 'aws_secret_access_key = %s\n' "$secret"
            printf 'region = %s\n' "$region"
            if [ -n "$endpoint" ]; then printf 'endpoint_url = %s\n' "$endpoint"; fi
          } > "$out/snippet"
        '';
      };
    };

    mkGenerator = name: kind: let
      k = kinds.${kind};
    in {
      share = true;
      inherit (k) prompts;

      files =
        lib.mapAttrs (_: _: {deploy = false;}) k.prompts
        // {
          # root-owned: only the activation script below reads it.
          snippet = {
            secret = true;
            mode = "0400";
          };
        };

      runtimeInputs = [pkgs.coreutils];

      script = ''
        set -euo pipefail
        die() { echo "${generatorName name}: $*" >&2; exit 1; }
        # Prompt answer with surrounding whitespace (incl. the newline) removed.
        # Pure bash: a failing command inside $(get …) would not trip set -e.
        get() {
          local v
          v="$(< "$prompts/$1")"
          v="''${v#"''${v%%[![:space:]]*}"}"
          v="''${v%"''${v##*[![:space:]]}"}"
          printf '%s' "$v"
        }
        check_region() {
          [[ "$1" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || die "'$1' is not a region name (e.g. eu-central-1)"
        }

        # persist = true: keep the answers for the --regenerate pre-fill.
        for p in ${lib.escapeShellArgs (lib.attrNames k.prompts)}; do
          cp "$prompts/$p" "$out/$p"
        done

        ${k.script name}
      '';
    };
  in {
    options.services.imperium.awscli = {
      enable = mkEnableOption "the AWS CLI with profiles from clan vars";

      user = mkOption {
        type = types.str;
        default = "apetrovic";
        description = "User whose ~/.aws/config is managed.";
      };

      profiles = mkOption {
        type = types.attrsOf (types.enum (lib.attrNames kinds));
        default = {};
        example = {
          natl = "sso";
          garage = "keys";
        };
        description = ''
          Profile name -> kind. Each becomes a clan vars generator,
          aws-profile-<name>, that asks for that kind's fields.
        '';
      };
    };

    config = mkIf cfg.enable {
      assertions =
        lib.mapAttrsToList (name: _: {
          assertion = builtins.match "[a-z0-9][a-z0-9-]*" name != null;
          message = "services.imperium.awscli.profiles: '${name}' must be lowercase letters, digits and dashes";
        })
        cfg.profiles;

      environment.systemPackages = [pkgs.awscli2];

      clan.core.vars.generators = lib.mapAttrs' (name: kind:
        lib.nameValuePair (generatorName name) (mkGenerator name kind))
      cfg.profiles;

      system.activationScripts.awscli-config = {
        deps = ["setupSecrets"];
        text = ''
          install -d -m 0700 -o ${cfg.user} -g ${group} ${runDir}
          tmp="$(mktemp ${runDir}/.config.XXXXXX)"
          ${lib.concatMapStrings (name: ''
              if [ -r ${chunkPath name} ]; then
                cat ${chunkPath name} >> "$tmp"
                printf '\n' >> "$tmp"
              else
                echo "awscli: ${generatorName name} not deployed yet, skipping" >&2
              fi
            '')
            (lib.attrNames cfg.profiles)}
          chown ${cfg.user}:${group} "$tmp"
          chmod 0400 "$tmp"
          mv -f "$tmp" ${runDir}/config
        '';
      };

      home-manager.users.${cfg.user} = {config, ...}: {
        home.file.".aws/config".source = config.lib.file.mkOutOfStoreSymlink "${runDir}/config";
      };
    };
  };
}
