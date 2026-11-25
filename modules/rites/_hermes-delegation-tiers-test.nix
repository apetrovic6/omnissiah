# Eval check for the Hermes delegation tiers guard rails (README "Hermes delegation tiers"). Runs as
# the flake check checks.x86_64-linux.hermes-delegation-tiers; by hand:
#   nix eval --impure --json .#nixosConfigurations.ryza --apply \
#     'ryza: import ./modules/rites/_hermes-delegation-tiers-test.nix { inherit ryza; }'
#
# Each case extends ryza with one bad setting and expects the named assertion to fail; ryza itself
# must fail none of them. Only `config.assertions` is evaluated, never a build.
{ryza}: let
  inherit (ryza.pkgs) lib;
  failed = module: map (a: a.message) (builtins.filter (a: !a.assertion) (ryza.extendModules {modules = [module];}).config.assertions);
  delegationFailures = module: builtins.filter (lib.hasInfix "delegation") (failed module);
  tier = extra:
    {
      name = "probe";
      description = "probe";
      model = "m";
    }
    // extra;
  # name -> { module; expect = substring of the assertion message that must fail }
  cases = {
    # A typed work tier on a personal provider (the root Codex grant).
    workTierProvider = {
      module = {lib, ...}: {services.imperium.hermes.profiles.work.delegation.tiers = lib.mkForce [(tier {provider = "openai-codex";})];};
      expect = "work bills only the DevZero token";
    };
    # The default backend routes by delegation.provider: never from settings.
    workSettingsProvider = {
      module = {services.imperium.hermes.profiles.work.settings.delegation.provider = "openai-codex";};
      expect = "settings.delegation sets provider";
    };
    workSettingsProfile = {
      module = {services.imperium.hermes.profiles.work.settings.delegation.profile = "default";};
      expect = "work bills only the DevZero token";
    };
    workAllowlist = {
      module = {lib, ...}: {services.imperium.hermes.profiles.work.delegation.allowedProviders = lib.mkForce ["anthropic"];};
      expect = "work bills only the DevZero token";
    };
    coderAuto = {
      module = {lib, ...}: {
        services.imperium.hermes.profiles.coder.delegation = {
          allowedProviders = lib.mkForce ["anthropic" "auto"];
          tiers = lib.mkForce [(tier {provider = "auto";})];
        };
      };
      expect = "auto and custom are not providers";
    };
    coderOutsideAllowlist = {
      module = {lib, ...}: {services.imperium.hermes.profiles.coder.delegation.allowedProviders = lib.mkForce ["anthropic"];};
      expect = "must be in allowedProviders";
    };
    coderBadDefault = {
      module = {lib, ...}: {services.imperium.hermes.profiles.coder.delegation.default = lib.mkForce "nope";};
      expect = "must name one of its tiers";
    };
    coderDuplicate = {
      module = {lib, ...}: {services.imperium.hermes.profiles.coder.delegation.tiers = lib.mkAfter [(tier {name = "plan";})];};
      expect = "tier names must be unique";
    };
    coderParentFallback = {
      module = {lib, ...}: {
        services.imperium.hermes.profiles.coder.delegation.tiers = lib.mkAfter [
          (tier {
            fallback = [
              {
                provider = "anthropic";
                model = "m";
              }
            ];
          })
        ];
      };
      expect = "cannot have a fallback";
    };
  };
  results = lib.mapAttrs (_: case: delegationFailures case.module) cases;
  baseline = delegationFailures {};
  missed = lib.filterAttrs (name: messages: !lib.any (lib.hasInfix cases.${name}.expect) messages) results;
in
  assert lib.assertMsg (baseline == []) "ryza fails delegation assertions: ${lib.concatStringsSep "; " baseline}";
  assert lib.assertMsg (missed == {}) "delegation guard not enforced for: ${lib.concatStringsSep ", " (lib.attrNames missed)}"; {
    inherit baseline results;
  }
