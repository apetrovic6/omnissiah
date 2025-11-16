{ ... }: {
  clan.core.vars.attic-pull-token = {
    description = "Attic pull-only token for accessing the binary cache.";
    secret = true; # clan treats this as sensitive
    # type = "string"; # optional if you want to be explicit
  };
}

