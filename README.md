# Omnissiah

A [clan](https://clan.lol) NixOS flake for the homelab: workstations, the home
server, two VPSes and the `taghmata` RKE2 cluster. Everything is named after
Warhammer 40,000's Adeptus Mechanicus; the lexicon below maps the names to
what they do.

## Lexicon

### Directories

| Name | Meaning here |
|---|---|
| `machines/` | One directory per host: its own configuration, disk layout and hardware report |
| `stc/` | Standard Template Constructs: clan services used as roles, attached to machines by tag in `inventory/machines.nix` and registered as `@imperium/<role>` in `clan.nix` |
| `modules/rites/` | Reusable NixOS modules, each exported as `nixosModules.<name>` |
| `modules/litanies/` | `flake.lib` helper functions |
| `modules/noosphere/` | Self-hosted services, grouped by domain (below) |
| `modules/manufactorum/` | What the flake builds for itself: checks, packages, the dev shell and formatter |
| `modules/cartographa/` | The chart of the estate: host and network addresses (`_chart.nix`), flake-wide values such as the domain and SSO provider, paths into the vars store, and shared clan vars |
| `overlays/` | Nixpkgs overlays, exported as `overlays.<name>` |
| `services/` | Packages built from source in this repo |
| `users/` | Home Manager configuration |
| `relics/` | Vendored binary assets: wallpapers, the Rocksmith DLL |
| `rituals/` | Operational scripts run by hand |
| `vars/`, `sops/` | Clan-managed secrets and generated values; do not edit by hand |

Everything under `modules/` and `overlays/` is loaded automatically by
`import-tree` as a flake-parts module. Files and directories whose name starts
with `_` are skipped and must be imported explicitly.

### Noosphere domains

| Name | Holds |
|---|---|
| `pharos` | Edge and access: Caddy, Pangolin, CrowdSec, Technitium DNS, Vaultwarden |
| `librarium` | Media libraries: Plex, Tautulli, Immich, Navidrome, Audiobookshelf |
| `munitorum` | Acquisition: SABnzbd, NZBHydra |
| `lexicanum` | Search: SearXNG |
| `scriptorium` | Code hosting: Forgejo |
| `vox` | Messaging: Matrix, ntfy |
| `taghmata` | The Kubernetes cluster: RKE2 node modules (`rke2/`), secret generators (`reliquary/`), nixidy apps (`nixidy/`), OpenTofu config (`_tofunix/`) |

### Machines

| Name | What it is |
|---|---|
| `phalanx` | Desktop workstation, also runs local LLM inference |
| `enginseer` | Laptop workstation |
| `genetor` | macOS machine (nix-darwin) |
| `cerberus` | Home server: DNS, reverse proxy, Forgejo, PostgreSQL, media, Home Assistant |
| `cypramundi` | VPS running the Pangolin reverse proxy and Matrix |
| `alfrost` | VPS |
| `terra`, `luna`, `sol` | `taghmata` control-plane nodes; terra bootstraps the cluster |
| `mars` | `taghmata` control-plane node that takes no workloads |
| `servitor` | Banana Pi BPI-M5, arm64 `taghmata` worker |

### Modules

Each noosphere domain is one NixOS module, `nixosModules.<domain>`, holding
option-gated wrappers: importing it declares `services.imperium.*` options and
enables nothing. Three exports are different:

| Module | What it is |
|---|---|
| `noosphere` | Only the `noosphere.*` options (domain, SSO, age key) |
| `taghmata` | The RKE2 server/agent wrappers, the node token and the registry cache |
| `reliquary` | Generators for secrets that only the cluster consumes. Imported by the `taghmata` servers, so `clan vars generate terra` creates them |
| `reliquary-kaneo`, `-memos`, `-ntfy`, `-ncps` | Generators for secrets shared between the cluster and a host. Each is imported by the module that consumes it on the host side |
| `vox-matrix` | The Matrix homeserver. Not option-gated: importing it runs Synapse |

### Litanies

Helpers under `self.lib` (`modules/litanies`):

| Helper | Use |
|---|---|
| `mkSopsGenerators pkgs { <name> = {...}; }` | Clan vars generators that produce one sops-encrypted document: a `SopsSecret` for the cluster when `namespace` is set, a plain document for OpenTofu otherwise. Values come from `random`, `prompts` or a `setup` script. Documented in `_sops-generators.nix` |
| `mkImperiumService { inherit lib pkgs; name = "..."; }` | The options every `services.imperium.<name>` wrapper shares |
| `mkDomain`, `mkRevProxyVHost` | A Caddy virtual host on the lab domain |
| `hosts`, `lan`, `vips`, `vars` | The network chart and vars paths (below) |

### Option namespaces

- `services.imperium.<name>`: this repo's own service wrappers.
- `noosphere.*`: flake-wide values such as the base domain and SSO provider.

## Working with it

```sh
clan machines update <machine>          # deploy
clan vars generate <machine>            # create missing secrets
nix build .#checks.x86_64-linux.<machine>
nix fmt
```

`checks` contains every NixOS machine for the system, so new machines are
built by CI without being listed anywhere.

## Addresses and secrets paths

No module writes an IP address or a `../../vars/...` path itself. Both come
from `modules/cartographa`:

| Where | Addresses | Vars files |
|---|---|---|
| NixOS and Home Manager modules | `self.lib.hosts.cerberus`, `self.lib.lan.gateway`, `self.lib.vips.traefik` | `self.lib.vars.shared "<generator>" "<file>"` |
| nixidy apps | the `cartographa` module argument | the `vars` module argument |
| OpenTofu config, clan inventory | `import .../cartographa/_cartographa.nix` | the same import's `vars` |

A new host or device gets one line in `modules/cartographa/_chart.nix`.
