{ref, ...}: let
  secretsFile = toString ../../../../../vars/shared/tofunix-pocketid-secret/tofunix-pocketid-secret/value;
  lu-user = toString ../../../../../vars/shared/tofunix-pocketid-lu/tofunix-pocketid-secret/value;
  noosphere = import ../../../../vars/_noosphere-values.nix;
  inherit (noosphere) domain;
in {
  imports = [
    (import ./karakeep {
      inherit ref;
      domain = domain;
    })
    (import ./forgejo {
      inherit ref;
      domain = domain;
    })
    (import ./garage-ui {
      inherit ref;
      domain = domain;
    })
  ];

  data.sops_file.pocket_api_key = {
    source_file = secretsFile;
    input_type = "yaml";
  };

  data.sops_file.pocket_lu_user = {
    source_file = lu-user;
    input_type = "yaml";
  };

  provider.pocketid.default = {
    base_url = "https://id.${domain}";
    api_token = "\${data.sops_file.pocket_api_key.data[\"api_key\"]}";
  };

  resource.pocketid_group.admin = {
    name = "Admin";
    friendly_name = "Administrators";
  };

  resource.pocketid_group.argocd_admins = {
    name = "ArgoCDAdmins";
    friendly_name = "ArgoCD Admins";
  };

  resource.pocketid_group.users = {
    name = "User";
    friendly_name = "Users";
  };

  resource.pocketid_group.developers = {
    name = "developers";
    friendly_name = "Developers";
  };

  resource.pocketid_user.lu = {
    username = "\${data.sops_file.pocket_lu_user.data[\"username\"]}";
    email = "\${data.sops_file.pocket_lu_user.data[\"email\"]}";
    first_name = "\${data.sops_file.pocket_lu_user.data[\"first_name\"]}";
    last_name = "\${data.sops_file.pocket_lu_user.data[\"last_name\"]}";
    groups = [ref.pocketid_group.users.id ref.pocketid_group.developers.id];
  };

  resource.pocketid_client.vikunja = let
    baseUrl = "https://vikunja.${domain}";
  in {
    name = "Vikunja";
    callback_urls = [
      "https://vikunja.${domain}/auth/openid/pocketid"
    ];

    logout_callback_urls = [
      baseUrl
    ];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.pocketid_client.pangolin = let
    baseUrl = "https://ugalabugala.org";
  in {
    name = "pangolin";
    callback_urls = [
      "https://ugalabugala.org/auth/idp/1/oidc/callback"
    ];

    logout_callback_urls = [
      baseUrl
    ];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.kubernetes_secret_v1.vikunja-oidc = {
    metadata = {
      name = "vikunja-oidc";
      namespace = "vikunja";
    };

    data = {
      client-id = ref.pocketid_client.vikunja.id;
      client-secret = ref.pocketid_client.vikunja.client_secret;
    };
  };

  resource.pocketid_client.argocd = let
    baseUrl = "https://argocd.${domain}";
  in {
    name = "ArgoCD";
    callback_urls = [
      "${baseUrl}/auth/callback"
    ];

    logout_callback_urls = [
      baseUrl
    ];

    allowed_user_groups = [
      ref.pocketid_group.argocd_admins.id
    ];

    pkce_enabled = false;
    launch_url = baseUrl;
  };

  resource.kubernetes_secret_v1.argo-oidc = {
    metadata = {
      name = "argo-oidc";
      namespace = "argocd";
      labels = {
        "app.kubernetes.io/part-of" = "argocd";
      };
    };

    data = {
      client-id = ref.pocketid_client.argocd.id;
      client-secret = ref.pocketid_client.argocd.client_secret;
    };
  };
}
