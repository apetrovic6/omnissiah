{self, ...}: {
  imports = [self.nixosModules.taghmata-node];

  # Sets the private key secret for sops secrets operator in the cluster
  noosphere.taghmata.sopsAgeKey.enable = true;

  # Trial: two jobs at once so noosphere does not show terra offline while
  # it runs an ugalabugala job. Both share the runner's 2 CPU / 4 GiB cap.
  services.imperium.forgejoRunner.capacity = 2;

  # Longhorn's trimFilesystem API hardcodes /usr/bin/fstrim, which doesn't
  # exist on NixOS. This symlink makes it available so Longhorn can trim
  # volumes to reclaim freed space from the block device.
  system.activationScripts.fstrim-link = ''
    mkdir -p /usr/bin
    ln -sf /run/current-system/sw/bin/fstrim /usr/bin/fstrim
  '';
}
