# Every app that logs in through Pocket ID (../patterns/clients.nix). The
# public clients of the products are declared by ../fabricata.nix.
{noosphere, ...}: let
  inherit (noosphere) domain;
  inherit (import ../../../cartographa/_cartographa.nix) lab;
in {
  pharos.clients = {
    # The Hermes dashboard on ryza (modules/rites/hermes.nix), outside the
    # cluster: public, so no secret has to reach the machine, and admins only,
    # since the dashboard drives an agent with a shell.
    hermes = {
      name = "Hermes";
      url = "https://hermes.${domain}";
      callbacks = ["/auth/callback"];
      groups = ["admin"];
      public = true;
      clientId = "hermes";
    };

    argocd = {
      name = "ArgoCD";
      url = "https://argocd.${domain}";
      callbacks = ["/auth/callback"];
      groups = ["argocd_admins"];
      secret = {
        name = "argo-oidc";
        namespace = "argocd";
        labels."app.kubernetes.io/part-of" = "argocd";
      };
    };

    vikunja = {
      name = "Vikunja";
      url = "https://vikunja.${domain}";
      callbacks = ["/auth/openid/pocketid"];
      secret.namespace = "vikunja";
    };

    karakeep = {
      name = "karakeep";
      url = "https://karakeep.${domain}";
      callbacks = ["/api/auth/callback/custom"];
      secret = {
        namespace = "karakeep";
        idKey = "OAUTH_CLIENT_ID";
        secretKey = "OAUTH_CLIENT_SECRET";
      };
    };

    # The cluster forge.
    forgejo = {
      name = "forgejo";
      url = "https://forge.${domain}";
      callbacks = ["/user/oauth2/Pocket%20ID/callback"];
      secret = {
        namespace = "forgejo";
        idKey = "key";
        secretKey = "secret";
      };
    };

    # The cerberus forge, which takes its credentials from a clan var.
    forgejo_nix = {
      name = "Forgejo";
      url = "https://forge.${lab.domain}";
      callbacks = ["/user/oauth2/Pocket%20ID/callback"];
    };

    garage_main_ui = {
      name = "garage-main-ui";
      url = "https://ui.main.garage.${domain}";
      callbacks = ["/auth/oidc/callback"];
      secret = {
        name = "garage-main-ui-oidc-secret";
        namespace = "garage-operator";
      };
    };

    garage_backup_ui = {
      name = "garage-backup-ui";
      url = "https://ui.backup.garage.${domain}";
      callbacks = ["/auth/oidc/callback"];
      secret = {
        name = "garage-backup-ui-oidc-secret";
        namespace = "garage-operator";
      };
    };

    pangolin = {
      name = "pangolin";
      url = "https://${lab.domain}";
      callbacks = ["/auth/idp/1/oidc/callback"];
    };

    audiobookshelf = {
      name = "Audiobookshelf";
      url = "https://audiobookshelf.${lab.domain}";
      callbacks = ["/auth/openid/callback" "/auth/openid/mobile-redirect"];
      groups = ["users"];
    };

    # Aurral (yarr namespace) reads the keys as OIDC_CLIENT_ID/SECRET through
    # envFrom. The Aurral Pocket app signs in through this same callback:
    # Aurral finishes the login and hands it back to the app itself.
    aurral = {
      name = "Aurral";
      url = "https://aurral.${domain}";
      callbacks = ["/sso/callback"];
      groups = ["users"];
      secret = {
        namespace = "yarr";
        idKey = "OIDC_CLIENT_ID";
        secretKey = "OIDC_CLIENT_SECRET";
      };
    };

    # Its Secret is written below, in the one shape Harbor reads.
    harbor = {
      name = "Harbor";
      url = "https://harbor.${domain}";
      callbacks = ["/c/oidc/callback"];
      groups = ["users"];
    };
  };

  # Harbor takes its whole OIDC config as a single JSON blob in
  # CONFIG_OVERWRITE_JSON, which harbor-core reads once at startup. Rendering
  # that blob here keeps the client secret inside OpenTofu. It used to be
  # exported as plain client-id/client-secret keys and then re-typed by hand
  # into the `harbor-oidc-secret` clan var prompt, which is how a stray `-d`
  # ended up prefixed to the secret and broke the token exchange.
  resource.kubernetes_secret_v1.harbor-oidc = {
    metadata = {
      name = "harbor-oidc";
      namespace = "harbor";
    };

    # `''` opens the Nix string; the `''${` on the next line escapes down to a
    # literal `${`, so OpenTofu (not Nix) evaluates the interpolation.
    data.CONFIG_OVERWRITE_JSON = ''
      ''${jsonencode({
        auth_mode          = "oidc_auth"
        oidc_name          = "Pocket ID"
        oidc_endpoint      = "https://id.${domain}"
        oidc_client_id     = pocketid_client.harbor.id
        oidc_client_secret = pocketid_client.harbor.client_secret
        oidc_groups_claim  = "groups"
        oidc_admin_group   = "Admin"
        oidc_scope         = "openid,profile,email"
        oidc_verify_cert   = true
        oidc_auto_onboard  = true
        oidc_user_claim    = "preferred_username"
      })}'';
  };
}
