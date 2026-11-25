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
| `modules/taghmata/` | The Kubernetes cluster: RKE2 node modules (`rke2/`), secret generators (`reliquary/`), nixidy apps (`nixidy/`), OpenTofu config (`_tofunix/`). Its rendered manifests are the one thing left under `modules/noosphere/taghmata/`, where ArgoCD reads them |
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

### Machines

| Name | What it is |
|---|---|
| `phalanx` | Desktop workstation, also runs local LLM inference |
| `enginseer` | Laptop workstation |
| `genetor` | macOS machine (nix-darwin) |
| `cerberus` | Home server: DNS, reverse proxy, Forgejo, PostgreSQL, media, Home Assistant |
| `cypramundi` | VPS running the Pangolin reverse proxy and Matrix |
| `alfrost` | VPS |
| `terra`, `luna`, `sol` | Bare-metal `taghmata` nodes: control plane and workloads. terra founded the cluster |
| `mars` | `taghmata` control-plane node (Proxmox VM) that takes no workloads |
| `servitor` | Banana Pi BPI-M5 single-board computer; not part of the cluster |
| `stygies` | Persistent Proxmox dev VM for the operator and the unprivileged Hermes SSH user |

### The taghmata cluster roles

`stc/taghmata.nix` is one clan service with two roles, assigned by the machine
tags of the same name in `inventory/machines.nix`. Every node also carries the
`taghmata` tag, so `clan machines update --tags taghmata` rolls the cluster and
`--tags fabricator` only the control plane. A machine may hold either role or
both:

| Roles held | What the machine runs |
|---|---|
| `fabricator` + `skitarii` | RKE2 server that also takes workloads (terra, luna, sol) |
| `fabricator` | RKE2 server, tainted so only the control plane runs there (mars) |
| `skitarii` | RKE2 agent (nobody yet) |

`fabricator` is the control plane: etcd, the ArgoCD chart, the cluster's secret
generators. `skitarii` brings what workloads need from the host: the Longhorn,
iSCSI and NFS helpers and the swap file. Nodes register with the founder
(terra) unless `roles.fabricator.settings.joinAddress` is set.

### Modules

Each noosphere domain is one NixOS module, `nixosModules.<domain>`, holding
option-gated wrappers: importing it declares `services.imperium.*` options and
enables nothing. Three exports are different:

| Module | What it is |
|---|---|
| `noosphere` | Only the `noosphere.*` options (domain, SSO, age key) |
| `taghmata` | The RKE2 server/agent wrappers, the node token and the registry cache |
| `impermanence` | An ephemeral root: `services.imperium.impermanence` takes the system and per-user paths that survive a reboot and resets the root from a blank btrfs snapshot in the initrd. It can be imported from several modules at once, so a module that keeps state imports it and declares its own paths (`strata`, `awscli`, `proaudio`). apetrovic's personal list is `users/apetrovic/persistence.nix` |
| `workstation-host` | What phalanx and enginseer share as hosts: encrypted btrfs root, secure boot, impermanence, NVIDIA settings, NAS shares. The desktop and tooling come from the `workstation` role |
| `taghmata-node` | What the bare-metal cluster machines share as hosts: static address, CI runner. `machines/{terra,luna,sol}` set only what differs; their disk layout is `taghmata/_node-disko.nix` |
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

### Local inference (Strata)

`nixosModules.strata` (`modules/rites/strata/default.nix`) exposes
`services.imperium.strata`. It builds the pinned CUDA engine and Python API
server once per CUDA target and runs a `strata.service` user unit, restricted
to the configured account. Importing the module alone enables nothing.

| Host | Model | GPU | CUDA target | Context | Idle unload |
|---|---|---|---|---|---|
| `phalanx` | Flash-Next IQ3_XXS | 1 | 8.6 | 262144 | 3600 seconds |
| `enginseer` | Flash-Next Coder IQ1_M | 0 | 8.9 | 32768 | 900 seconds |

Host choices live in `machines/<host>/strata.nix`. Phalanx retains its existing
model ID, paths and measured tuning. Enginseer's Coder configuration is a
starting point, not a measured performance or memory-fit guarantee.

```nix
imports = [self.nixosModules.strata];
nixpkgs.config.cudaCapabilities = ["8.9"];
services.imperium.strata = {
  enable = true;
  user = "apetrovic";
  family = "coder"; # defaults to IQ1_M; qwen defaults to IQ3_XXS
  gpu = 0;
  maxContext = 32768;
  idleUnload = 900;
};
```

Other knobs include `quant`, `modelName`, `port`, `dataDir`, `pack`, `native`,
`ple`, `mtp`, `expertProfile`, `kvResident`, `kvType`, `prefill`, `specTokens`,
`lazy`, `minFreeVramMiB` and `extraArgs`. Coder selects its own expert profile;
the full-model profile must not be reused for its pruned expert layout.

**Prepare model data before deploying to a new host.** Nix does not download
weights or prepare packs. Use a writable checkout of the Strata version pinned
in `flake.nix`, following its source-install instructions. For enginseer,
run its setup as `apetrovic` with:

```sh
./setup.sh --setup --family coder --model IQ1_M \
  --data-dir /home/apetrovic/models/strata-data \
  --context 32768 --vision no --no-start
```

The expected data layout is `packs/coder-iq1_m/` (including `tokenizer/`),
`models/coder-IQ1_M/Qwen3.8-Flash-Next-GSQ-RCO-IQ1_M-0000{1,2}-of-00002.gguf`,
and `mtp/rt/` beneath that data directory. Setup may reuse files elsewhere;
override the module's paths if its prepared files are not in this layout.
Upstream setup pins model revisions independently of the engine release;
its Coder weights may predate the latest model-card benchmark.

After preparation, deploy with `clan machines update <host>`. The user service
uses Nix-built binaries, not setup's generated launch script. Its lazy API is
at `http://127.0.0.1:8000/v1`; no firewall port is opened. Configure clients
with the advertised ID: `qwen3.8-flash-next-iq3_xxs` on phalanx or
`qwen3.8-flash-next-coder-iq1_m` on enginseer.

As the configured user:

```sh
systemctl --user status strata
journalctl --user -u strata
curl http://127.0.0.1:8000/v1/models
```

