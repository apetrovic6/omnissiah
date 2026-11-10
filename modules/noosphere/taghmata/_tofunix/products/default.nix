# Forge and registry wiring for every rust-app-template product in ../../_products.nix.
#
# Per product:
#   - the repo on forge.ugalabugala.org (the cerberus Forgejo, where the template lives);
#   - a Harbor project of the same name;
#   - a project-scoped robot with push and pull (skopeo checks for existing blobs, which needs
#     pull);
#   - HARBOR_USERNAME/HARBOR_PASSWORD as REPO action secrets, which the template's publish step
#     maps into `just publish::push`. Never user-level: those would reach the template repo.
#   - for a product with `auth`, a public Pocket ID client named after the product.
#
# builtins only, and a fixed top-level shape: `pkgs`/`lib` arrive through `_module.args`, so
# computing this module's attribute names from them is an infinite recursion.
{ref, ...}: let
  products = import ../../_products.nix;
  owner = "manjo";
  # `ref` covers resources, data, vars and locals but not providers, so the alias is spelled out.
  cerberusForge = "forgejo.cerberus";

  sops = name: "robot_${name}";
  robot = name: "${name}-ci";
  robotSecret = name: "\${data.sops_file.${sops name}.data[\"robot_secret\"]}";

  # { <key name> = <value>; } for every product.
  each = key: value:
    builtins.listToAttrs (map (name: {
      name = key name;
      value = value name products.${name};
    }) (builtins.attrNames products));
  byName = each (name: name);
in {
  data.sops_file = each sops (name: _: let
    var = "tofunix-harbor-robot-${name}";
  in {
    source_file = toString ../../../../../vars/shared/${var}/${var}/value;
    input_type = "yaml";
  });

  resource.forgejo_repository = byName (name: product: {
    provider = cerberusForge;
    inherit name;
    inherit (product) description;
    private = false;
    default_branch = "master";
    has_pull_requests = true;
    has_actions = true;
    has_issues = true;
  });

  resource.harbor_project = byName (name: product: {
    inherit name;
    inherit (product) public;
    vulnerability_scanning = true;
    auto_sbom_generation = true;
  });

  resource.harbor_robot_account = each robot (name: _: {
    name = robot name;
    description = "CI push for ${name} (forge.ugalabugala.org/${owner}/${name})";
    level = "project";
    secret = robotSecret name;
    permissions = [
      {
        access = [
          {
            action = "push";
            resource = "repository";
          }
          {
            action = "pull";
            resource = "repository";
          }
        ];
        kind = "project";
        namespace = ref.harbor_project.${name}.name;
      }
    ];
  });

  resource.forgejo_repository_actions_secret =
    each (name: "${name}-harbor-username") (name: _: {
      provider = cerberusForge;
      inherit owner;
      repository = ref.forgejo_repository.${name}.name;
      name = "HARBOR_USERNAME";
      data = ref.harbor_robot_account.${robot name}.full_name;
    })
    // each (name: "${name}-harbor-password") (name: _: {
      provider = cerberusForge;
      inherit owner;
      repository = ref.forgejo_repository.${name}.name;
      name = "HARBOR_PASSWORD";
      data = robotSecret name;
    });

  # A public OIDC client for each product with `auth`, client_id = the product name, so there is
  # no secret to keep: the service checks access tokens (aud = client_id) and the clients log in
  # with PKCE. `http://127.0.0.1/callback` is the native desktop loopback redirect, and Pocket ID
  # ignores the port for loopback, so that single entry covers any port. A product without
  # `auth` gets nothing.
  resource.pocketid_client = builtins.listToAttrs (map (name: {
    inherit name;
    value = let
      hosts = products.${name}.auth.webHosts;
    in {
      inherit name;
      client_id = name;
      is_public = true;
      pkce_enabled = true;
      callback_urls =
        (map (host: "https://${host}/auth/callback") hosts)
        ++ ["http://127.0.0.1/callback"];
      logout_callback_urls = map (host: "https://${host}") hosts;
      launch_url = "https://${builtins.head hosts}";
      allowed_user_groups = [ref.pocketid_group.users.id];
    };
  }) (builtins.filter (name: builtins.hasAttr "auth" products.${name}) (builtins.attrNames products)));
}
