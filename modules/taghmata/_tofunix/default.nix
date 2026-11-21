# The OpenTofu configuration of the estate: what exists on the forges, in the
# registry and in the identity provider. Built into the `tofunix` CLI by
# ../tofunix.nix, which also passes in `noosphere`, `vars` and `products`.
#
#   conduits.nix   every provider and the credential it logs in with
#   patterns/      options that stamp out the resources repeated per item
#   scriptorium/   code hosting: both forges, their GitHub mirrors, Harbor
#   pharos/        identity: Pocket ID groups, users and OIDC clients
#   fabricata.nix  per-product wiring, from ../_products.nix
#
# The state holds resources by type and name (`forgejo_repository.nvf`),
# never by file, so moving a declaration between these files changes nothing.
# `nix build .#tofunix.tfjson` prints the generated configuration; an
# unchanged store path means an unchanged plan.
{
  imports = [
    ./conduits.nix
    ./patterns/reliquary.nix
    ./patterns/repos.nix
    ./patterns/robots.nix
    ./patterns/clients.nix
    ./scriptorium/forge-noosphere.nix
    ./scriptorium/forge-cerberus.nix
    ./scriptorium/harbor.nix
    ./pharos
    ./fabricata.nix
  ];

  terraform.backend.s3 = {
    bucket = "opentofu";
    key = "terraform.tfstate";
    region = "main";
    endpoints.s3 = "https://s3.main.garage.noosphere.uk";
    skip_credentials_validation = true;
    skip_requesting_account_id = true;
    skip_metadata_api_check = true;
    skip_region_validation = true;
    use_path_style = true;
  };
}
