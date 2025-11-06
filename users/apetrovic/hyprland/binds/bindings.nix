{ pkgs, lib, ... }:
with pkgs;
let 
  inherit (lib) getExe;
    modifier = "SUPER";

    launcher =  getExe walker;
    browser = getExe librewolf;
     # terminal = getExe ghostty;
     terminal = getExe ghostty;
    # passwordManager = getExe bitwarden-desktop;
    fileManager = getExe xfce.thunar;
    cliFileManager = getExe yazi;
    # messenger = getExe signal-desktop-bin;

    passwordManager =  "bitwarden";
    messenger = "signal";
in
{
  wayland.windowManager.hyprland.settings.bindd = [
    # Walker
    "${modifier}, SPACE, Launcher, exec, ${launcher} -m desktopapplications"

    "${modifier}, RETURN, Terminal, exec, ${terminal}"
    "${modifier} SHIFT, F, File manager, exec, ${fileManager}"
    "${modifier}, B, Web browser, exec, ${browser}"

    #"${modifier}, M, Music player, exec, ${music}"
    #
    "${modifier}, G, Messenger, exec, ${messenger}"
    "${modifier}, O, Obsidian, exec, obsidian -disable-gpu"
    "${modifier}, SLASH, Password manager, exec, ${passwordManager}"

    # Terminal apps
    "${modifier}, N, Neovim, exec, ${terminal} -e nvim"
    #"${modifier}, D, Lazy Docker, exec, ${terminal} -e lazydocker"
    "${modifier}, D, Lazy Docker, exec, ${getExe lazydocker}"
    "${modifier}, F, Terminal File Manager, exec, ${terminal} -e ${cliFileManager}"

    # Hyprpanel
    #"${modifier} SHIFT, SPACE, Toggle Hyprpanel, exec, hyprpanel-toggle"
    "${modifier} SHIFT, SPACE, Toggle Hyprpanel, exec, hyprpanel toggleWindow bar-0"
    "${modifier} SHIFT, N, Notifications, exec, hyprpanel t notificationsmenu"
  ];
}

