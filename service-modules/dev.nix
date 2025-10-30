{
  _class = "clan.service";
  manifest.name = "base";

  roles.default.perInstance.nixosModule = { lib, pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      insomnia
      postman
      devenv

    ];

    programs.direnv = {
      enable = true;
      enableZshIntegration = true;
      enableBashIntegration = true;
    };
};
}
