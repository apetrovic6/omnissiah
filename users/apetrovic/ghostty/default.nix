{...}:
{
  programs.ghostty = {
    enable = true;
    installBatSyntax = true;
    installVimSyntax = true;
    enableBashIntegration = true;
    enableZshIntegration = true;

    settings = {
      window-padding-x = 12;
      window-padding-y = 12;
      keybind = [
        # Splits
        "ctrl+s=new_split:auto"
        "ctrl+left=goto_split:left"
        "ctrl+right=goto_split:right"
        "ctrl+up=goto_split:up"
        "ctrl+down=goto_split:down"

        # Resize Split
        "ctrl+shift+left=resize_split:left,10"
        "ctrl+shift+right=resize_split:right,10"
        "ctrl+shift+up=resize_split:up,10"
        "ctrl+shift+down=resize_split:down,10"
        "ctrl+shift+enter=equalize_splits"

        # Tabs
        "ctrl+t=new_tab"
        "ctrl+w=close_tab"
        "shift+left=next_tab"
        "shift+right=previous_tab"
      ];
    };
  };
}
