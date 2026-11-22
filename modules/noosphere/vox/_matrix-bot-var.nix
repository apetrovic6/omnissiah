# The password of a Matrix bot account, shared between the homeserver
# (cypramundi, which registers the account: ./matrix-bots.nix) and the machine
# the bot runs on (ryza for Hermes: modules/rites/hermes.nix). Both import this
# one definition, so the shared generator is identical on both. Each sets the
# file's owner to its own user.
#
# Generated, never typed in. Rotating it (`--regenerate`) does not change the
# account: registration skips an existing user, so also reset the password
# in Synapse.
{pkgs}: {
  share = true;
  files.password.secret = true;
  runtimeInputs = [pkgs.openssl];
  script = ''openssl rand -hex 32 > "$out/password"'';
}
