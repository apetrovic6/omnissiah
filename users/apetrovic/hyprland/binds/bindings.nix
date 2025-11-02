{config, pkgs, lib, ... }:
let
    modifier = "SUPER";
    launcher = "walker";
    browser = "brave";
    terminal = "ghostty";
    passwordManager = "bitwarden";
    fileManager = "thunar";
    cliFileManager = "yazi";
    messenger = "signal";
in
{
  wayland.windowManager.hyprland.settings.bindd = [
    # Launchers
    "${modifier}, SPACE, Launcher, exec, ${launcher}"
    "${modifier}, RETURN, Terminal, exec, ${terminal}"
    "${modifier} SHIFT, F, File manager, exec, ${fileManager}"
    "${modifier}, B, Web browser, exec, ${browser}"
    #"${modifier}, M, Music player, exec, ${music}"
    "${modifier}, G, Messenger, exec, ${messenger}"
    "${modifier}, O, Obsidian, exec, obsidian -disable-gpu"
    "${modifier}, SLASH, Password manager, exec, ${passwordManager}"

    # Terminal apps
    "${modifier}, N, Neovim, exec, ${terminal} -e nvim"
    "${modifier}, D, Lazy Docker, exec, ${terminal} -e lazydocker"
    "${modifier}, F, Terminal File Manager, exec, ${terminal} -e ${cliFileManager}"

    # Hyprpanel
    "${modifier} SHIFT, SPACE, Toggle Hyprpanel, exec, hyprpanel-toggle"
    "${modifier} SHIFT, N, Notifications, exec, hyprpanel t notificationsmenu"
  ];
}

