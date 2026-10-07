{
  pkgs,
  lib,
  ...
}: {
  imports = [./hardware.nix];

  networking.hostName = "servitor";

  # No tags in inventory/machines.nix yet, so this machine gets only the
  # clan-wide services (admin, tor). `base` is deliberately left off until the
  # board is known to boot -- it pulls in a large closure that would have to
  # cross-build or emulate before you ever see a login prompt. Add "base" to
  # the tags once this works.
  environment.systemPackages = with pkgs; [];

  # The admin clan service (clan.nix, roles.default.tags.all) authorises the
  # admin key for root, which is what `clan machines update` uses. sshd itself
  # still has to be on for that to be reachable.
  services.openssh.enable = true;

  networking.useDHCP = lib.mkForce true;
  networking.firewall.allowedTCPPorts = [22];

  # 4 GB of RAM and no swap partition in the image: without this, a
  # `nixos-rebuild` run on the board itself gets OOM-killed. Harmless when
  # everything is built on phalanx and copied over.
  zramSwap.enable = true;
}
