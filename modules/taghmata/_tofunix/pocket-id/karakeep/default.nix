{
  ref,
  domain,
  ...
}: {
  resource.pocketid_client.karakeep = let
    baseUrl = "https://karakeep.${domain}";
  in {
    name = "karakeep";
    callback_urls = [
      "https://karakeep.${domain}/api/auth/callback/custom"
    ];

    logout_callback_urls = [baseUrl];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.kubernetes_secret_v1.karakeep-oidc = {
    metadata = {
      name = "karakeep-oidc";
      namespace = "karakeep";
    };

    data = {
      OAUTH_CLIENT_ID = ref.pocketid_client.karakeep.id;
      OAUTH_CLIENT_SECRET = ref.pocketid_client.karakeep.client_secret;
    };
  };
}
