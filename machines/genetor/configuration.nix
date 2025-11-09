{pkgs, ...}:
{
  imports = [ 

  ];

  environment.systemPackages = with pkgs; [
    git
    wget
    vim
    fastfetch
    yazi
  ];

            users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOuTvHKw/dHSm0NLjCQsk/9sPyNRerLB/wWuwitVpvdg"
  ];
  system.stateVersion = 6;
  clan.core.networking.targetHost = "root@192.168.1.149";
  nixpkgs.hostPlatform = "aarch64-darwin";
}
