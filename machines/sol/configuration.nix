{self, ...}: {
  imports = [self.nixosModules.taghmata-node];

  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = false;
    };
  };
}
