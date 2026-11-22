# What is specific to the taghmata cluster in its nixidy setup. The generic
# flake-parts support is ./flake-module.nix.
{
  lib,
  config,
  ...
}: let
  global = config.noosphere;
  ingress = import ./_modules/ingress.nix {inherit lib;};
  vars = import ../../cartographa/_vars.nix;

  # The SSO URL, derived from provider and domain unless it is set.
  ssoUrl =
    if global.sso.url != ""
    then global.sso.url
    else if global.sso.provider != "" && global.domain != ""
    then "${lib.toLower global.sso.provider}.${global.domain}"
    else "";
in {
  nixidy = {
    repository = "https://github.com/apetrovic6/omnissiah.git";
    branch = "master";

    modules = [
      # `noosphere.*` (domain, SSO), with the flake's values
      ./_modules/noosphere-options.nix

      # `garage.keys`: S3 keys and buckets, declared by the application that uses them
      ./_modules/garage-keys.nix

      ({lib, ...}: {
        noosphere.domain = lib.mkDefault global.domain;
        noosphere.sso.provider = lib.mkDefault global.sso.provider;
        noosphere.sso.wellKnownUrl = lib.mkDefault global.sso.wellKnownUrl;
        noosphere.sso.url = lib.mkDefault ssoUrl;
      })
    ];

    # Options this repo adds to every application.
    applicationImports = [
      (import ./_modules/sops-secrets.nix {inherit vars;})
      ingress.module
    ];

    # The network chart and the vars store (modules/cartographa), and the
    # ingress annotation helper, as arguments of every module.
    extraSpecialArgs = {
      cartographa = import ../../cartographa/_cartographa.nix;
      inherit vars;
      inherit (ingress) ingressAnnotations;
    };

    # The applications are under ./apps, each declaring itself with
    # `nixidy.envs.prod.apps.<name>`.
    envs.prod = {
      modules = [
        {
          nixidy.defaults.syncPolicy.autoSync = {
            enable = true;
            prune = true;
            selfHeal = false;
          };
        }
      ];
      # The sources are in modules/taghmata, the rendered manifests are not:
      # see modules/noosphere/taghmata/README.md.
      rootPath = "modules/noosphere/taghmata/nixidy/manifests/prod";
    };
  };

  perSystem = {...}: {
    nixidy.crds = {
      outputPath = "modules/taghmata/nixidy/_generated";
      generatedDir = ./_generated;
    };
  };
}
