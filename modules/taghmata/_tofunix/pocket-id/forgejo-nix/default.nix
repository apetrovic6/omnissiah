{ref, ...}: let
  baseUrl = "https://forge.ugalabugala.org";
in {
  resource.pocketid_client.forgejo_nix = {
    name = "Forgejo";
    callback_urls = ["${baseUrl}/user/oauth2/Pocket%20ID/callback"];
    logout_callback_urls = [baseUrl];
    pkce_enabled = false;
    launch_url = baseUrl;
  };
}
