{...}: 
{
  services.displayManager.cosmic-greeter.enable = false;
  services.desktopManager.cosmic = {
    enable = false;
    xwayland.enable = true;
  };
}
