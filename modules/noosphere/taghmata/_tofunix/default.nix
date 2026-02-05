{ref, ...}: {
  imports = [
    ./harbor
    ./forgejo
  ];

  provider.sops.default = {};
}
