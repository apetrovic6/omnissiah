{
  ref,
  domain,
  ...
}: {
  resource.pocketid_client.garage_ui = let
    baseUrl = "https://ui.garage.${domain}";
  in {
    name = "garage-ui";
    callback_urls = [
      "${baseUrl}/auth/oidc/callback"
    ];

    logout_callback_urls = [baseUrl];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.pocketid_client.garage_main_ui = let
    baseUrl = "https://ui.main.garage.${domain}";
  in {
    name = "garage-main-ui";
    callback_urls = [
      "${baseUrl}/auth/oidc/callback"
    ];

    logout_callback_urls = [baseUrl];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.pocketid_client.garage_backup_ui = let
    baseUrl = "https://ui.backup.garage.${domain}";
  in {
    name = "garage-backup-ui";
    callback_urls = [
      "${baseUrl}/auth/oidc/callback"
    ];

    logout_callback_urls = [baseUrl];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.kubernetes_secret_v1.garage-ui-oidc-secret = {
    metadata = {
      name = "garage-ui-oidc-secret";
      namespace = "garage";
    };

    data = {
      client-id = ref.pocketid_client.garage_ui.id;
      client-secret = ref.pocketid_client.garage_ui.client_secret;
    };
  };

  resource.kubernetes_secret_v1.garage-main-ui-oidc-secret = {
    metadata = {
      name = "garage-main-ui-oidc-secret";
      namespace = "garage-operator";
    };

    data = {
      client-id = ref.pocketid_client.garage_main_ui.id;
      client-secret = ref.pocketid_client.garage_main_ui.client_secret;
    };
  };

  resource.kubernetes_secret_v1.garage-backup-ui-oidc-secret = {
    metadata = {
      name = "garage-backup-ui-oidc-secret";
      namespace = "garage-operator";
    };

    data = {
      client-id = ref.pocketid_client.garage_backup_ui.id;
      client-secret = ref.pocketid_client.garage_backup_ui.client_secret;
    };
  };
}
