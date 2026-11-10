# Products generated from rust-app-template, and the registry/forge wiring each one gets.
#
# Plain data, read by:
#   - tofunix-product-robot-secrets.nix: one generated Harbor robot secret per product
#   - _tofunix/products: the Forgejo repo on forge.ugalabugala.org, the Harbor project, the
#     project-scoped robot, the repo's HARBOR_USERNAME/HARBOR_PASSWORD action secrets, and, for
#     a product with `auth`, a public Pocket ID client
#
# The secrets are set on the REPO, never on the user: user-level secrets reach every repo of
# `manjo`, rust-app-template included, and the template must never push its own images.
#
# Adding a product: add it here, `clan vars generate` (its robot secret), then tofunix apply.
{
  pilot = {
    description = "M1 pilot: a rust-app-template product deployed to taghmata and cerberus";
    # Pull without credentials: RKE2 nodes already reach harbor.noosphere.uk anonymously, and
    # Harbor is homelab-only. Private projects + a pull secret are deferred.
    public = true;

    # A public OIDC client in Pocket ID, client_id = the product name (no secret anywhere):
    # the service checks access tokens (aud = client_id), the clients log in with PKCE.
    auth.webHosts = ["pilot.noosphere.uk"];
  };
}
