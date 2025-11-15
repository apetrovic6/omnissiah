{self, ...}: {
  flake.nixosModules.impermanence = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkIf mkOption mkEnableOption types;
    cfg = config.services.imperium.impermanence;
  in {
    imports = [
      self.inputs.impermanence.nixosModules.impermanence
    ];

    options.services.imperium.impermanence = {
      enable = mkEnableOption "Enable Impermanence";
    };

    config = mkIf cfg.enable {
      environment.persistence."/persist" = {
        enable = true; # NB: Defaults to true, not needed
        hideMounts = true;
        directories = [
          "/etc"
          "/var/spool"
          "/root"
          "/srv"
          # "/var/log"
          "/var/lib/bluetooth"
          "/var/lib/nixos"
          "/var/db/sudo/lectured"
          "/var/lib/systemd/coredump"
          "/etc/NetworkManager/system-connections"
          {
            directory = "/var/lib/colord";
            user = "colord";
            group = "colord";
            mode = "u=rwx,g=rx,o=";
          }
        ];
        files = [
          #          "/etc/machine-id"
          {
            file = "/var/keys/secret_file";
            parentDirectory = {mode = "u=rwx,g=,o=";};
          }
        ];

        users.apetrovic = {
          directories = [
            "Downloads"
            "Music"
            "Pictures"
            "Documents"
            "Videos"
            ".config"
            ".local/share"
            {
              directory = ".gnupg";
              mode = "0700";
            }
            {
              directory = ".ssh";
              mode = "0700";
            }
            {
              directory = ".local/share/keyrings";
              mode = "0700";
            }
            ".local/share/direnv"
          ];
          files = [
            ".screenrc"
            ".bash_history"
            ".gitconfig"
          ];
        };
      };
    };
  };
}