The generated config is linked into `~/.local/state/strata`, where the server
also writes settings and logs. On a machine with an ephemeral root the module
persists `.config/strata` and `.local/state/strata` for the configured user.
The model data is not the module's to keep: `models` is persisted for
`apetrovic` by `users/apetrovic/persistence.nix`, and another user or a custom
`dataDir` needs its own entry. To update the
engine, change the Strata input and its matching llama.cpp pin together.

### Hermes coder profile (ryza → stygies)

The ryza gateway serves `coder` only after a host key is pinned. Its terminal
tools run over SSH as `hermes` in `~/work` on stygies.

1. Generate `hermes-stygies-ssh` on ryza with
   `clan vars generate ryza --generator hermes-stygies-ssh`. Stygies needs only
   the generated public half.
2. Install stygies. ryza pins its host key automatically from stygies's
   `openssh` clan var (`services.imperium.hermes.stygies.knownHosts`). Until
   that var exists the pin is empty, which leaves the private key root-only
   and disables the coder profile and its Matrix routes without deleting
   existing profile data.
3. Create one Matrix room per project and invite the existing bot. Under
   `projects` in `machines/ryza/_coder-projects.nix`, add the repo basename
   with `forge = "cerberus"` or `forge = "noosphere"` and `room = "!…"`, using
   the room's internal ID, not an alias. For a repo not owned by `manjo`, add
   `owner = "<user or org>"`; Hermes forks it to `hermes/<repo>` and opens PRs
   into `<owner>/<repo>`. A `noosphere` project is a Nix
   evaluation error until `forges.noosphere.botEnabled` is `true` (see
   [Hermes on noosphere Forgejo](#hermes-on-noosphere-forgejo)). Ryza uses this map for Matrix routing
   and the coder prompt; Stygies uses its keys to validate app claims.
   Each room is its own conversation; start a thread per task for a fresh one.

In Hermes Mobile, pick `coder`, open one chat per task, and name the exact repo
from the coder project map. App chats and Matrix threads share one slot and
queue; both require explicit plan approval. If queued, return to the same chat
or thread and say `continue`. There is no push notification. If the app task ID
is lost, use `clear task` only for a confirmed active task. For a queued task,
confirm its project and `queued_at` from the queued reply, then say
`drop queued <queued_at>` instead; this leaves the active task alone.

On ryza as `hermes`, use `hermes -p coder model` to select a provider and
`hermes -p coder --tui` to start a session. `hermes -p coder webapp` selects the
same profile if the gateway's Webapp listener is enabled. Interactive config
changes outside Nix-managed settings survive activation.
The coder's `SOUL.md` is managed by Nix; a switch or gateway restart
overwrites edits to that file. **Deploy stygies before ryza.** On stygies as
`hermes`, first check that `task-status -- '!x:y' '$z'` succeeds. Existing chats
and threads pick up a changed SOUL or profile setting on their next turn,
history kept: the `hermes-refresh-prompts` unit runs
`hermes -p <profile> sessions refresh-prompts` once for each managed profile
(`coder`, `work`) whose SOUL or Nix settings changed, after the new file is in
place. A failure doesn't fail the deploy; it is logged
(`journalctl -u hermes-refresh-prompts`) and retried on the next switch or
gateway start. Don't reset an active or queued chat to pick up the prompt.

**App projects** need stygies paths: create them in the app with an absolute
`/home/hermes/work/<repo>` path. Hermes resolves `~` and relative paths on ryza
(`~/work/x` becomes `/var/lib/hermes/work/x`), which doesn't exist on stygies.
A patched Hermes (`services.imperium.hermes.sshHostOnlyPaths`, default
`/var/lib/hermes`) runs such a project's commands in the profile's
`terminal.cwd` (`~/work`) instead of failing every one, and logs
`ssh working directory … exists only on the Hermes host` in `agent.log`. Fix the
project's path rather than relying on that.

Before rolling stygies back, stop submitting new app tasks and use
`task-status --queue` on stygies to check both the active slot and the queue.
Finish or clear any active app task and drop any remaining queued app entries
with `task-drop -- '<position>' '<queued_at>'`. Refresh the queue listing before
each drop. Older tools cannot read app rows.

**Kaneo login:** Use a Kaneo account with access to the project workspace.
A separate workspace member for Hermes is recommended so its edits are
attributable; an existing member account works too. From phalanx, open a
tunnel and keep the SSH session open:

```sh
ssh -o ExitOnForwardFailure=yes -L 28431:127.0.0.1:28431 root@192.168.1.45
```

On ryza, run the login as `hermes`:

```sh
sudo -iu hermes hermes -p coder mcp login kaneo --flow browser
```

Open the printed URL in a browser on phalanx and approve access. If the
tunnel is unavailable, paste the final browser redirect URL into the Hermes
login prompt. Restart `hermes-gateway` only if the tools don't appear within a
minute after login.

[Kaneo issues a 30-day access token](https://github.com/usekaneo/kaneo/blob/v2.48.0/apps/api/src/mcp/oauth.ts#L151-L161)
without a refresh token. Check `expires_at` in `mcp-tokens/kaneo.json` under the
persisted coder profile. Repeat the browser login when it expires. Until
reauthorized, Hermes tells the task's chat or thread that the board is
unreachable and keeps working without Kaneo.

**Emergency stop:** Send `/pause` in the default bot DM to hold new work
across profiles; `/pause off` resumes. Existing work is not killed. For a hard
stop, pause first, stop `hermes-gateway` on ryza, and kill the remote `hermes`
processes using the same SSH identity. Set `key` to the `terminal.ssh_key` path
from `/var/lib/hermes/.hermes/profiles/coder/config.yaml`:

```sh
sudo systemctl stop hermes-gateway
sudo -u hermes -H ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -i "$key" hermes@192.168.1.248 'exec pkill -KILL -u hermes'
```

The hard stop affects every process owned by `hermes` on stygies; the SSH
connection may drop. If SSH itself is unavailable, use the stygies console.
Restart the gateway and lift the pause when ready.

### Hermes work profile (ryza → stygies)

`work` uses Anthropic Claude Opus 5.5 with the DevZero account in both the
DevZero and Codilas rooms, and in Hermes Mobile. Its terminal runs on stygies
as `hermes` in `~/work-devzero`. It needs the same stygies host pin as `coder`
for that terminal, but does not use the personal task queue or the personal
Claude Code login; its coding tasks use per-company slots (see
[Hermes work coder](#hermes-work-coder-github--gitlab)). The profile and its room routes exist with or without the
pin; without it the terminal, file and code tools are disabled
(`agent.disabled_toolsets`, which always includes `cronjob`), because a room
without a route would be answered by `default` on the personal login.
Prompt refreshes after a SOUL change and app project paths work as for `coder`
(see [Hermes coder profile](#hermes-coder-profile-ryza--stygies)); work's
fallback directory is `~/work-devzero`, and app projects use
`/home/hermes/work-devzero/<company>/<repo key>`.

1. On your PC, confirm the DevZero account and run
   `claude-as devzero setup-token`. Run
   `clan vars generate ryza --generator hermes-work-claude-token` and paste
   only the token at the hidden prompt. Never put it in shell arguments,
   logs, or chat. The token starts with `sk-ant-oat01-` and is about 108
   characters; the check unit rejects anything without that prefix. If the
   hidden prompt mangles the paste (it did on 2026-11-24), copy the token and
   set it from the clipboard instead:
   `wl-paste | tr -d '\n ' | clan vars set ryza hermes-work-claude-token/token`.
2. Deploy stygies first, then ryza. Invite the existing `@hermes` bot to both
   rooms. Refresh the mobile profile picker, select `work`, and start a new
   chat. Use `/new` in either Matrix room if it has earlier context.
3. On ryza, as `hermes`, check both credential pools:
   - `hermes -p work auth list anthropic`: the setup-token env source is
     selected and nothing else is usable.
   - `hermes -p default auth list anthropic`: only the Claude Code source. A
     `manual` or `hermes_pkce` row (from `hermes auth add anthropic` or a
     Hermes OAuth login) would be borrowed by `work`, which has no rows of its
     own, and would outrank its token. Repeat this check after any
     `hermes auth add`.
   - `-p coder` shows the personal Claude Code source, not the work token.
   - `pwd` in the work terminal returns `/home/hermes/work-devzero`.
4. Confirm Anthropic and DevZero permit this use. Compare account usage and
   extra usage in the DevZero and personal Claude accounts before and after
   timestamped Claude turns from the work app and both rooms, then from
   `default` and `coder`. Work should affect only DevZero; the controls
   should affect only personal. A successful reply or a listed OAuth source
   does not prove the billed account or that usage was included in the plan.

#### A missing or bad token fails soft, and alerts

A token that is missing, unreadable, empty or malformed does not stop the
gateway: `default`, `coder`, the Matrix DM and the app keep working. The work
rooms stay routed to `work` and answer with an auth error, never as `default`.
Config and SOUL still apply (they carry `auth.adopt_external_logins: false`).
The dotenv rule: a **missing** file removes the token from work's `.env` (the
var was removed on purpose); any other problem keeps the last good token and
logs the reason (never the token) to the journal of the unit that ran it. A
valid new token is always written, whatever the root pool holds.

`hermes-work-token.service` on ryza is the loud half. It fails when the token
file is missing or invalid, when work's `.env` is not a regular file or does
not hold exactly the provisioned token (the write failed), or when the root
`auth.json` has Anthropic sources other than `claude_code` and `env:*`. It
runs after the gateway starts, at boot, on each switch, and every 15 minutes;
nothing depends on it. When it has been failed for 10 minutes, the
`HermesWorkTokenUnitFailed` alert reaches the phone through Alertmanager and
ntfy. A first deploy before the var exists therefore alerts and makes the
switch report that unit as failed, which is expected until the var is
generated. The alert is in
`modules/taghmata/nixidy/apps/augur/prometheus-stack/hermes-alerts.nix`; it
needs `nix run .#render-prod`, the rendered `PrometheusRule-hermes.yaml`
committed (`nixidyChecks` fails otherwise), and ArgoCD to sync it before it can
fire. To see the state: `systemctl status hermes-work-token`,
`journalctl -u hermes-work-token`. The message tells you which of two cases it
is:

- **Token, or dotenv mismatch** ("work rooms answer with an auth error"): work
  has no working credential. Run `setup-token`, regenerate the var, deploy
  ryza, restart `hermes-gateway` and `hermes-dashboard`.
- **Root credential pool** ("work is BILLING A PERSONAL CREDENTIAL"): a source
  such as `manual` or `hermes_pkce` in the root `auth.json` is borrowed by
  `work` and outranks its token, so work keeps answering, billed to that
  personal credential, right now. A new token does not help. Remove the row
  (`sudo -iu hermes hermes -p default auth list anthropic`, then
  `hermes -p default auth remove anthropic <id>`) or stop the work rooms. This
  is detection only; nothing prevents the borrow.

#### Renewal

Renew ~11 months after creating the token: repeat `setup-token` in the
DevZero account, run the same generator with `--regenerate`, and deploy the
new var to ryza. **A deploy rewrites the dotenv but never restarts the
units**, and built agents keep their credential pool: always run
`systemctl restart hermes-gateway hermes-dashboard` afterwards, then
`systemctl start hermes-work-token` to clear a failed state. Open fresh work
chats and repeat the billing check.

#### Jira and Opsee (MCP)

`work` has two remote MCP servers with browser OAuth: `atlassian`
(`https://mcp.atlassian.com/v1/mcp`, Jira and Confluence for every site the
signed-in account can see) and `opsee` (`https://mcp.api.opsee.ai/mcp`).
Nothing secret is in Nix; the tokens live in the work profile's
`mcp-tokens/`. Both rooms share the one login per server. After deploying
ryza, sign in once with the **work** accounts. From phalanx, tunnel the fixed
callback ports:

```sh
ssh -o ExitOnForwardFailure=yes -L 28432:127.0.0.1:28432 -L 28433:127.0.0.1:28433 root@192.168.1.45
```

and in that session:

```sh
sudo -iu hermes hermes -p work mcp login atlassian --flow browser
sudo -iu hermes hermes -p work mcp login opsee --flow browser
```

Open each printed URL in the browser on phalanx and approve. Without the
tunnel, paste the final redirect URL into the prompt. Restart
`hermes-gateway` only if the tools don't appear within a minute. A
permission error from Atlassian usually means the org admin hasn't allowed
the Atlassian remote MCP server or third-party OAuth apps. If a server stops
issuing refresh tokens, its tools go missing until you repeat its login.

#### Limits to know

- Never `/model` or configure `work` onto another provider: a provider logged
  in under `default` would be borrowed from the root `auth.json` and bill the
  personal account. All `auxiliary.*` slots are pinned to Anthropic Opus 5.5
  for the same reason.
- The cron tool is disabled for `work` (`cronjob` in `agent.disabled_toolsets`):
  a cron `script:` job would run locally on ryza as `hermes`, with the DevZero
  token in its environment, outside the stygies boundary. This stops the agent
  creating jobs; an admin using the CLI or dashboard still could.
- The dashboard's environment page can reveal the work token (`POST
  /api/env/reveal?profile=work`) to any authenticated admin session.
- The work terminal logs in to stygies as the same `hermes` user as `coder`.
  That user has the task tools, the `fj` login and the Forgejo key, and can
  read `~/work`. The SOUL is the only guard; isolating them (a second user and
  key) was explicitly not a goal.

### Hermes work coder (GitHub / GitLab)

From the DevZero and Codilas rooms, or the app with `work` selected, `work`
can take a task such as "fetch DEV-123 from Jira and work on it in `api`"
(the repo key is required unless the company lists only one repo). It plans,
waits for explicit approval, implements on stygies, pushes a branch straight
to the company repo (no forks) and opens a PR (GitHub) or MR (GitLab). It
pushes and posts as **your own accounts**, with narrow tokens.

Companies, their rooms, Jira projects and repo allowlists are in
`machines/ryza/_work-projects.nix`. Both companies start with
`enabled = false`. While a company is off, no Clan var is declared for it (so no
deploy prompts), stygies gets no credentials, CLI wrapper or task commands for
it, and the SOUL says coding isn't set up there. A disabled company that lists
repos fails evaluation.

**What stygies gets per enabled company** (`modules/rites/hermes-work-coder.nix`):

- Two secret vars, owned by `hermes`, mode 0400:
  - `hermes-work-<company>-{github,gitlab}-token` holds the token.
  - `hermes-work-<company>-git-identity` holds your commit `user.name` and
    `user.email` as a Git config fragment. The values never appear in Nix.
- Task commands `<company>-task-{status,claim,branch,done,clear,drop}`. They are
  the personal coder's script with its own slot in
  `~/work-devzero/.tasks/<company>`, the company's room and repo keys as
  allowlists, and branch names checked by `<company>-task-branch`.
- Branch names follow `<type>/<JIRA-KEY>-<slug>`, with `type` one of
  `feature`, `fix` or `chore`. Example: `feature/DEV-123-fix-login`.
- A CLI wrapper: `devzero-gh` or `codilas-glab`.
  - It reads the token from the var for each call and passes it only to that
    child process (`GH_TOKEN`, or `GITLAB_TOKEN` + `GITLAB_HOST`). It also
    turns off telemetry, update checks and prompts.
  - It allows a fixed list of subcommands, and for each a fixed list of flags
    with their arity, parsed the way gh and glab (pflag) parse them. Any other
    subcommand or flag is refused, as are short-flag bundles, attached short
    values, repeated flags and any bare `--`.
  - Allowed: PR/MR create, view, list, diff, checks; top-level comment
    (`pr comment` / `mr note create`); title/body edits and ready; CI reads;
    and `api` as GET only, under a listed repo (`repos/<owner>/<name>/…` or
    `projects/<url-encoded path>/…`) or exactly `api user`.
  - Refused: merge, approve, close, auto-merge, retargeting (`--base`,
    `--target-branch`), inline replies, resolve/edit/delete of notes,
    absolute or `/`-rooted API URLs, GraphQL, and `--jq` that reads the
    environment.
  - Read selectors (`pr view 12`, `mr diff <branch>`, …) must be a number or
    a branch name: a PR/MR URL would override `--repo`. Body files
    (`--body-file`, `--description-file`) must not be or link to a token,
    identity or other secret file.
  - `--repo` must be a listed repo. Every write (create, comment/note,
    edit/update, ready) needs an active task for that repo, and must name the
    task's recorded branch as `--head`/`--source-branch` or as the PR/MR
    selector.
  - The flag list is checked against the real binaries by
    `tests/test_hermes_work_cli_arity.py`; rerun it whenever gh or glab
    changes in nixpkgs.
- Entries in the `hermes` Git config, all read-only:
  - A credential helper per listed repo URL: exact host, `get` only, with the
    path checked against the allowlist.
  - An `includeIf` per repo for the identity file and `push.default = nothing`.
  - `http.followRedirects = false`, so a redirect can't carry a company token
    to a URL the guard never judged.
  - A global `pre-push` hook (`hook.hermes-work-guard`) that refuses any push
    to a company host except one that meets all of these:
    - it uses exactly `https://<host>/<path>.git` or `https://<host>/<path>`
      for a listed repo (the forms the `includeIf` matches);
    - it pushes the branch recorded for that company's active task, for that
      repo;
    - that branch is not the default branch (needs
      `git remote set-head origin --auto`);
    - it is fast-forward only: no deletes, tags or force-pushes;
    - every pushed commit that isn't already on the remote has an author
      and committer email equal to the identity file's (empty emails
      refused). Merging the default branch is fine: its commits are on the
      remote already. A missing identity var refuses the push.

  It also refuses HTTP(S) pushes to any host that is neither a company host
  nor one of the personal forges in `_coder-projects.nix`. Pushes to the
  personal forges, SSH hosts other than the companies', and local paths
  pass, so the personal coder's Forgejo pushes are unaffected.

**Limits.** These are guard rails against mistakes, not a sandbox. The agent
runs as `hermes`, which can read the token files, call the store `gh`/`glab`
directly, or skip the guard with `--no-verify`, `hook.pre-push.enabled=false`,
`hook.hermes-work-guard.enabled=false` or
`git -c hook.hermes-work-guard.command=true`. The SOUL forbids all of these.
glab also still reads hermes's `~/.config/glab-cli/config.yml` (aliases, debug,
per-host `api_protocol`): glab 1.130 has no config-dir variable, and moving
`XDG_CONFIG_HOME` would hide Hermes's Git config from the Git that glab runs.
Only a deliberately pre-seeded file there matters. **Company
branch protection is the backstop**: confirm the default branch of every listed
repo is protected (GitHub ruleset or branch protection; GitLab protected
branch) before enabling. A GitHub fine-grained PAT with Contents write can merge
PRs, and a GitLab `api` token can do anything your account can.

#### Enabling a company (runbook)

1. **Create the token** with your own account.
   - **DevZero (GitHub):**
     1. Go to Settings → Developer settings → Fine-grained tokens. Set
        resource owner **DevZero**.
     2. Choose *Only select repositories* and pick the repos you will list.
     3. Set repository permissions **Contents: Read and write** and **Pull
        requests: Read and write** (Metadata: Read is added automatically).
     4. Set expiry within the org's policy.
     5. If the org requires approval, the token stays *pending*, reading
        public data only, until an org owner approves it.
   - **Codilas (GitLab, gitlab.codilas.com):** check the version under
     **Help → Help**. Use a **fine-grained token** if the instance supports
     them: beta from GitLab 18.10, GA in 19.2. A supporting instance offers
     **Fine-grained token** in the **Generate token** menu under Edit profile
     → Access → Personal access tokens.
     1. Under **Group and project access**, add only the listed projects.
     2. Give each one these permissions:
        - **Code: Download**
        - **Code: Push**
        - **Project: Read** (`glab mr create` reads the project first)
        - **Merge Request: Create, Read, Update**: never Merge or Approve.
        - **Work Item: Create, Read**: top-level MR notes
          (`POST …/merge_requests/:iid/notes`).
        - **Pipeline: Read**
        - **Job: Read**
     3. Add **User: Read**, for the `codilas-glab api user` login check.
     4. If `codilas-glab` gets a 403 on a read it needs, add that permission.

     As of 2026-11-24, gitlab.codilas.com offers only classic PATs. Use one with
     scopes `api`, `read_repository` and `write_repository`. Expiry is at most
     365 days unless the admin changed it.
2. **List the repos.** In `_work-projects.nix`, add
   `repos.<key> = { path = "<owner>/<name>"; };` or the GitLab
   `group/sub/project` path. Also add the company's Jira project keys to
   `jiraProjects`, then set `enabled = true`.
3. **Generate the vars** without Clan's automatic commits, then make one
   commit:

   ```sh
   CLAN_NO_COMMIT=1 clan vars generate stygies --generator hermes-work-devzero-github-token
   CLAN_NO_COMMIT=1 clan vars generate stygies --generator hermes-work-devzero-git-identity
   # Codilas: hermes-work-codilas-gitlab-token, hermes-work-codilas-git-identity
   git add machines/ryza/_work-projects.nix vars/per-machine/stygies/hermes-work-devzero-github-token \
     vars/per-machine/stygies/hermes-work-devzero-git-identity
   git commit -m "feat(hermes): enable devzero work coder"
   ```

   Add anything else `git status` shows under `vars/` or `sops/` for these
   generators. Clan normally commits each generator's files on its own, which
   would leave the vars committed without the registry change that enables
   them. The generators exist only once step 2 sets `enabled = true`.

   Paste only the token at its hidden prompt. The identity generator asks for
   the name and email your commits for that company should carry. Both values
   must be one line. The email must have exactly one `@`. Neither may contain
   `[`, `]`, `\` or `"`.
4. **Deploy stygies first** (commands, guard, credentials), **then ryza**
   (the SOUL that names them).
5. **Check** as `hermes` on stygies (`sudo -iu hermes`):
   - Egress works: `curl -sSI https://github.com` and
     `curl -sSI https://gitlab.codilas.com`. The hermes uid may reach public
     IPv4 (`machines/stygies/network.nix`). If the GitLab host resolved to a
     private address it would be dropped.
   - `devzero-gh api user --jq .login` / `codilas-glab api user` shows your
     account. glab's `auth status` can't pass: the wrapper uses no stored
     login.
   - The credential helper works for listed repos: `git ls-remote
     https://github.com/<owner>/<name>.git` lists refs. For a non-listed repo,
     check only the exit status, so no token is printed:
     `printf 'url=https://github.com/<other>/<repo>.git\n\n' | git credential fill >/dev/null 2>&1; echo $?`
     prints a non-zero status, without prompting.
   - In a clone of a listed repo:
     - `git config --show-origin user.email` comes from the identity file.
     - `git push --dry-run origin HEAD:refs/heads/main` is refused by the
       Hermes push guard. `--dry-run` still runs pre-push.
   - `devzero-task-status --` is idle, and `~/work/.current-task` is unchanged.
   - Trial run: in the company room, ask for a small Jira ticket, naming the
     repo key. You should
     see a claim, a plan, then a wait for your `go`. After that it records the
     branch, pushes, and posts the PR/MR link. Repeat once from the app.

Company CI runs on the company's own runners when the PR/MR opens. Nothing
runs on ours; Hermes only reads its status.

#### Adding a repo later

Add it to the company's `repos` in `_work-projects.nix`. For GitHub, also add
it to the fine-grained PAT's selected repositories; for a GitLab fine-grained
token, add the project to the token. Then deploy stygies, then ryza. The key
is the name used in task claims, and must be unique within the company.

#### Token renewal

| Token | Lifetime | Renew |
| --- | --- | --- |
| DevZero GitHub fine-grained PAT | org policy; prefill allows up to 366 days | regenerate on GitHub with the same repos and permissions |
| Codilas GitLab token | ≤365 days by default | create a new one with the same permissions |

Run `clan vars generate stygies --generator <name> --regenerate`, then deploy
stygies. Clan commits the regenerated var by default; that is fine for a
renewal, since nothing else changes with it. The helper and wrappers read the file for each call, so no
restart is needed. An expired token shows up as a Git `Authentication failed`
or a 401 from the wrapper. The identity var changes only if your name or email
does.

## Cluster applications

The applications on taghmata are under `modules/taghmata/nixidy/apps`. Each is
a flake-parts module that declares itself, so adding a file adds an
application:

```nix
{self, ...}: {
  nixidy.envs.prod.apps.example = {charts, config, ...}: {
    applications.example = { ... };       # an ordinary nixidy module
  };

  # Only if the application needs them: a chart nixhelm does not have, and
  # typed options for the chart's custom resources.
  perSystem = {pkgs, ...}: {
    nixidy.charts."vendor/example" = ./chart;
    nixidy.crds.definitions.example.chart = ./chart;
  };
}
```

`default.nix` is the entry of an application's directory; files it imports
are prefixed with `_` so they are not loaded as flake-parts modules.
`nixidy.envs.prod.disabledApps = ["example"]` leaves one out. The flake-parts
support itself is `nixidy/flake-module.nix`, and what is specific to this
cluster is `nixidy/taghmata.nix`.

They are grouped like the noosphere domains, with three groups that exist
only in the cluster: `enginarium` (what the cluster runs on), `datavault`
(storage) and `augur` (observability), plus `cogitator` (everyday tools) and
`fabricata` (products built from rust-app-template).
Besides nixidy's own options, an application can use:

| Option | For |
|---|---|
| `sopsSecrets = ["name"]` | Shipping a cluster secret generated in `taghmata/reliquary` |
| `ingresses.<name>` | A single-host Traefik ingress with a certificate and Glance dashboard entry. `ingressAnnotations` builds the same annotations for charts that render their own Ingress |
| `garage.keys.<name>` (beside `applications`, not inside it) | An S3 key and its buckets on `garage-main` or `garage-backup`, with the credentials reflected into the application's namespace |
| `templates.cnpg-database-cluster`, `templates.garageObjectStore`, `templates.rust-service` | A PostgreSQL cluster, its backup object store, a rust-app-template service |

`nix run .#render-prod` renders the manifests into
`modules/noosphere/taghmata/nixidy/manifests/prod`; what ArgoCD applies is that
committed copy. `nix build .#nixidyChecks.x86_64-linux.prod` fails, listing the
files, when that copy is not what the sources render: after a flake update
that moved a chart, or a change nobody rendered. `nix run .#gen-crd`
regenerates the CRD option modules.

After each scheduled input update, the Machines workflow re-renders and opens
a pull request titled "render manifests", one commit per application
(`rituals/render-manifests-pr.sh`). Merging it is the deploy. The script also
runs by hand; `--no-push` only makes the commits.

## OpenTofu

`modules/taghmata/_tofunix` describes what exists outside NixOS and the
cluster: repositories and mirrors on both forges, Harbor projects and robots,
Pocket ID groups and OIDC clients. `nix run .#tofunix -- plan` runs it against
the state in the `opentofu` Garage bucket.

| Path | Holds |
|---|---|
| `conduits.nix` | Every provider and the credential it logs in with |
| `patterns/` | Options that stamp out resources repeated per item (below) |
| `scriptorium/` | Code hosting: `forge-noosphere.nix`, `forge-cerberus.nix`, `harbor.nix` |
| `pharos/` | Identity: Pocket ID groups and users, and `clients.nix` |
| `fabricata.nix` | Per-product wiring, generated from `../_products.nix` |

| Option | Declares |
|---|---|
| `reliquary.<name>.generator` | A clan var decrypted by the sops provider; `relic "<name>" "<key>"` is one of its values |
| `scriptorium.repos.<name>` | A Forgejo repository, with `mirrors.<where>` for push mirrors |
| `scriptorium.robots.<name>` | A Harbor robot that pushes and pulls |
| `pharos.clients.<name>` | A Pocket ID client, and with `secret.namespace` the Kubernetes Secret carrying its credentials |

Anything else is written as a plain `resource.<type>.<name>`. The state knows
resources by type and name, not by file, so declarations can move freely.
`nix build .#tofunix.tfjson` builds the generated configuration: the same store
path before and after a refactor means the plan cannot have changed.

### Installing Stygies

Follow [Hermes on Cerberus Forgejo](#hermes-on-cerberus-forgejo) for the rollout
order. Use the install command below only after the first OpenTofu apply has
created VM 121 on pve2 and the Stygies vars are generated.

Before installing, run `clan vars generate ryza --generator hermes-stygies-ssh`
and include the generated vars in the flake. Ryza gets the private key;
Stygies reads only the public file and denies Hermes SSH until it is present.

Boot the attached NixOS ISO and make root reachable over SSH at the reserved
IP. Run `clan machines install stygies --phases disko,install,reboot` from the
operator machine. This skips kexec, which hung on Ryza. Keep the hardware
report collected by the installer. The operator can use the VM console or
enter the `apetrovic` account from the existing Clan admin login.

Cerberus Caddy accepts Stygies requests only for the two Forgejo instances,
NCPS, and Harbor. Stygies pins the three noosphere names to Cerberus, whose
`*.noosphere.uk` vhost proxies to Traefik. Stygies's Hermes and Nix builder
egress policy still blocks direct access to the Traefik VIP.

### Forgejo Actions runners

Cerberus, Terra, Luna and Sol run `forgejo-runner-noosphere.service` and
`forgejo-runner-ugalabugala.service` on the host. On Ryza, the corresponding
units run in separate `ryza-ci-noosphere` and `ryza-ci-ugalabugala` guests.
Each unit has one forge token and capacity for one job. On hosts, the
two runners and their shared `nix-daemon` run under the existing machine
cap, with one Nix build slot per runner. The Ryza guests each have 3 vCPUs,
7 GiB RAM and one Nix build slot. Only Ryza separates jobs by kernel. The
sccache key, CI signing key and ncps upload credentials are still shared.

The split does not change the machine name, UUID or secret registered with
either forge. No re-registration or manual state migration is needed. Let
active jobs finish before changing generations. Each new unit creates
`/var/lib/forgejo-runner/<forge>` and its job `tmp` directory. Workspaces,
local action caches and per-forge Cargo homes start cold. The existing host
Nix stores and ncps cache stay in use. The first Cargo builds after the
split are cold in sccache, and the two forges no longer share sccache
entries because their Cargo paths differ. Do not copy a legacy `.runner`
file into the new state.

The old host state at `/var/lib/private/forgejo-runner/<machine>` and the
old Cargo home at `/var/lib/private/forgejo-runner-cargo` are unused. On
Ryza, `/var/lib/microvms/ryza-ci` holds the stopped legacy guest's two disk
images; the new guests have separate sparse 50 GiB overlay and 20 GiB
`/var` images. Check allocated space and free space on Ryza before rollout:
the old images and new caches compete with the host store. Retain old
state for rollback, or archive/remove it after verifying the cutover and
deciding it is no longer needed. Do not start the old guest alongside the
replacement pair.

Inspect either Ryza guest's console with
`journalctl -u microvm@ryza-ci-<forge>.service` on Ryza.

### Hermes on Cerberus Forgejo

Hermes pushes topic branches only to `hermes/rust-app-template` and
`hermes/pilot`, then opens PRs against the corresponding `manjo` repository.
Hermes has read access upstream; only `manjo` can merge PRs into `master`.
Direct pushes to `master` are allowed for `manjo` on `pilot` only;
`rust-app-template` takes changes through PRs alone. OpenTofu manages the bot account, forks, grants,
branch rules, and SSH key. Create both API tokens by hand.

Forgejo requires approval for `pull_request` runs opened or updated by the
untrusted bot and withholds Forgejo Actions secrets. `pull_request_target`
runs base-branch workflows and can receive those secrets. **Keep the account
restricted.** While it is restricted, **Always trust** has no effect.

Approving a run executes the PR's code as that forge's runner, with its
token and the shared sccache read-write key. Use the same review bar as
for merging, including build scripts, tests, Nix code, and workflows.
After any doubtful approval, revoke and rotate the affected registration;
assess both forges if the host or the old shared runner was exposed. Rotate
the sccache key if it may have been exposed.

Never use **Update branch** or push to a Hermes PR branch. A trusted
maintainer's push can run the PR head without approval; ask Hermes to
rebase instead. Immediately before approving, reload the PR and confirm
that the head SHA matches what you reviewed and that there is only one
pending run: Forgejo approves all pending runs for the PR at once. Before
merging, verify in Actions that the run for that head passed the required jobs.

**Before handing Hermes its credentials:** let active CI jobs finish, then
run `nix run .#forgejo-runner-register -- --all --forge ugalabugala` from the repo root.
This re-registers the existing Cerberus runners under `manjo`, preserving
their labels. In Cerberus Forgejo's **Site Administration → Actions →
Runners**, verify that no runner is instance-wide. An instance-wide runner
could pick up jobs from a Hermes-owned fork without upstream PR approval.

1. Run `clan vars generate terra --generator tofunix-hermes-forgejo-password`
   and commit the SOPS-encrypted var. Only the operator needs this password;
   do not put it on Stygies. OpenTofu stores it in state despite redacting
   it from plan output. Keep the var tracked after applying: removing it
   schedules the account and its grants for deletion. Regenerating it
   does not rotate the Forgejo password.
2. Create the bot with OpenTofu.
   stygies uses the static `192.168.1.248` (`_chart.nix`); the router can't
   reserve it, so check it's still free before installing. Initialize
   OpenTofu with `nix run .#tofunix -- init` using the state
   credentials from `.envrc`. The Cerberus provider token must belong to a
   site admin and include `write:repository` for grants and branch rules,
   `write:admin` for the user and SSH key, and `read:user` (or `write:user`)
   to refresh them. Adopt the existing template rule once, before applying:

   ```sh
   nix run .#tofunix -- import \
     gitea_repository_branch_protection.rust-app-template manjo/rust-app-template/master
   nix run .#tofunix -- plan
   ```

   If `hermes` already exists, import it with `nix run .#tofunix -- import
   gitea_user.hermes <numeric-user-id>` before planning. Import keeps the
   existing Forgejo password; the generated password is for a new account.
   Review and apply the plan to create VM 121 on pve2, the restricted bot
   account, the branch rules, and the upstream read grants.
3. Sign in as `hermes` and choose **Disable email notifications** in
   **Settings → Account**. For a new account, decrypt the password only
   when signing in:

   ```sh
   sops decrypt --input-type yaml --extract '["password"]' \
     vars/shared/tofunix-hermes-forgejo-password/tofunix-hermes-forgejo-password/value
   ```

   Under **Settings → Applications → Generate New Token**, create a
   separate operator token for **All (public, private, and limited)**
   repositories with `write:repository` for the forks, `read:user` for
   the provider's login check, and `read:organization` for its owner lookup.
   Paste it at the hidden prompt for
   `clan vars generate terra --generator tofunix-hermes-forgejo-forks`.
   Commit the SOPS-encrypted var, then review and apply a new OpenTofu
   plan to create both forks. Do not put this token on Stygies.
4. As `hermes`, open **Settings → Applications → Generate New Token** and
   choose **All (public, private, and limited)**. The account is
   restricted, so Forgejo lets it reach only its own forks and the repos it
   was added to as a read collaborator, not even other public repos; the
   account is the boundary, and the token keeps working when a repo is
   added to `repos` in `forge-cerberus.nix`. (Forgejo tokens can't be
   edited, so a Specific-repositories token would have to be replaced for
   every new repo.) Give **repository** and
   **issue** Read and Write access (`write:repository`, `write:issue`) and
   leave all other scopes off. Forgejo's PR POST requires `write:repository`
   on a token that covers both the base and head repos; ordinary PR and
   issue comments use `write:issue`. These token scopes don't elevate the
   bot's upstream repository permission beyond read.
5. Stygies already imports `self.nixosModules.hermes-forgejo-bot`. Run
   `clan vars generate stygies`, supply the token at the hidden prompt,
   and set a separate password for `apetrovic`. Commit the generated vars,
   including the public SSH host key that Clan needs to evaluate Stygies.
   If this merges before those vars are committed, the scheduled
   `machines.yml` Stygies job will fail until they are available; other
   matrix jobs still run.
6. [Install Stygies](#installing-stygies).
7. Run `nix run .#tofunix -- plan` again, then review and apply it to enroll
   the bot's SSH key. OpenTofu reads only `id_ed25519.pub`, not the private
   key. Keep the public var tracked; removing it schedules the managed key
   for deletion.

On Stygies, `modules/rites/hermes-forgejo-bot.nix` sets up the `hermes` user:

- **Git identity:** `Hermes <hermes@forge.ugalabugala.org>`, from a read-only
  `~/.config/git/config`, which also rewrites `https://forge.ugalabugala.org/`
  URLs to SSH. Once the noosphere bot is enabled, the same file sets
  `credential.interactive = false` (HTTPS never prompts) and an `includeIf`
  on `hasconfig:remote.*.url` switches the commit email to
  `hermes@forge.noosphere.uk` in repos whose remote is on that forge.
- **SSH to the forge:** port 2222 with the Clan-deployed
  `hermes-forgejo-ssh/id_ed25519`. Forgejo's RSA host key is pinned.
- **`fj`, the Forgejo CLI:** logged in as the bot by `hermes-fj-login.service`
  from the separate `hermes-forgejo-token/token` (Cerberus) and, once the
  noosphere bot is enabled, `hermes-forgejo-noosphere-token/token` files. After rotating only a token, run
  `systemctl restart hermes-fj-login`.

The runtime tokens and SSH key are readable only by `hermes` and root.

On Cerberus, set `origin` to `ssh://forgejo@forge.ugalabugala.org:2222/hermes/<repo>.git`
and `upstream` to `ssh://forgejo@forge.ugalabugala.org:2222/manjo/<repo>.git`.
Fetch from `upstream` and push topic branches only to `origin`. Then open the
PR against upstream from the fork: in fj, a base starting with `^` means the
parent repo's branch, for example
`fj -H forge.ugalabugala.org pr create -r hermes/<repo> --base ^master --head <topic-branch> "<title>" --body-file <file>`
(forgejo-cli 0.7.0 src/prs.rs).

Stygies keeps about 10 GiB of audit logs under `/var/log/audit`. The target is
roughly 90 days, but actual retention depends on build activity. Auditd warns
at 10% free space and rotates logs below 5% or on a full disk rather than
suspending auditing. Disk pressure can shorten the retained history.
When stdin isn't a terminal, use `ausearch -i -k hermes-exec </dev/null` (or `--input /var/log/audit/audit.log`).

Local Nix builds on Stygies, including `apetrovic`'s, share the Hermes egress
policy. The root Nix daemon is not filtered by this policy.
Cerberus's Caddy guard matches the Stygies source IP, so other Cerberus
services also return HTTP 403 to `apetrovic` when accessed from Stygies.

### Hermes on noosphere Forgejo

The noosphere bot is gated by `forges.noosphere.botEnabled` in
`machines/ryza/_coder-projects.nix` (now `true`). While it is off no deploy declares or
prompts for `hermes-forgejo-noosphere-token`, Stygies gets no noosphere Git
credentials or `fj` login, and a project with `forge = "noosphere"` fails
evaluation. Follow the steps below in order; set the flag to `true` in the same
commit as the generated PAT var (step 2).

**Scope the runners before handing Hermes credentials.** First check
**Site Administration → Actions → Runs** on noosphere for workflow runs of any
owner other than `manjo` (for example the `monolith-softworks` org). Owner-scoped
`manjo` runners take no jobs from other owners, so those would queue forever
after scoping; scope them separately or accept the loss before continuing.
Drain noosphere CI. In noosphere **Site Administration → Actions → Runners**, compare the UUID
for each machine with its existing `forgejo-runner-noosphere/uuid` Clan var.
Stop and reconcile any missing/mismatched running identity before continuing.
From the updated checkout, run:

```sh
nix run .#forgejo-runner-register -- --all --forge noosphere
```

Forgejo 15.0.12 re-scopes same-UUID runners in place. No runner secret
rotation, restart, or redeploy is needed, and the command does not contact
ugalabugala. Check for exactly one row per machine (Cerberus, Terra, Luna,
Sol, Ryza), with the same UUID and labels and owner `manjo`. If an identified
legacy row remains, stop its old daemon if still running, then delete only
that row via its trash action in the noosphere runner list. Do not proceed
with any instance-wide row, even offline. Check a normal `manjo` Actions
run still schedules. Do not revert to global while a Hermes fork exists.

1. Run `clan vars generate terra --generator tofunix-hermes-noosphere-password`
   and commit the SOPS-encrypted var. Review the OpenTofu plan and apply the
   restricted non-admin `hermes` account on noosphere. If the intended account
   already exists, import it as `gitea_user.hermes_noosphere` instead. Keep
   the var tracked after applying; removing it schedules the managed account
   for deletion. The operator password is also stored in OpenTofu state.
2. As noosphere `hermes`, generate a PAT under **Settings → Applications**:
   **All (public, private, and limited)** with repository and issue **Read
   and Write** only. Run
   `clan vars generate stygies --generator hermes-forgejo-noosphere-token`,
   paste it at the hidden prompt, and in the same commit set
   `forges.noosphere.botEnabled = true` in `machines/ryza/_coder-projects.nix`
   and commit the encrypted var. Do not deploy the operator password or reuse
   the Cerberus PAT. To rotate, use
   the same generator with `--regenerate`, deploy it, restart
   `hermes-fj-login.service`, and revoke the old PAT after checking the new one.
3. Deploy Cerberus first (Caddy guard), then Stygies (host pin and credentials),
   then Ryza (coder prompt). As `hermes` on Stygies, check that
   `getent ahostsv4 forge.noosphere.uk` returns Cerberus, that
   `curl -fsS https://forge.noosphere.uk/api/v1/version` succeeds with TLS
   verification, and that the same request forced to the Traefik VIP with
   `--resolve forge.noosphere.uk:443:192.168.1.251 --connect-timeout 5` cannot
   connect. An unrelated vhost via Cerberus must still return 403. Check
   `fj auth list` for both hosts, plus an existing Cerberus Git and `fj` read.
   Verify an existing project on Ryza is still routed in Matrix and available
   in the app.

No noosphere project is enrolled by default. To add one, review branch
protection and Actions on `<owner>/<repo>`, add the repo to `hermesRepos` in
`modules/taghmata/_tofunix/scriptorium/forge-noosphere.nix`, and apply the
read-only grant. Sign in as `hermes` to create the actual fork; leave fork
Actions off and never attach a privileged runner to it. Invite the Matrix
bot and add the `{ forge = "noosphere"; room = "!…"; }` project record, with
`owner = "<org>"` for an organisation repo (its tofunix entry sets `org`, and
the read grant follows it).
Deploy Stygies and then Ryza. The remotes are
`https://forge.noosphere.uk/hermes/<repo>.git` (`origin`) and
`https://forge.noosphere.uk/<owner>/<repo>.git` (`upstream`); Git reads the PAT
from the deployed secret file for this HTTPS host only. As `hermes`, check
noninteractive `git ls-remote` on both, a fork-only dry-run push, and a repo
read with `fj -H forge.noosphere.uk`. The first task should open its PR from
the fork against the actual upstream default branch and confirm that
untrusted PR CI waits for `manjo` approval. Use the same approval rules as
on Cerberus.

## Addresses and secrets paths

No module writes an IP address or a `../../vars/...` path itself. Both come
from `modules/cartographa`:

| Where | Addresses | Vars files |
|---|---|---|
| NixOS and Home Manager modules | `self.lib.hosts.cerberus`, `self.lib.lan.gateway`, `self.lib.vips.traefik` | `self.lib.vars.shared "<generator>" "<file>"` |
| nixidy apps | the `cartographa` module argument | the `vars` module argument |
| OpenTofu config | the `noosphere` module argument | the `reliquary` option, over the `vars` module argument |
| clan inventory | `import .../cartographa/_cartographa.nix` | the same import's `vars` |

A new host or device gets one line in `modules/cartographa/_chart.nix`.
