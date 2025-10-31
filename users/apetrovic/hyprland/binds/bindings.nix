{ ... }:
let
    modifier = "SUPER";
    browser = "brave";
    terminal = "ghostty";
    passwordManager = "bitwarden";
    fileManager = "thunar";
    cliFileManager = "yazi";
    messenger = "signal";
in
{
  wayland.windowManager.hyprland.settings.bindd = [
    "${modifier}, Return,Terminal, exec, ${terminal}"

    # Launchers
    "${modifier}, RETURN, Terminal, exec, ${terminal}"
    "${modifier}, F, File manager, exec, ${fileManager}"
    "${modifier}, B, Web browser, exec, ${browser}"
    #"${modifier}, M, Music player, exec, ${music}"
    "${modifier}, G, Messenger, exec, ${messenger}"
    "${modifier}, O, Obsidian, exec, obsidian -disable-gpu"
    "${modifier}, SLASH, Password manager, exec, ${passwordManager}"

    # Terminal apps
    "${modifier}, N, Neovim, exec, ${terminal} -e nvim"
    "${modifier}, T, Top, exec, ${terminal} -e btop"
    "${modifier}, D, Lazy Docker, exec, ${terminal} -e lazydocker"
    "${modifier} SHIFT, F, Terminal File Manager, exec, ${terminal} -e ${cliFileManager}"
  ];
}

