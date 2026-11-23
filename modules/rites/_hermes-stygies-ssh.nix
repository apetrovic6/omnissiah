# The SSH key Hermes on ryza uses for its `ssh` terminal backend into stygies
# (HOM-18). Shared, so the public half lands in vars/shared and stygies can
# authorize it without being a recipient of the private half. Imported on ryza
# only; stygies reads the public file from vars/shared.
{pkgs, ...}: {
  clan.core.vars.generators.hermes-stygies-ssh = {
    share = true;
    files."id_ed25519" = {
      owner = "hermes";
      group = "hermes";
    };
    files."id_ed25519.pub".secret = false;
    runtimeInputs = [pkgs.openssh];
    script = ''
      ssh-keygen -t ed25519 -N "" -C "hermes@ryza->stygies" -f "$out/id_ed25519"
    '';
  };
}
