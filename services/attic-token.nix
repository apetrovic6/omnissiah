  {...}:
{  clan.core.vars.attic-pull-token = {
    description = "Attic pull-only token for accessing the binary cache.";
    secret = true;  # mark as secret so clan treats it as sensitive
    # type = "string";  # if `type` is supported; usually the default is fine
  };
}
