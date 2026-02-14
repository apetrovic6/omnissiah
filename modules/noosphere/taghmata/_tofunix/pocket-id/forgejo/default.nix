{ref, domain, ...}: 
{
  resource.pocketid_client.forgejo = let
    baseUrl = "https://forgejo.${domain}";
  in {
    name = "forgejo";
    callback_urls = [
      "https://forge.${domain}/user/oauth2/Pocket%20ID/callback"
    ];

    logout_callback_urls = [baseUrl];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.kubernetes_secret_v1.forgejo-oidc = {
    metadata = {
      name = "forgejo-oidc";
      namespace = "forgejo";
    };

    data = {
      key= ref.pocketid_client.forgejo.id;
      secret = ref.pocketid_client.forgejo.client_secret;
    };
  };

}
