#
# {self, ...}: {
#   flake.nixosModules.service-dev = {
#     config,
#     lib,
#     pkgs,
#     ...
#   }:
{
  _class = "clan.service";
  manifest.name = "dev";
  manifest.readme = "";

  roles.default.description = "Dev related tools";

  roles.default.perInstance.nixosModule = {
    lib,
    pkgs,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      insomnia
      postman
      devenv
      lazydocker
      lazygit
    ];

    programs.adb.enable = true;

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
    };
  };
  #};
}
