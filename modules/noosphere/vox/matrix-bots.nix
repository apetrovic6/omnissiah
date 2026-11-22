# Bot accounts on the homeserver (./matrix.nix), declared instead of
# registered by hand: one generated password per bot (./_matrix-bot-var.nix,
# shared with the machine the bot runs on) and a oneshot that registers the
# account through the registration shared secret. Registration skips an
# account that already exists, so the unit is safe on every boot.
#
# A new bot: add its local part to `bots` here and point its service at the
# same generator, `matrix-bot-<localpart>`.
{...}: {
  flake.nixosModules.vox-matrix-bots = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.imperium.matrixBots;
    synapse = config.services.matrix-synapse;
    secretPath = config.clan.core.vars.generators.matrix-registration-secret.files."registration_shared_secret".path;
    # register_new_matrix_user reads the shared secret from a config file.
    registerConfig = pkgs.writeText "matrix-register.yaml" ''
      registration_shared_secret_path: "${secretPath}"
    '';
  in {
    options.services.imperium.matrixBots = {
      bots = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["hermes"];
        description = "Local parts of the bot accounts to register (non-admin).";
      };
    };

    config = lib.mkIf (cfg.bots != []) {
      clan.core.vars.generators = lib.genAttrs (map (b: "matrix-bot-${b}") cfg.bots) (_:
        lib.recursiveUpdate (import ./_matrix-bot-var.nix {inherit pkgs;}) {
          files.password.owner = "matrix-synapse";
        });

      systemd.services = lib.listToAttrs (map (bot:
        lib.nameValuePair "matrix-register-${bot}" {
          description = "Register the Matrix bot account @${bot}";
          wantedBy = ["multi-user.target"];
          after = ["matrix-synapse.service"];
          requires = ["matrix-synapse.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "matrix-synapse";
            # Synapse can take a moment to answer after it reports ready.
            Restart = "on-failure";
            RestartSec = 15;
          };
          script = ''
            ${synapse.package}/bin/register_new_matrix_user \
              -c ${registerConfig} --exists-ok --no-admin -u ${bot} \
              --password-file ${config.clan.core.vars.generators."matrix-bot-${bot}".files.password.path} \
              http://127.0.0.1:8008
          '';
        })
      cfg.bots);
    };
  };
}
