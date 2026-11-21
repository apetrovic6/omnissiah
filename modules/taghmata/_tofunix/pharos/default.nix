# Pocket ID (id.noosphere.uk): groups and users. The OIDC clients are in
# ./clients.nix.
{
  ref,
  relic,
  ...
}: {
  imports = [./clients.nix];

  # A second file of the same generator: one person's details.
  reliquary.pocket_lu_user = {
    generator = "tofunix-pocketid-lu";
    file = "tofunix-pocketid-secret";
  };

  resource.pocketid_group = {
    admin = {
      name = "Admin";
      friendly_name = "Administrators";
    };
    argocd_admins = {
      name = "ArgoCDAdmins";
      friendly_name = "ArgoCD Admins";
    };
    users = {
      name = "User";
      friendly_name = "Users";
    };
    developers = {
      name = "developers";
      friendly_name = "Developers";
    };
  };

  resource.pocketid_user.lu = {
    username = relic "pocket_lu_user" "username";
    email = relic "pocket_lu_user" "email";
    first_name = relic "pocket_lu_user" "first_name";
    last_name = relic "pocket_lu_user" "last_name";
    groups = [ref.pocketid_group.users.id ref.pocketid_group.developers.id];
  };
}
