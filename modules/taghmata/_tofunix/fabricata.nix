# Fabricata: forge and registry wiring for every rust-app-template product in
# ../_products.nix.
#
# Per product:
#   - the repo on forge.ugalabugala.org (the cerberus Forgejo, where the template lives);
#   - a Harbor project of the same name;
#   - a project-scoped robot, `<product>-ci`, that pushes and pulls;
#   - HARBOR_USERNAME/HARBOR_PASSWORD as REPO action secrets, which the template's publish step
#     maps into `just publish::push`. Never user-level: those would reach the template repo.
#   - for a product with `auth`, a public Pocket ID client named after the product.
{
  config,
  lib,
  products,
  ref,
  relic,
  ...
}: let
  inherit (config.scriptorium) owner;
  sops = name: "robot_${name}";
  robot = name: "${name}-ci";

  # { <key name> = <value name product>; } for every product.
  each = key: value: lib.mapAttrs' (name: product: lib.nameValuePair (key name) (value name product)) products;
  byName = each (name: name);

  actionSecret = suffix: secretName: data:
    each (name: "${name}-${suffix}") (name: _: {
      provider = "forgejo.cerberus";
      inherit owner;
      repository = ref.forgejo_repository.${name}.name;
      name = secretName;
      data = data name;
    });
in {
  # One generated secret per product (../reliquary/tofunix/product-robot-secrets.nix).
  reliquary = each sops (name: _: {generator = "tofunix-harbor-robot-${name}";});

  scriptorium.repos = byName (_: product: {
    forge = "cerberus";
    inherit (product) description;
  });

  scriptorium.robots = each robot (name: _: {
    description = "CI push for ${name} (forge.ugalabugala.org/${owner}/${name})";
    secret = relic (sops name) "robot_secret";
    project = "${ref.harbor_project.${name}.name}";
  });

  resource.harbor_project = byName (name: product: {
    inherit name;
    inherit (product) public;
    vulnerability_scanning = true;
    auto_sbom_generation = true;
  });

  resource.forgejo_repository_actions_secret =
    actionSecret "harbor-username" "HARBOR_USERNAME" (name: ref.harbor_robot_account.${robot name}.full_name)
    // actionSecret "harbor-password" "HARBOR_PASSWORD" (name: relic (sops name) "robot_secret");

  # A public OIDC client for each product with `auth`, client_id = the product name, so there is
  # no secret to keep: the service checks access tokens (aud = client_id) and the clients log in
  # with PKCE. `http://127.0.0.1/callback` is the native desktop loopback redirect, and Pocket ID
  # ignores the port for loopback, so that single entry covers any port. A product without
  # `auth` gets nothing.
  resource.pocketid_client =
    lib.mapAttrs (name: product: let
      hosts = product.auth.webHosts;
    in {
      inherit name;
      client_id = name;
      is_public = true;
      pkce_enabled = true;
      callback_urls =
        (map (host: "https://${host}/auth/callback") hosts)
        ++ ["http://127.0.0.1/callback"];
      logout_callback_urls = map (host: "https://${host}") hosts;
      launch_url = "https://${lib.head hosts}";
      allowed_user_groups = [ref.pocketid_group.users.id];
    })
    (lib.filterAttrs (_: product: product ? auth) products);
}
