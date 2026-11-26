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
tools run over SSH as `hermes` in `~/personal` on stygies (layout and its
one-time migration: [Hermes workspaces on stygies](#hermes-workspaces-on-stygies)).

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
   Two projects can't share a room, and `room = ""` is an evaluation error.
4. For an app-only project (reachable from Hermes Mobile and the desktop app,
   never from Matrix), skip the room: add the entry with `forge` (and `owner`)
   but no `room`, or `room = null`. It gets no Matrix route, the coder prompt
   lists its room as "app only", and stygies's task tools refuse a Matrix
   claim for it (`HERMES_TASK_APP_ONLY_PROJECTS`); Hermes asks you to use the
   app instead. To move it to Matrix later, create the room and add `room`.

In Hermes Mobile, pick `coder`, open one chat per task, and name the exact repo
from the coder project map. Each app chat or Matrix thread is its own task with
its own git worktree, so tasks run in parallel, several on one repo too
([Hermes task worktrees](#hermes-task-worktrees)); each needs explicit plan
approval. At the cap (`services.imperium.hermesGit.maxLiveTasks`, default 3) a
new claim is refused as `busy`, not queued: finish or clear a task first. To
release a task, say `clear task` (or `drop task`) in its chat or thread; from
anywhere else, say `clear task <task_id>` with the ID from `task-status --all`.
That is also the way out when an app task ID is lost.

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
gateway start. Don't reset a chat with a live task to pick up the prompt.

**App projects** need stygies paths: create them in the app with an absolute
`/home/hermes/personal/<repo>` path. Hermes resolves `~` and relative paths on ryza
(`~/personal/x` becomes `/var/lib/hermes/personal/x`), which doesn't exist on stygies.
A patched Hermes (`services.imperium.hermes.sshHostOnlyPaths`, default
`/var/lib/hermes`) runs such a project's commands in the profile's
`terminal.cwd` (`~/personal`) instead of failing every one, and logs
`ssh working directory … exists only on the Hermes host` in `agent.log`. Fix the
project's path rather than relying on that. The project path stays the base
clone; the SOUL runs a task's commands in that task's worktree
(`/home/hermes/personal/.worktrees/<repo>/<task_id>`, which the guard leaves
alone, as it does every path outside `sshHostOnlyPaths`).

Before rolling stygies back past the task worktrees change, see
[Hermes task worktrees](#hermes-task-worktrees), "Rollback".

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

### Hermes task worktrees

The personal coder runs every task (one Matrix thread or one app chat) in its
own git worktree, on its own branch, with no slot or queue
(`modules/rites/_hermes-task.py` in worktree mode, launched by
`modules/rites/hermes-forgejo-bot.nix`). The work coder still uses its
per-company slots for now.

| Path on stygies | What |
| --- | --- |
| `~/personal/<repo>` | Base clone: `origin` (the `hermes/<repo>` fork) and `upstream`. App projects point here; tasks never work in it. |
| `~/personal/.worktrees/<repo>/<task_id>` | A task's worktree, created by `task-branch`, removed by `task-done` |
| `~/personal/.worktrees/.trash` | Removed worktrees on their way out, deleted after each command (outside the lock) |
| `~/personal/.worktrees/.kept` | Trees the tools would not delete, kept for you (listed by `task-status --all`) |
| `~/personal/.task-state.json` | Live tasks (JSON, replaced atomically), with `.task-lock` |

Worktrees sit beside the base clones, not inside them, so a `git clean`, a
search or a `path:` flake copy in a base clone never reaches a task.

Commands (`--follow-up` and other flags go before the origin):

- `task-claim`: `claimed`, `active` (this conversation already has a task), or
  `busy` (live tasks are at `maxLiveTasks`; nothing is written).
- `task-status <origin>`: the conversation's own task (`owned`, `worktree`,
  `idle_seconds`, `possibly_stale` after 12 idle hours). `task-status --all`
  lists every live task by `task_id`, project, branch, idle time and summary,
  plus `orphans` (worktree directories without a task), `kept` and `wip_refs`.
  It never shows Matrix or app IDs.
- `task-branch <origin> <started_at> <branch>` creates the worktree: a new
  branch from `upstream/HEAD` without upstream tracking, or with `--follow-up`
  the existing PR branch from `origin`, fast-forward only. Branches are
  `hermes/<slug>`, and two live tasks never share one. The lock is released
  while Git checks out, so big checkouts don't stall other tasks. A checkout
  that dies is recovered by the next `task-branch` for that task after 10
  minutes (the branch it left is deleted); one killed outright (SIGKILL, OOM)
  leaves Git's `initializing` lock, recovered after an hour. A failing
  post-checkout hook (e.g. git-lfs not installed) is reported as a warning.
- `task-done` removes the worktree and deletes the local branch if `origin` has
  exactly it, checked with `git ls-remote` (a stale remote-tracking ref or an
  unreachable remote keeps it). Commits only the worktree's HEAD reflog names
  (an amend, a detached commit left behind) are saved to
  `refs/hermes/wip/<task_id>` first. It refuses while anything would be lost:
  uncommitted changes, a detached HEAD, a rebase/merge/cherry-pick/revert/bisect
  in progress, commits no branch, remote or tag holds, or initialised
  submodules (their objects live in the worktree's admin dir; a submodule never
  checked out doesn't count).
- `task-clear <origin>`, `task-clear --id <task_id | repo/dir>` (only on your
  explicit `clear task`): saves uncommitted work, and commits only the
  worktree's HEAD holds, to `refs/hermes/wip/<task_id>` in the repo (never
  replacing an existing ref), then removes the worktree. `task-clear --repair`
  moves invalid state aside; the SOUL runs it on your `clear task` when a
  command reported invalid state.

The tools only ever delete a linked worktree of the task's own base clone.
Anything else at a worktree path (another clone, a plain directory), and any
worktree a snapshot can't hold (submodules, a nested repository, edits hidden
by skip-worktree or assume-unchanged, a tree Git can't read) is moved to
`.kept` instead; a kept linked worktree stays registered and locked, so look at
it and remove it with `git worktree unlock` + `git worktree remove`. Its
submodules still name their old place (`core.worktree`), so reach one with
`git --git-dir ~/personal/<repo>/.git/worktrees/<task_id>/modules/<sub> --work-tree <kept>/<sub> …`.
If Git can't lock a worktree, nothing is moved and the command refuses. Locked
worktrees are never touched. **Ignored files** (build output, `.env`, local
notes) are not kept: done and clear delete them with the worktree.

To look at saved work: `git -C ~/personal/<repo> show refs/hermes/wip/<task_id>`,
or check it out somewhere with `git worktree add`. Delete the ref when done
(`git update-ref -d`).

**Migration.** The first task command after the deploy turns the old slot into
live tasks: the active task keeps its branch and finishes in its base clone
(`legacy`), and queued tasks become pending tasks that start at their next
`continue`. The old files are renamed `.current-task.migrated-<time>` and
`.task-queue.migrated-<time>`.

Deploy stygies, then ryza, back to back, while no personal task is between its
claim and step 3 (setting up the workspace): an old-SOUL task in that window
creates its branch in the base clone, and the new `task-branch` then refuses it
("already exists locally"). Tasks past step 3 migrate cleanly (`legacy`).
Don't start a task between the two deploys.

**Rollback.** Older tools ignore `.task-state.json`. Before rolling stygies
back, run `task-status --all` as `hermes` and finish or clear what's live, then
remove `.task-state.json`. Don't rename the `.migrated-*` files back: they hold
every row from deploy time, including tasks finished since. If a task must go
on in the old slot, write a fresh `.current-task` with only its row (six
tab-separated fields: `started_at`, room, thread, project, branch, summary).
Leftover worktrees are plain git worktrees:
`git -C ~/personal/<repo> worktree remove <path>`.

### Hermes delegation tiers

`coder` hands sub-tasks to subagents (`delegate_task`) on a model picked by
**tier**. The coder SOUL's "Delegation" section says when to use which.
`work` has the same tiers on the DevZero token only, switched off for now
(`workTiersEnabled` in `machines/ryza/hermes.nix`).

| Tier | Model (effort) | Fallback, in order |
| --- | --- | --- |
| `plan` | claude-opus-5-5 (high) | gpt-6.2-sol |
| `critical` | claude-fable-5-2 (high) | claude-opus-5-5 |
| `implement` (default) | claude-sonnet-5-5 (medium) | gpt-6.2-sol, gpt-6.1-terra |
| `review` | claude-opus-5-5 (high) | gpt-6.2-sol |
| `quick` | claude-haiku-5-5 (low) | gpt-6-luna, deepseek-flash |
| `bulk` | deepseek-v4-pro (high) | qwen3.8-max (Token Plan) |

- **Accounts:**
  - Claude models use the hermes user's Claude Code login (Max).
  - GPT models use the ChatGPT Plus device login.
  - DeepSeek and Qwen use the `pi-api-keys` keys.
- **Fallback effort:** a fallback runs at its tier's effort, because Hermes fallback entries are only a provider and a model.
- **Data leaving the subscriptions:** `bulk` sends repo content and logs to DeepSeek (falling back to Alibaba's Token Plan), and so does `quick` when it reaches its last fallback (DeepSeek). Every other tier stays on Anthropic or OpenAI.

How it works:
- A small delegation backend of ours, `tiers` (`modules/rites/_hermes-delegation-tiers`), is bundled into the Hermes package. Its smoke test runs at build time, so a Hermes bump that breaks it fails the build.
- `services.imperium.hermes.profiles.<name>.delegation` renders the profile's `delegation` settings on every activation, tiers on or off. It pins:
  - `max_concurrent_children = 2`. This is not a cap on subagents overall: it limits the children of one `delegate_task` call, and separately the background calls running at once. The background pool is shared by every profile in the gateway, and a call that finds it full runs inline instead of being refused, so one profile can still have several calls' worth of children at once. The SOUL's "at most two" is the rule the agent follows.
  - no nested delegation, no auto-approval, no inherited fallback
  - the core route keys (`delegation.provider`, `model`, `base_url`, `api_key`, `profile`, ...) empty, meaning "the parent's". Hermes' default backend routes every child by these, and the `hermes model` menu can write them; activation resets them. `settings.delegation` may not set them (assertion).
- Only tier names and descriptions reach the model.
- Coder's `auxiliary.review` is pinned to Opus 5.5, so core `/review` doesn't run on the `implement` tier.

**Guard rails.** Each provider a tier or fallback names must be in the profile's `allowedProviders`. This is checked by a Nix assertion and again by the backend on every task. At runtime the allowlist is the intersection of config.yaml's and a read-only copy in the Nix store (`HERMES_DELEGATION_TIERS_ALLOWLIST`, set for the gateway and the `hermes` wrapper), so a hand edit of config.yaml can narrow it, never widen it. The backend also refuses:
- provider aliases, and meta ids such as `auto` and `custom` (they pick whatever login or endpoint is present)
- endpoints and keys
- profile routes
- fast tiers
- unknown tiers: they fail with a message instead of running elsewhere

`work` must keep `allowedProviders = []`, tiers without a provider, and no `settings.delegation`; an assertion enforces all three. A profile with an empty allowlist always runs the `tiers` backend, even with no tiers, so every subagent keeps the parent's exact credentials, the DevZero token, whatever `delegation.*` says. This matters because a profile with no ChatGPT grant of its own borrows the default profile's, whatever `auth.adopt_external_logins` says.

Never install NousResearch's `advanced-delegation` plugin here: its `/delegation` command and `hermes delegation config` editor write `delegation.backend` and the same keys Nix owns.

Subagents never see SOUL.md, and they get the parent's full tools, including the stygies terminal, Kaneo and the shared working copy. That is why the coder SOUL tells the parent to put the rules into each task's context, keeps every tier but `implement` read-only, runs one `implement` at a time, and leaves every commit, push, PR, task-slot and Kaneo action to the parent.

After deploying ryza:
1. **ChatGPT login (already done).** Codex refresh tokens rotate on every use, so the login can't be a clan var. It lives in the persisted `/var/lib/hermes/.hermes/auth.json`, and `coder` reads it from there. Check it:
   ```sh
   sudo -iu hermes hermes -p coder auth list openai-codex
   ```
   This should show one device-code OAuth credential. If it ever shows none, sign in again with `sudo -iu hermes hermes auth`, pick OpenAI Codex, and finish the device code in a browser.
2. **Rendered settings.** Check `delegation.backend: tiers` and the five options:
   ```sh
   sudo -u hermes sed -n '/^delegation:/,/^[a-z]/p' /var/lib/hermes/.hermes/profiles/coder/config.yaml
   ```
3. **New sessions.** Send `/new` in each coder room and app chat. A session keeps the `delegate_task` it started with, so older sessions run with no tiers.
4. **Smoke test.** In a coder thread, ask: "Delegate one `quick` task: run `uname -n` and report it." The result's route should read `quick · claude-haiku-5-5`, and its `model` names the model that actually ran.
5. **Qwen Token Plan region.** Check which endpoint the key works on. This lists models only, so it starts no paid call. The key is never printed: curl reads the header from stdin, so it is never in a process's arguments either.
   ```sh
   sudo -iu hermes bash -c 'key="$(tr -d "\n" < /run/secrets/vars/shared/pi-api-keys/qwen-api-key)"
   for host in token-plan.ap-southeast-1 token-plan.cn-beijing; do
     printf "%s: " "$host"
     printf "Authorization: Bearer %s\n" "$key" |
       curl -s -o /dev/null -w "%{http_code}\n" -H @- "https://$host.maas.aliyuncs.com/compatible-mode/v1/models"
   done'
   ```
   - `200` on `cn-beijing` only: set `qwenTokenPlanProvider = "alibaba-token-plan-cn"` in `machines/ryza/hermes.nix`.
   - `401` on both: the plan's API may not serve `/models`, so check the key's region in the Model Studio console instead.
6. **Watch usage for a week:** the Claude weekly limits (Fable has its own), the ChatGPT Plus 5-hour and weekly windows, and DeepSeek spend.

**To enable `work` tiers:**
1. Set `workTiersEnabled = true`, deploy, and send `/new` in the work rooms.
2. Repeat the billing comparison from [Hermes work profile](#hermes-work-profile-ryza--stygies) step 4 with a delegated `quick` task. Only DevZero usage should move.

### Hermes workspaces on stygies

Both profiles run as `hermes` on stygies (home `/home/hermes`), in separate
trees. Each SOUL forbids the other's tree.

| Profile | Terminal cwd | Repos | Task slot |
| --- | --- | --- | --- |
| `coder` | `~/personal` | `~/personal/<repo>`, task worktrees in `~/personal/.worktrees/<repo>/<task_id>` | `~/personal/.task-state.json`, `.task-lock` |
| `work` | `~/work` | `~/work/<company>/<repo key>` | `~/work/.tasks/<company>/` |

Before 2026-11-25 the coder used `~/work` and the work profile `~/work-devzero`.
Stygies's activation moves the old layout
(`modules/rites/_hermes-workspace-migrate.py`, run as `hermes`, before
tmpfiles): `~/work` → `~/personal`, then `~/work-devzero` → `~/work`. It acts
only on evidence of the old layout: `~/work-devzero`, which every old
generation created. Without it, or once the done-stamp
`~/.local/state/hermes-workspace-migrate.done` exists, it does nothing. The
stamp is written, with a log line, only once `~/work-devzero` is gone: after a
success, or on first sight of a home without it. Linked Git worktrees are repointed: their `.git` files inside
the moved trees, the repos' `worktrees/*/gitdir` back-pointers, and the `.git`
file of a worktree outside the trees that a back-pointer names. A worktree
outside the trees that no back-pointer names needs
`git -C <repo> worktree repair <worktree path>`. Remotes, the `includeIf` rules
(URL-based) and the slot files hold no paths. Python virtualenvs (absolute
shebangs and `activate`) must be recreated, and each `.envrc` needs
`direnv allow` again (direnv keys its allow list by path). Nix gcroots
(`result`, `.direnv`, `.devenv`) dangle until rebuilt, so GC may collect their
closures. None of this loses data. If the script is killed between the renames
and the Git rewrites (a window of milliseconds), the rerun has nothing to move,
so a linked worktree keeps a stale link. Fix that one with
`git -C <repo> worktree repair <worktree path>`.

It **refuses and changes nothing** when:

- a slot it would move has an active task, or a task command holds its lock;
- a `hermes` process has its working directory in `~/work` or `~/work-devzero`
  (it lists them);
- old and new trees both hold content (an empty-directory skeleton left by
  tmpfiles doesn't count), or `~/work` mixes personal repos with company
  directories;
- any of the three directories is a symlink, or a directory can't be read;
- there is no `~/work-devzero`, but `~/work` has the old personal slot files
  (`.task-lock`, `.task-queue`, `.current-task`). That is the old layout with its
  evidence missing. If `~/work` is the old personal tree, create an empty
  `~/work-devzero` as `hermes` and run `sudo hermes-workspace-migrate`.

A `hermes` process is checked for once more right before the renames, with
`~/personal` included.

A refusal never fails the deploy. It is printed in the deploy output and
logged: `journalctl -t hermes-workspace-migrate`. Until the move is done the
task commands refuse with `workspace migration pending`, so a stale slot can't
hide a task.

**Deploy window (one time).** `/pause` doesn't stop running work, so use the
hard stop:

1. On stygies, check both slots are idle, as `hermes`: `~hermes` is mode 700,
   so a check as another user sees nothing and looks idle. Use
   `sudo -iu hermes task-status --queue` and
   `sudo -iu hermes <company>-task-status --queue` (the old commands, before
   this change), or the loop under the manual fallback. Also check
   `sudo ls -A ~hermes/work-devzero` lists something. That is the evidence the
   migration needs; if it lists nothing, stop and look before deploying.
2. On ryza: `sudo systemctl stop hermes-gateway hermes-dashboard`.
3. On stygies: `pgrep -u hermes -a` shows nothing, or only `sshd` sessions.
   Kill leftovers as in the emergency stop above.
4. `clan machines update stygies` on its own. Check the output (or
   `journalctl -t hermes-workspace-migrate`) for `moved … -> …` and the
   done-stamp line, and check that `sudo ls -A ~hermes` shows `personal` and
   `work` but no `work-devzero`.
5. `clan machines update ryza`, as a separate run. Until ryza switches, its
   old coder cwd `~/work` is the company tree and its old work cwd
   `~/work-devzero` is gone. Never deploy ryza first: its new work cwd `~/work`
   would be the personal tree.
6. On ryza: `sudo systemctl start hermes-gateway hermes-dashboard`. The deploy
   may already have started them.

A task active during the switch makes the migration refuse, by design. Its
agent may be mid-command in the repo, and its absolute paths would break
underneath it. Either roll stygies back to the previous generation, finish or
clear the task there, and deploy again, or clear it by hand once manjo has
confirmed it can go.

**Manual fallback:** fix the cause the refusal names, then run the migration
again by hand on stygies, with the gateway stopped:

```sh
sudo hermes-workspace-migrate
```

`hermes-workspace-migrate` is the exact script and arguments activation uses,
run as `hermes`. It prints what it moved, or why it refuses again; exit 0 means
done or nothing to do. To check that the slots are idle, run this as `hermes`.
It prints nothing when they are (an idle slot has no `.current-task`). For the
old layout:

```sh
sudo -u hermes sh -c 'for f in /home/hermes/work/.current-task /home/hermes/work-devzero/.tasks/*/.current-task; do
  [ -s "$f" ] && echo "active: $f"; done; true'
```

For the new layout (before a rollback):

```sh
sudo -u hermes sh -c 'for f in /home/hermes/personal/.current-task /home/hermes/work/.tasks/*/.current-task; do
  [ -s "$f" ] && echo "active: $f"; done; true'
```

Don't move the trees with `mv` or prune them with `find … -delete`. `mv` into
an existing directory nests the tree, and pruning empty directories can delete
an empty `.git/refs` and break a repo.

**Rollback past this change is one-way.** The old generation recreates
`~/work-devzero` empty. Its personal launcher writes its slot into `~/work`
(the company tree), and its company launchers see idle slots. So before rolling
stygies back, with the gateway stopped and both slots idle (the new-layout
check above), reverse the move by hand on stygies as `hermes`:

```sh
set -eu
cd ~
# First: if a step below fails, the next roll-forward still migrates.
rm -f ~/.local/state/hermes-workspace-migrate.done
[ ! -e work-devzero ] || rmdir work-devzero   # fails, and stops, if not empty
mv -T work work-devzero
mv -T personal work
```

If it stops halfway, `sudo hermes-workspace-migrate` is safe in any partial
state. It moves the trees forward to the new layout again, or refuses on
anything ambiguous. Fix the cause, then start the rollback over.

Then run `git -C <repo> worktree repair <worktree paths>` for repos with linked
worktrees. Rolling forward again migrates afresh. A stray old-slot file the new
launchers report (`~/work/.task-lock`, or files under `~/work-devzero`) is named
in the message: check it holds no live task, then remove it.

**After ryza is deployed:**

- App projects and sessions that point at `/home/hermes/work/<repo>` (coder) or
  `/home/hermes/work-devzero/...` (work) fail their `cd` instead of reaching the
  other tree, because those paths no longer exist. On ryza as `hermes`, run
  `hermes -p coder projects list --all`, archive those, and recreate them with
  `/home/hermes/personal/<repo>`. Do the same for `work` with
  `/home/hermes/work/<company>/<repo key>`. The one path that would still `cd`
  is a coder project at `/home/hermes/work` itself, so check for it.
- Memories and the skills the agents wrote are part of their system prompts
  and may still name the old paths:
  `grep -rn 'work-devzero\|~/work\|/home/hermes/work' ~/.hermes/profiles/{coder,work}/{memories,skills}`.
  Edit the hits: coder's `~/work` becomes `~/personal`, and work's
  `~/work-devzero` becomes `~/work`.
- A cron job's workdir becomes its session cwd. Check `hermes -p coder cron list`
  for workdirs under `/home/hermes/work`. The cron tool is disabled for `work`.
- Matrix threads start in the new cwd after the gateway restart.

### Hermes work profile (ryza → stygies)

`work` uses Anthropic Claude Opus 5.5 with the DevZero account in both the
DevZero and Codilas rooms, and in Hermes Mobile. Its terminal runs on stygies
as `hermes` in `~/work`. It needs the same stygies host pin as `coder`
for that terminal, but does not use the personal task queue or the personal
Claude Code login; its coding tasks use per-company slots (see
[Hermes work coder](#hermes-work-coder-github--gitlab)). The profile and its room routes exist with or without the
pin; without it the terminal, file and code tools are disabled
(`agent.disabled_toolsets`, which always includes `cronjob`), because a room
without a route would be answered by `default` on the personal login.
Prompt refreshes after a SOUL change and app project paths work as for `coder`
(see [Hermes coder profile](#hermes-coder-profile-ryza--stygies)); work's
fallback directory is `~/work`, and app projects use
`/home/hermes/work/<company>/<repo key>`.

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
   - `pwd` in the work terminal returns `/home/hermes/work`.
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
  read `~/personal`, and coder can read `~/work`. The SOULs are the only guard
  (each forbids the other's directory); isolating them (a second user and
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
  `~/work/.tasks/<company>`, the company's room and repo keys as
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
   - `devzero-task-status --` is idle, and `~/personal/.current-task` is unchanged.
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

#### Ryza one-job pilot (`nix-eph`)

Ryza ships with one slot, `ryza-eph-1`, serving three pools on `nix-eph`:
`ugalabugala` (manjo/rust-app-template, repo ID 9), `noosphere-user`
(manjo/auspex and manjo/mushroom-farmer), and `noosphere-org`
(monolith-softworks, the full org queue). Each dispatcher boots its
assigned slot for one job handle. The guest gets that registration's
single-use token, UUID and job handle, plus the selected forge URL and
label. The job can read these files.
There is no dispatcher PAT, persistent runner secret, sccache key, ncps netrc
or signing key in the guest (the opt-in trust policy below adds the last
two, root-only, for exactly resolved trusted runs). The guest shares the
host Nix store read-only and can use ncps with public verification keys;
writable store and `/var` images are disposable.
Treat all host store contents as visible to the job; do not put plaintext
secrets in store paths.

The dispatcher only decides: Forgejo API calls, durable state, the trust
verdict. Every slot side effect goes through `slotctl`
(`modules/rites/_forgejo-slotctl.py`), either as a local child or through a
source-restricted SSH forced command. It handles systemd units, staged
runner credentials, disk images and the trust share on the slot host.
Each call names a slot and one verb (`observe`, `check-space`, `start`,
`stop`, `reset-failed`, `stop-support`, `stage`, `scrub`, `deliver`,
`withdraw`, `egress trusted`). The module compiles the per-host config, which holds the paths,
into slotctl. slotctl has no option to point elsewhere, and repeated or
abbreviated options are refused, so a caller can only pick a declared slot
and a verb. Secrets travel on stdin.
- `scrub` refuses unless the VM is stopped, and it also clears the trust
  share.
- `deliver` refuses unless the slot delivers and its VM is `active` with no
  job queued.
- A refusal is one fixed code (for example `vm-not-running`). The dispatcher
  logs its own message for it, the same text as before; slotctl's output is
  never logged.

With remote dispatch off, existing persistent runners and labels (including
`nix-vm`) are unchanged. They are **not** safe for arbitrary untrusted
workflows: they accept jobs that request their credential-bearing labels.
Review the entire workflow before approving a fork run; do not open up fork
scheduling more broadly.

**Enroll a local pilot pool (operator only, before remote cutover).**

1. Verify the upstream repo is public, owned by `manjo`, and note its numeric
   Forgejo repo ID (not the fork's ID). Create a dedicated PAT as `manjo` in
   Cerberus Forgejo: **Public only**, **`write:user` only** for plain dispatch.
   This permits GET `/user` and GET/POST/DELETE on `/user/actions/runners`
   and its subroutes as applicable; it is not runner-only authority (it can
   even add account SSH keys). See the
   [trusted module header](modules/rites/_forgejo-ephemeral-trusted.nix) for
   the exact authority. Specific-repo PATs cannot carry `write:user`.
2. Configure the pool in the fleet module in
   `modules/rites/forgejo-runner-ephemeral.nix` (replace `9` only when
   enrolling a different public upstream). Trust policy is separate from dispatch:

   ```nix
   services.imperium.forgejoEphemeral.pools.ugalabugala = {
     forge = "ugalabugala";
     scope.user = "manjo";
     labels = [ "nix-eph" ];
     dispatch = [ 9 ];
     trust = {
       repos."9" = { owner = "manjo"; name = "rust-app-template"; };
       users = [ "manjo" ];
     };
   };
   ```

   `dispatch = "owner"` admits jobs from the pool owner's whole queue;
   use a nonempty list of positive upstream IDs to restrict it. A trusted
   repo must be in that list, and `trust.repos` needs `trust.users` (both
   asserted). Labels, dispatch and trust entries filter the dispatcher, not
   the PAT. With `trustedJobs` off the trust entries are inert; each
   dispatcher then logs `trust allowlist configured but trusted jobs are
   off` once per pool at startup. Every slot serves
   every pool, rotating across eligible pools and taking the smallest
   numerical eligible job ID within the selected pool. Jobs must request
   exactly one configured label; a guest with dynamic routing gets only
   that label. Each forge has one PAT, loaded as `forgejo-pat-<forge>`.
   Configure the pool before generating its encrypted var:

   ```sh
   CLAN_NO_COMMIT=1 clan vars generate ryza --generator forgejo-ephemeral-ugalabugala
   ```

   Paste the PAT only at the hidden prompt, never into a command, shell
   environment or log. It is a per-machine, host-only `root:root` `0400` secret.
   Commit the pool configuration **together with** the encrypted per-machine
   var and its Clan access metadata; never deploy the configuration on its own.
3. Check host RAM/disk headroom for the additional 2-vCPU/4-GiB guest and
   sparse 50-GiB overlay and 20-GiB `/var` images. Review the `vm-eph-1` tap
   ACLs: public HTTPS and only Cerberus (`192.168.1.105`) on the LAN for
   DNS (TCP/UDP 53) and HTTPS (TCP 443). Ryza source-NATs the tap to the
   dedicated `ryza-eph` address in the [network chart](modules/cartographa/_chart.nix).
   The slot's size, tap number and SNAT address are data in
   [`modules/rites/_ci-slots.nix`](modules/rites/_ci-slots.nix), which
   Cerberus's guard reads too.
   The shipped guest pins `forge.ugalabugala.org` and `ncps.noosphere.uk`
   to Cerberus. Guests with dynamic routing also pin `forge.noosphere.uk`.
   Caddy allows only those three HTTP hosts from the slot's source address
   and relays the `*.noosphere.uk` hosts through its existing proxy.
   There is no direct Traefik VIP access or guest access to Ryza's control
   plane or other CI guests. Confirm the resolved addresses and dependency
   endpoints before rollout; don't broaden ACLs or PAT scopes to make a
   failing check pass.
   Check that the router has no TCP 443 hairpin port-forward to Cerberus:
   a hairpin could hide the slot's dedicated source address from Caddy.
4. Cerberus's guard is unconditional; deploy it at any time
   (`clan machines update cerberus`), even with the pilot off. Before enabling
   Ryza, check that `caddy.service` is active and its latest config load
   succeeded. In `/etc/caddy/caddy_config`, confirm that the vhosts invoke
   `stygies-access` and that `@blockedEphemeral` matches `192.168.1.249` and
   allows only the two Forgejo hosts and NCPS. Check again before rolling
   Cerberus back while the pilot is enabled. Do not enable the slot without
   the guard.
   Once verified, deploy Ryza
   (`clan machines update ryza`), check
   `journalctl -u forgejo-ephemeral-dispatcher@ryza-eph-1.service` for auth errors, and verify
   `microvm@ryza-eph-1.service` stays stopped without demand. No persistent
   runner registration command is needed.

**Exercise the pilot.** Open a reviewed `pull_request` test PR in
`rust-app-template`. Change `ci-impure`'s runner selection and timeout,
insert the probe below first, and retain the checkout/build/test steps.
Do not use `pull_request_target` or reference Actions secrets, and set
`persist-credentials: false` on checkout. Forgejo still creates its normal
per-task Git token; it is distinct from the runner token.

Host-mode workflow steps may not inherit `CREDENTIALS_DIRECTORY` from the
runner service; this has not been verified. The probe fails closed if the
variable is missing or points elsewhere. Treat that as an inconclusive
credential check, not a pass; do not dump credentials to diagnose it.

```yaml
jobs:
  ci-impure:
    runs-on: nix-eph
    timeout-minutes: 60
    steps:
      - name: Check one-job isolation without disclosing credentials
        shell: bash
        env:
          EPHEMERAL_DYNAMIC_ROUTING: "0" # Set to "1" for the two-pool test below.
        run: |
          set +x
          set -euo pipefail
          fail() { printf 'isolation FAILED: %s\n' "$1" >&2; exit 1; }
          d=${CREDENTIALS_DIRECTORY:?missing runtime credential directory}
          [[ "$d" == /run/credentials/forgejo-one-job.service ]] ||
            fail 'unexpected credential directory'
          credentials=(runner-uuid runner-token job-handle)
          endpoints=(https://forge.ugalabugala.org/api/v1/version https://ncps.noosphere.uk/nix-cache-info)
          if [[ $EPHEMERAL_DYNAMIC_ROUTING == 1 ]]; then
            credentials+=(forgejo-url runner-label)
            endpoints+=(https://forge.noosphere.uk/api/v1/version)
          fi
          for k in "${credentials[@]}"; do
            [[ -f "$d/$k" && -r "$d/$k" && -s "$d/$k" ]] ||
              fail 'expected credential not available'
          done
          shopt -s dotglob nullglob
          for path in "$d"/*; do
            expected=false
            for k in "${credentials[@]}"; do
              [[ ${path##*/} != "$k" ]] || expected=true
            done
            "$expected" || fail 'unexpected runtime credential'
          done
          [[ ! -e "$HOME/.netrc" && ! -e /root/.netrc &&
             ! -e /var/lib/microvms &&
             ! -e /var/lib/forgejo-ephemeral-dispatcher &&
             ! -e /run/microvm-credentials &&
             ! -v AWS_SHARED_CREDENTIALS_FILE ]] || fail 'unexpected host or cache path'
          awk '
            { for (i = 7; i <= NF && $i != "-"; i++); fs = $(i+1) }
            fs ~ /^(virtiofs|9p|nfs.*|cifs)$/ {
              if (fs != "virtiofs" || $5 != "/nix/.ro-store" || $6 !~ /(^|,)ro(,|$)/)
                bad = 1
              else
                store++
            }
            END { exit (bad || store != 1) }
          ' /proc/self/mountinfo || fail 'unexpected shared mount or writable lower store'
          for url in "${endpoints[@]}"; do
            peer=$(curl -fsS --noproxy '*' --connect-timeout 3 --max-time 8 \
              -o /dev/null -w '%{remote_ip}' "$url") ||
              fail 'allowed HTTPS endpoint did not respond successfully'
            [[ $peer == 192.168.1.105 ]] || fail 'allowed HTTPS endpoint did not use Cerberus'
          done
          rc=0
          longhorn=$(curl -s --noproxy '*' --connect-timeout 3 --max-time 8 \
            --resolve longhorn.noosphere.uk:443:192.168.1.251 -o /dev/null \
            -w '%{http_code} %{time_connect}' https://longhorn.noosphere.uk/) || rc=$?
          [[ ( $rc == 7 || $rc == 28 ) && $longhorn == '000 0.000000' ]] ||
            fail 'direct Longhorn VIP TCP connection was not blocked'
          proxmox=$(curl -sS --noproxy '*' --connect-timeout 3 --max-time 8 \
            --resolve proxmox.ugalabugala.org:443:192.168.1.105 -o /dev/null \
            -w '%{http_code}' https://proxmox.ugalabugala.org/) ||
            fail 'could not verify the Cerberus guard response'
          [[ $proxmox == 403 ]] || fail 'Cerberus did not deny Proxmox with HTTP 403'
          for addr in 10.99.2.1 10.99.0.2 10.99.1.2 192.168.1.105; do
            if timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$addr" 22 2>/dev/null; then
              fail 'CI control port reachable'
            fi
          done
          printf 'isolation probe passed\n'
```

Before approval, confirm from a permitted source that the Longhorn VIP
accepts TCP 443 and the Proxmox vhost produces its expected upstream
response without the pilot guard. A closed port or an upstream error
does not prove the pilot policy.
Also verify the negative port-22 targets actually listen; substitute
confirmed control ports/addresses (including an unrelated LAN listener) if
not. For a host-file canary, put a non-secret file on Ryza outside
`/nix/store` and add a presence check for its path to the probe. Do not dump
environments, mount tables, credential directories or file contents.

**Verify Noosphere dispatch.** On a reviewed `pull_request` test in
`manjo/auspex`, use `runs-on: nix-eph` and the isolation probe above with
`EPHEMERAL_DYNAMIC_ROUTING: "1"`. Require the Noosphere version endpoint to
respond through Cerberus and all negative probes to pass. The Noosphere PAT
is shared by both Noosphere pools: it needs `write:organization` and must
belong to an org owner. A Public only PAT cannot reach a non-public org.
Both Noosphere pools currently dispatch untrusted. Check the pool-tagged
journal and the correct Forgejo user or org runner inventory for creation
and cleanup of the one-job registration.

**Verify cleanup and cancellation.** Check the dispatcher and slot journals
for the pool, job attempt, runner ID, VM exit and deletion. Using that
forge's dedicated PAT, confirm its Actions runner inventory (all pages)
no longer contains the ID: `GET /api/v1/user/actions/runners` for a user
pool, or `GET /api/v1/orgs/<org>/actions/runners` for an org pool.
Keep the PAT out of command arguments, shell history and logs. Also verify
`nix-store-overlay.img` and `var.img` are gone from
`/var/lib/microvms/ryza-eph-1/job` and that the slot's staged runner
credential directory is gone (`/run/microvm-credentials/ryza-eph-1`
locally, or `/run/microvm-credentials/forgejo-ryza-eph-1/ryza-eph-1` remotely).
`systemctl show -p Result microvm@ryza-eph-1` should report `success` after a
good job. The installer (re-run before every VM start and dispatcher start)
creates the slot directories and refuses a pre-existing symlink; tmpfiles
cannot create them, because `/var/lib/microvms` is owned by `microvm`. The
empty `job/` directory stays for reuse.

| Slot class | Writable store | Runner timeout | Guest limit | Host VM limit |
|---|---:|---:|---:|---:|
| `std` (Ryza) | 50 GiB | 180 min | 190 min | 195 min |
| `large` | 150 GiB | 360 min | 370 min | 375 min |

Both classes collect the writable store below 20% free, targeting 50%.
Workflow timeouts still apply (60 min for the pilot probe). The dispatcher
stops any job that has not received a trusted verdict 65 min after first
observing pickup. If polling fell behind, it counts from the last known
waiting poll or the recorded VM start. The timestamp survives dispatcher
restarts. A separate slot-host timer queues a stop after 75 min from boot
submission even if the dispatcher or its SSH connection is down. Only
successful trust delivery disarms it while the VM is running. Host startup
and shutdown have separate 90 s and 30 s limits.

The guest uses one addressed `one-job --wait-timeout 300s` process. It
keeps the same fetch request key across transport retries. If the last
addressed fetch failed, it replays that key once after the pickup deadline
on a fresh context bounded to five seconds, to recover a task the forge
may already have assigned. It powers off on completion or pickup expiry.
If the handle is still waiting and unassigned after runner deletion, the
dispatcher releases it with backoff.
After three boots without pickup for the same attempt, it retires the
handle and logs the reason; cancel and re-run that attempt to retry it.
Forgejo v15.0.12 deletes assigned ephemeral registrations on
[`UpdateTask` completion](https://codeberg.org/forgejo/forgejo/src/tag/v15.0.12/routers/api/actions/runner/runner.go#L332-L339)
and on [`StopTask`](https://codeberg.org/forgejo/forgejo/src/tag/v15.0.12/services/actions/task.go);
its [runner interceptor](https://codeberg.org/forgejo/forgejo/src/tag/v15.0.12/routers/api/actions/runner/interceptor.go#L21-L45)
rejects unknown registrations. Use the tagged source and PAT-side absence
as evidence; do not copy or replay the runner token. A never-assigned
registration still needs dispatcher reconciliation.

On an idle slot, use
`sudo systemctl edit --runtime --drop-in=pilot-cancellation.conf microvm@ryza-eph-1.service`
to add a temporary drop-in:

```ini
[Service]
ExecStartPre=/run/current-system/sw/bin/sleep 75
```

Run `sudo systemctl daemon-reload`. The delay counts against the unit's
90-second `TimeoutStartSec`; leave time for normal preflight. Queue the
reviewed pilot job, wait for registration and the startup delay, then
cancel in the UI during the delay, before any task is assigned or steps
run. The dispatcher stops the slot after two consecutive successful job
polls no longer list its handle. It polls every 15 seconds during the
first five minutes, then every minute. It queues (and logs) that stop once
per slot run, again only if the slot is still busy 90 seconds later. A guest
cancelled mid-boot ignores the ACPI powerdown. The unit then ends
`failed`/`timeout` after its 30-second `TimeoutStopSec`. That is expected
for this one case. When a stop the dispatcher queued in this run ends in
`timeout`, it runs `systemctl reset-failed` on the unit after scrubbing and
logs `reset microvm@ryza-eph-1.service after its cancellation stop timed out`,
so a later deploy doesn't report a failed unit. Any other failure (a
preflight refusal, a signal, OOM, `RuntimeMaxSec`), or a timeout after a
dispatcher restart, stays failed for inspection and logs
`slot ended <result>; left failed for inspection`. Clear it with
`systemctl reset-failed` once you've looked. Verify local and remote cleanup,
remove only the test drop-in
(`/run/systemd/system/microvm@ryza-eph-1.service.d/pilot-cancellation.conf`),
and run `sudo systemctl daemon-reload` again. Also test cancelling with a
reviewed job already running; verify the same cleanup without the delay
override.

**Compare performance.** Benchmark a trusted revision on the persistent
`nix-vm` runner, then the same checkout, steps, dependencies and inputs
on `nix-eph` (exclude probe time or include an equivalent timing boundary).
Compare fresh writable state on both sides on the same host/forge under
similar load; if the persistent workspace/action/Cargo caches cannot be
made fresh safely, label that result warm rather than calling it a cold
baseline. Do not flush the shared host store or ncps. Record substitution
hits, store/cache warmth, sccache policy, CPU/RAM/build slots, job wall time,
queue-to-pickup including boot, teardown/revocation latency and peak RAM/disk.
Repeat the ephemeral run with fresh images; fresh disks do not mean cold
shared caches.

**Pause before maintenance, rotation or disable.** On the dispatcher host,
`sudo touch /run/forgejo-ephemeral/pause` pauses every slot. To pause only
`ryza-eph-1`, use `sudo touch /run/forgejo-ephemeral-dispatcher/pause`.
For another slot, find its `--pause-file` in
`systemctl cat forgejo-ephemeral-dispatcher@<slot>.service`.
Pause blocks new dispatches, not cleanup. Before reconfiguring pools or
rolling back, use the global pause. Let in-flight jobs finish (or cancel
them); keep all old PATs valid until cleanup converges. Check **every**
slot is idle with no staged credentials or job images, the corresponding
Forgejo runner inventories no longer contain the dispatchers' registrations,
and **every pool's state file in every slot's state directory** has
`active: null` and `ambiguous: {}`. The original `ugalabugala`/`manjo` user
queue keeps `state.json`; other queues have identity-specific filenames.
Before rolling back to an older dispatcher, also wait for any `unpicked`
retry entries to clear (finish or cancel the associated queued attempts
and allow another poll). The older dispatcher cannot read the new
in-flight trust fields or missed-pickup state. Do not edit state files.
Find each state directory with
`systemctl show -p StateDirectory --value forgejo-ephemeral-dispatcher@<slot>.service`;
`ryza-eph-1` uses `/var/lib/forgejo-ephemeral-dispatcher` on Ryza and
`/var/lib/forgejo-ephemeral-dispatcher-ryza-eph-1` on the remote dispatcher.
Do not edit state or claim files.
Remove the relevant pause flag to resume. Both flags survive dispatcher
restarts, not a host reboot; restore them before resuming maintenance.

Pause and drain before switching to the pool-aware generation, too.
The original pilot keeps the same guest, state file, and pause paths.

**Upgrade from `forgejo-ephemeral-dispatcher.service`: pause and drain first.**

1. Set the old `/run/forgejo-ephemeral-dispatcher/pause` flag and drain
   `ryza-eph-1` as above. Do not switch generations with a live or pending VM:
   the old generation did not write a run marker.
2. On Ryza, check `df -B1 --output=avail /var/lib/microvms`: require at least
   `85899345920` available bytes (80 GiB). Stop the old service, then deploy.
3. Verify that only `forgejo-ephemeral-dispatcher@ryza-eph-1.service` is
   running, its journal verifies the PAT identity, and the old pause flag is
   still present. Slot 1 reuses both the state directory and pause path; copy
   nothing. Remove the pause flag, run one `nix-eph` job, and check cleanup.

To roll back, pause slot 1 using the same flag, drain it, stop the instance,
then deploy the old generation.

**Run marker recovery.** Slotctl writes a root-only `<slot>.run` file next to
its staged credential directory (`/run/microvm-credentials/ryza-eph-1.run`
on the pilot; other slots use `/run/microvm-credentials/forgejo-<slot>/`).
An unknown marker is logged and scrubbed with the slot's job files once the
VM and its support units are idle. While the VM is live or has a queued job,
leave the marker alone. If normal cleanup still refuses (for example, a
corrupt marker), pause and stop the dispatcher instance, confirm the VM and
its support units are stopped with no pending jobs, then move only the
marker aside as root. Restart the still-paused dispatcher and verify its
scrub and runner reconciliation before unpausing. Do not reset `state.json`;
if it was lost and Forgejo still has a dispatcher runner, reconcile that
registration before resuming.

**Operator opt-in: add a second local Ryza slot.** After verifying the
single-slot upgrade, pause and drain both the `nix-eph` and persistent
`nix-vm` work before changing capacity. In `machines/ryza/forgejo-runner.nix`
reduce the persistent guests' combined budget from 6 vCPUs / 14 GiB to
4 vCPUs / 8 GiB. In `modules/rites/_ci-slots.nix` add `ryza-eph-2` under
`ryza.slots`: same sizing as `ryza-eph-1`, but `index = 2`. The two 5 GiB
slot slices plus the 8 GiB persistent budget total 18 GiB of Ryza's 24 GiB.
Keep the host-wide pause in place during the deploy so the new instance
starts paused. No SSH key or new PAT is needed for local slots.

Before registering and again before starting, the slot requires its full
configured image capacity plus 10 GiB free on the image filesystem
(80 GiB per standard Ryza slot). These checks do not reserve space or
budget for peers: provision for both sparse slots growing concurrently.
`maxSlots` caps a pool across all slots using durable claims, not just
running VMs. Leave it at the default or at least 2 for this test. After
unpausing, queue a three-job `nix-eph` matrix in the pilot pool: two VMs
should run at once and the third wait. Across both journals require one
boot per job attempt and no duplicate registration while a claim is held.
An unused registration from a definite pre-start refusal is deleted before
retry. Repeated definite start refusals also back off the entire slot
(7 seconds, doubling up to 600 seconds); the fifth consecutive refusal
logs one escalation. A successfully submitted start resets the slot-wide
backoff; per-handle cleanup and retry still apply. The pre-claim space
check logs the first refusal, a changed refusal and recovery, not repeats.
Verify cleanup for both slots. To roll back capacity, pause and drain both slots
and the persistent work, remove `ryza-eph-2`, restore the `nix-vm` budget,
deploy Ryza, and unpause.

#### Move the dispatcher off Ryza (HOM-32 PR 7, operator only)

The fleet-wide `dispatcher` settings live in `modules/rites/_ci-slots.nix`.
On merge, `remote = false`: Ryza keeps the local dispatcher, both PAT vars,
and its two persistent `nix-vm` guests. Only the pickup fix and watchdog
configuration change its build. Cerberus gets no dispatcher or new vars
prompts; its persistent runners and Caddy configuration are unchanged.

With `remote = true`, the selected `host` (default `cerberus`) takes both
PATs and the slotctl private key. No persistent Forgejo runner runs on
the selected host. The flip disables both Cerberus `nix` runners and
their sccache setup: `nix` capacity remains on Terra, Luna and Sol. That
includes all of `machines.yml` (`update`, `manifests` and the per-machine
build matrix, up to 300 min each), which then runs only within those
nodes' runner slices (2 CPU / 4 GiB, Luna 3 GiB) instead of sometimes on
Cerberus (3 CPU / 8 GiB): large closures can run out of memory there. Run
one `workflow_dispatch` of `machines.yml` before the flip if in doubt;
PR 11 moves it to its own label. Ryza
keeps both `nix-vm` guests, their runner tokens, CI key, ncps netrc and
sccache key until PR 12. PR 14 removes the remaining persistent runner
code and registrations. Keep fork approvals manual until persistent
runners are retired and their credentials rotated.

Ryza loses the ephemeral dispatcher and its PATs, not the persistent
guests' secrets. It authorizes exactly one slotctl key beside the
existing admin keys: `restrict`, a forced command and `from=` the
dispatcher's chart IP. The client binds to that IP and pins Ryza's
ed25519 `openssh` var. The remote dispatcher masks the host's secret
directories and gets only its declared private copies from systemd.
Trust stays off; see the separate opt-in below.

1. Globally pause Ryza's ephemeral dispatcher. Confirm the drain: no
   active run or unresolved registration in any pool, no busy slot or
   support unit, no staged credentials or job images, and old ephemeral
   registrations gone from both forges. Drained Ryza state need not move:
   trust was off, so there are no trust pins. Its retired-handle history
   will not transfer; cancel stale queued attempts you do not want retried.
   Drain both Cerberus `nix` runners too: once neither is running a job
   (the deploy removes them and would cancel one, e.g. a 5-hour
   `machines.yml` build), run `systemctl stop forgejo-runner-ugalabugala
   forgejo-runner-noosphere` on Cerberus so queued `nix` jobs go to Terra,
   Luna and Sol. Their forge rows stay registered (offline) until PR 14.
   Do not stop Ryza's `nix-vm` guests.
2. In the operator's working tree, set `dispatcher.remote = true` to
   expose the new generators. Do **not** deploy or publish that flip
   until the vars exist. Create **new** dedicated PATs as `manjo`; do not
   reuse either Ryza token. Ugalabugala: **Public only**, **`write:user`**.
   Noosphere: **`write:user` + `write:organization`**, not Public only
   (the org queue is non-public). Paste only at the hidden prompts.

   ```sh
   CLAN_NO_COMMIT=1 clan vars generate cerberus --generator forgejo-ephemeral-ugalabugala
   CLAN_NO_COMMIT=1 clan vars generate cerberus --generator forgejo-ephemeral-noosphere
   CLAN_NO_COMMIT=1 clan vars generate cerberus --generator forgejo-slotctl-ssh
   ```

   Commit the generated vars and Clan access metadata together with the
   flag flip. Leave the Ryza PAT vars and those tokens valid for rollback.
3. On Cerberus, before starting the new dispatcher, set its global pause:
   `sudo install -d -m 0700 /run/forgejo-ephemeral` then
   `sudo touch /run/forgejo-ephemeral/pause`. Stop the drained Ryza
   dispatcher. Deploy **Ryza first**, then **Cerberus**, while both are
   paused. Restore the pause marker first if either host rebooted.
4. On Cerberus check `journalctl -u 'forgejo-ephemeral-dispatcher@*'`
   for `Forgejo PAT identity verified` on each pool and verify
   `systemctl show -p NRestarts forgejo-ephemeral-dispatcher@ryza-eph-1.service`
   is not increasing. Even while paused the actual dispatcher performs
   startup `observe` and `withdraw` through its sandbox. Confirm neither
   persistent runner is active on Cerberus. On Ryza verify both `nix-vm`
   guests remain enabled and neither dispatcher unit nor PAT var remains.
   Check `LoadCredential` for absence of dispatcher credentials; the two
   persistent guests still have their own credential staging units.
   Check root's slotctl authorization for the expected `from=` and command.
5. Run the deferred live SSH `observe` check **from Cerberus**, still
   paused. From `systemctl cat forgejo-ephemeral-dispatcher@ryza-eph-1.service`
   take the `--ssh-command` wrapper path and the source path after
   `LoadCredential=slotctl-ssh-key:` (paths only, not key contents). With
   `wrapper` and `key_source` set to those paths:

   ```sh
   sudo systemd-run --wait --pipe --collect \
     --property="LoadCredential=slotctl-ssh-key:$key_source" \
     --property=RuntimeDirectory=forgejo-slotctl-probe \
     "$wrapper" '--slot ryza-eph-1 observe'
   ```

   Require success, with `vm` and `again` idle, no busy support units and
   `"run":null`. This exercises the pinned key, source restriction,
   forced command and slot-side transient sandbox without starting a job.
6. Unpause **Cerberus**. Run a reviewed `nix-eph` job and verify pickup,
   no trust delivery, and cleanup on Ryza. Once verified, revoke both
   old Ryza PATs and remove their obsolete per-machine vars:

   ```sh
   git rm -r -- vars/per-machine/ryza/forgejo-ephemeral-ugalabugala \
     vars/per-machine/ryza/forgejo-ephemeral-noosphere
   ```

   The pinned Clan CLI has no command to delete abandoned per-machine
   vars; `clan vars list ryza` checks declarations, not stale files.
   Commit the deletions. Keep Ryza's shared CI recipients for `nix-vm`
   now; remove them only when PR 12 retires those guests.

**Rollback.** Pause and drain the remote dispatcher, then stop its
instances. Enroll fresh Ryza PATs first if the old ones were revoked.
On Ryza restore the pause even after a reboot:
`sudo install -d -m 0700 /run/forgejo-ephemeral && sudo touch /run/forgejo-ephemeral/pause`.
Set `dispatcher.remote = false`, deploy Ryza and Cerberus, verify only
Ryza is dispatching, then unpause it. This restores Cerberus `nix`
capacity; Ryza's `nix-vm` scheduling never changed.

**Move the dispatcher role again.** Change only `dispatcher.host` in
`modules/rites/_ci-slots.nix` to a base-tagged NixOS host with a chart
address. Drain its persistent runners if present; they stop when it
becomes the dispatcher. Cerberus's own runners stay off for good once
`remote = true`, even when the dispatcher moves elsewhere, so moving the
role to Terra leaves `nix` on Luna and Sol only until PR 13. Generate its fresh PATs and its own
`forgejo-slotctl-ssh` key (do not copy the old private key). If trust is
already enabled, ensure the shared CI credentials can deploy there.
Pause and drain, stop the old dispatcher, and carry over each drained
slot's root-owned state directory so queue identities and trust user pins
are preserved. Pause the new host and deploy slot hosts first so they
replace the old source/key, then deploy the new dispatcher. Repeat the
SSH and job checks above before unpausing. Nothing follows this setting
for **guest egress**: that is the separate `guard` setting, see "What
moves with Cerberus" under trusted slot egress below.

**Rotate a PAT.** Pause and wait for cleanup to converge with the old
PAT as above. Create its replacement with the required scopes, regenerate
the forge's encrypted var on the **current dispatcher host** using its
enrollment command with `--regenerate`, and deploy the new var while paused.
The var path does not change; the service loads PATs only at startup. Restart
all `forgejo-ephemeral-dispatcher@<slot>.service` instances using that PAT.
Require the new invocation's journal to confirm the expected PAT identity
for that forge before revoking the old PAT. This verifies authentication
and identity, not write scope. Unpause only after verifying the rotation.

**Disable the pilot.** Pause, cancel any queued `nix-eph` runs you do not
intend to leave waiting, and wait for local and remote cleanup as above.
Disable the ephemeral services on the slot host and dispatcher; the
Cerberus guard stays in place.
Revoke the dedicated PATs only after cleanup; do not erase pending
reconciliation state.

#### Trusted `nix-eph` jobs (HOM-31, opt-in)

Trust is off by default, including after the remote dispatcher cutover.
With trust off the slot has no trust share.
When it is on, every job still **boots untrusted**. No repository is
verified at startup. After pickup, the dispatcher looks up only repos
listed in that pool's `trust.repos`, mapping job `task_id` → task →
`run_number` → run. The run's repo ID and owner must match the allowlist,
and it must be on the **default branch**: a push or `workflow_dispatch`
by someone in `trust.users`, or, only for repos with
`trust.repos.<id>.schedules = true`, a schedule triggered by
`forgejo-actions` (user ID `-2`). On the first idle poll with trust enabled,
the dispatcher pins each configured trust login to its account ID, before
it can trigger a trusted job. It keeps existing pins across restarts and
prunes logins removed from `trust.users`. The repo must not be a pull
mirror or have a write deploy key, and only pinned users may write its
default branch (below). Only then does the dispatcher deliver the signing
key and netrc. Slotctl writes them to `ryza-eph-1-trust` in the slot's
runtime credential parent (root `0700`, files `0400`).
The guest sees that directory as a read-only virtiofs share at `/run/ci-trust`,
readable only by guest root. The nix-daemon's post-build hook then uploads
builds to ncps. Fork PRs, AGit PRs (Hermes's included), fork re-runs or
approvals by manjo, every `pull_request*` event, lookup errors and 403s get
nothing. The job can still run up to the untrusted 65 min limit, and
the dispatcher logs the reason. Builds finished before delivery are not
uploaded. sccache stays off on `nix-eph`. The full rule, the API fields it
reads and who can read what (host, guest, escaped QEMU/virtiofsd) are in
`modules/rites/_forgejo-ephemeral-trusted.nix`.

On restart the dispatcher withdraws delivery and has up to 10 min to
revalidate the same recorded task and run. Failure to revalidate stops
the VM. An unresolved `trust.users` login keeps trust off for the pool
until an idle poll can pin it; untrusted dispatch continues.

A login in `trust.users` includes agents and tools that hold its repository
write credentials. Forgejo also attributes deploy-key pushes to the owner,
so any write deploy key on the repository disables trust. A dispatch on
another branch, tag, commit SHA or `pull/N/head` is not trusted. Do not
schedule auto-merges on fork PRs in trusted repos: a merge can land as an
allowed user's default-branch push, including commits added after review.
Require approvals and dismiss stale approvals on the default branch.

**Precondition for `trust.repos`.** `trust.users` filters who *triggers* a
run, never who *wrote* the code it runs: a trusted push runs whatever
earlier writers left on the default branch, and any default-branch push, by
anyone, re-creates the repo's schedules as `forgejo-actions`. So list a
repository only if nobody outside `trust.users` can write its default
branch:

- The personal repo owner and every collaborator with write or admin must
  be in `trust.users`. For org repos, every member of every team with repo
  access must be in `trust.users`, including Owners and read-only teams.
- A branch protection rule named exactly like the default branch (not a
  glob) with the merge allowlist on, the push allowlist on (or pushes
  disabled), both naming only `trust.users` and no team, and no
  unprotected file patterns. Without a merge allowlist any writer can merge
  a PR into the branch.
- No write deploy key, and not a pull mirror.

The dispatcher checks all three on each trust resolution. Forgejo's
branch protection API can hide allowlist teams that have lost repository
access, though enforcement still checks membership by team ID. The
dispatcher therefore checks collaborators' permissions and all members of
teams with repo access directly. An unreadable list fails closed under
the same 10 min trust deadline. These checks see today's access, not prior
writers; audit the default branch before adding a repo.

**Schedules are a separate opt-in** (`schedules = true` on the repo entry,
off by default). A scheduled run's trigger is always `forgejo-actions`, so
trusting it means trusting whoever last wrote the default branch. Enable it
only for a repo that meets the precondition and has a scheduled workflow
that needs the cache, such as a nightly `nix flake update` or a cache-warming
build of `master`. Ryza's `rust-app-template` pool has it off.

**Opt in separately (operator only).**

1. Pause and drain all `nix-eph` slots. Audit the default branch and
   verify the trust preconditions above for every `trust.repos` entry.
2. Set `dispatcher.trustedJobs = true` in `modules/rites/_ci-slots.nix`,
   leaving `dispatcher.remote` unchanged. The shared flag enables the
   dispatcher verdict and the slot-side `deliver` and trust share.
   Enroll replacement PATs with **`read:repository`** in addition to
   the dispatch scopes on both forges; regenerate their vars on the
   active dispatcher host. Keep Public only for the public pilot.
   Repository protection, deploy-key and collaborator probes require
   repo admin; org team member reads are included in the required
   `write:organization` scope.
3. Deploy the paused slot hosts first, then the dispatcher. On a
   remote dispatcher this also deploys `nix-ci-signing-key` and
   `ncps-upload-auth`. Verify its PAT identity checks and unpause.
4. Put a temporary `workflow_dispatch` workflow on rust-app-template's
   default branch with `runs-on: nix-eph`. Dispatch it **as manjo against
   that branch**. In the job, wait at least 30 seconds for pickup and
   delivery, then build a fresh trivial Nix derivation using the repo's
   pinned Nixpkgs and a name keyed by `GITHUB_RUN_ID` and
   `GITHUB_RUN_ATTEMPT`, with `--no-substitute --print-out-paths`.
   Require `trusted: run #N (workflow_dispatch); delivered CI upload credentials`
   and check the resulting path's narinfo on ncps for `ci.noosphere.uk-1`.
   Existing default-branch workflows use `nix` or `nix-vm`; a plain
   master merge does not exercise this test.

**Verify the negative case and cleanup.**

- Manually approve a reviewed fork PR probe on `nix-eph` and require:
  - a Hermes PR logs `untrusted: run #M (fork or AGit pull request); CI upload credentials withheld`,
    and re-running it as manjo logs the same.
- An unlisted repo gets an untrusted verdict without repository calls.
  `trust lookup pending: … HTTP 403…` after pickup can indicate missing
  `read:repository`, insufficient repository permissions (including admin
  permission for deploy-key and branch protection listing), or a Public only
  PAT on a private repo. `Forgejo trust user: HTTP 404` or `307` means a
  `trust.users` login was deleted, renamed or isn't visible to the PAT.
- If a trusted user's account is recreated under the same login, its runs
  log `ID differs from the pinned trust user`. To accept the new account,
  first remove the login from `trust.users` (and remove the trusted repos
  while the list would be empty). Restart every affected dispatcher and
  let it prune its pins, then re-add the login after verifying the new
  account. Do not edit state files.
- The isolation probe above still applies: `$CREDENTIALS_DIRECTORY` holds
  only the five one-job runtime inputs. A trusted job can still check that
  `/run/ci-trust` is unreadable to it
  (`! ls /run/ci-trust`). Never print the files.
- After the VM stops, Ryza's `ryza-eph-1-trust` directory is gone.

**Rotation.** Trusted jobs never see the key bytes, only the hook does.
But a trusted job can get anything it builds signed, so treat the key as
exposed to trusted code. The persistent runners still hand the same key,
netrc and the sccache RW key to every job they run, approved fork PRs
included. Once PR 12 retires Ryza's guests, remove their obsolete
per-machine runner vars after deleting the registrations. The pinned
Clan SOPS backend does not prune a machine that stops declaring a shared
generator. Remove only Ryza's links, then use Clan to re-encrypt each
var from a machine that still declares it (Terra on the default rollout
for upload credentials, Phalanx for workstation sccache):

```sh
git rm -- vars/shared/nix-ci-signing-key/key/machines/ryza \
  vars/shared/ncps-upload-auth/netrc/machines/ryza \
  vars/shared/sccache-garage-key/credentials/machines/ryza
CLAN_NO_COMMIT=1 clan vars fix terra --generator nix-ci-signing-key
CLAN_NO_COMMIT=1 clan vars fix terra --generator ncps-upload-auth
CLAN_NO_COMMIT=1 clan vars fix phalanx --generator sccache-garage-key
```

Verify the three `machines/ryza` links are gone and no recipient group
still grants Ryza access; commit the links and re-encrypted files.
Neither that cleanup nor Git deletion invalidates old ciphertext or
keys already copied. PR 15 rotates the CI signing key, ncps netrc and
sccache key after persistent runners are retired. If you see unexpected
delivery: pause, rotate the CI key and netrc, and audit recent uploads.

**Trust-only rollback.** Pause and drain all slots, and verify their
trust directories are gone. Set `dispatcher.trustedJobs = false` without
changing `dispatcher.remote` or `dispatcher.host`. Deploy both ends,
check `--trusted-jobs` and the share are gone, then unpause the same
dispatcher. After verification rotate the PATs to remove `read:repository`.

#### Trusted slot egress (HOM-32 PR 8, opt-in)

Trusted jobs need Garage S3 (sccache, PR 10), Harbor and ntfy. Cerberus's
Caddy answers 403 to all three for a slot's untrusted source (`ryza-eph`,
`192.168.1.249`). Trust is known only after pickup, so a trusted run
switches to a second source mid-job. Off by default:
`hosts.<host>.egress.trusted = null` in `modules/rites/_ci-slots.nix` means
no address, no unit, no NAT rule, no Caddy matcher, no extra guest pins
and no `--trusted-egress` flag.

With it set (Ryza: `ryza-eph-trusted`, `192.168.1.240` in the
[network chart](modules/cartographa/_chart.nix)):

- **Address.** The slot host carries the address as a /32 on its uplink.
  networkd uses `DuplicateAddressDetection=ipv4`: it probes (RFC 5227,
  like `arping -D`) before it adds or re-adds the address, and drops it on
  a conflict. It never keeps an address another device holds.
- **Switch.** Only after a successful `deliver` does the dispatcher call
  slotctl `egress trusted RUN` (Nix passes `--trusted-egress` when the slot
  host has the address). With `trustedJobs` off there is no delivery, so
  it never calls it. slotctl refuses unless the host has trusted egress,
  the slot delivers, the VM is running with no job queued, and both
  credentials are in the trust share. Then it starts the root oneshot
  `forgejo-ephemeral-trusted-egress@<slot>`. The oneshot checks that the
  /32 is still on the uplink and runs `arping -q -D -c 2 -w 3 -I <uplink>
  <address>`. Then it inserts, first in the chain and above the guard's
  default SNAT rule:
  `POSTROUTING -s <slot-ip>/32 -d <guard>/32 -p tcp --dport 443 -o <uplink> -j SNAT --to-source <trusted>`.
  The filter chains don't change. DNS and public HTTPS keep the untrusted
  source; only HTTPS to the guard moves.
- **End.** `ExecStop` deletes the rule and the flows NATed through it
  (`conntrack -D --orig-src <slot-ip> --reply-dst <trusted>`). The unit
  stops with the VM (`BindsTo`), on slotctl `withdraw` (also at every
  dispatcher start) and on `scrub`. It restarts with the slot's firewall
  guard and follows its reloads, so it stays first. The VM's preflight
  refuses to boot while the unit is up or has a job queued.
- **Caddy on the guard.** `@blockedEphemeral` (every untrusted source) is
  unchanged: `forge.ugalabugala.org`, `ncps.noosphere.uk`,
  `forge.noosphere.uk`. `@blockedEphemeralTrusted` (every trusted source)
  allows those plus `s3.main.garage.noosphere.uk` (path-style S3 only, no
  bucket subdomains), `harbor.noosphere.uk` and `ntfy.ugalabugala.org`.
  Guests pin all six to the guard. From the untrusted source the last
  three still get 403.
- **Refusals** are fixed slotctl codes. `egress-address-conflict` (another
  host answered the probe) and `egress-address-missing` (networkd dropped
  the /32) hold for the rest of the run, which keeps its credentials: ncps
  uploads still work, but S3, Harbor and ntfy don't. The dispatcher logs
  `trusted egress refused for this run: …; it stays on the untrusted source`
  once. Other failures (`egress-failed`, `egress-not-delivered`, …) are
  retried at each busy poll and logged once per message as
  `trusted egress pending: …`.

**Duplicate-address guard and the router.** The router's DHCP pool can't
be inspected. On 2026-11-26, ARP from Ryza got no answer for .240–.242 and
.244–.247, and .243 is keksic. So the block .240–.247 (minus .243) is kept
for slot SNAT sources, and the slot host probes before each use instead of
trusting the pool. Someone with router access should exclude .240–.247
from DHCP. Until then, a device that is leased .240 only makes trusted
egress refuse; that device keeps its address.

**Enable (operator only).**

1. On Ryza, check the address: `sudo arping -D -c 3 -I ens18 192.168.1.240`
   must exit 0 (`Received 0 response(s)`). If anything answers, choose
   another free address from the block for `ryza-eph-trusted` in the chart.
2. Set `hosts.ryza.egress.trusted = "ryza-eph-trusted";` in
   `modules/rites/_ci-slots.nix`. Leave `dispatcher` unchanged.
3. Deploy **Cerberus first**, so the matcher exists before any slot can use
   the address: `clan machines update cerberus`. Check that `caddy.service`
   is active, and that `grep -A3 '@blockedEphemeral' /etc/caddy/caddy_config`
   shows both matchers: `remote_ip 192.168.1.249` with exactly the three
   names above, and `remote_ip 192.168.1.240` with exactly the six. The
   dispatcher restarts with `--trusted-egress` (`systemctl cat
   forgejo-ephemeral-dispatcher@ryza-eph-1.service`).
4. Pause on Cerberus (`sudo touch /run/forgejo-ephemeral/pause`), wait for
   the slot to go idle, then `clan machines update ryza`. On Ryza check:
   `ip -4 -o address show dev ens18` lists `192.168.1.240/32`,
   `systemctl status forgejo-ephemeral-trusted-egress@ryza-eph-1` is
   inactive, and `sudo iptables -t nat -S POSTROUTING` has no
   `--to-source 192.168.1.240` rule. Unpause.
5. Check the address and both matchers from Ryza's host (not a slot), with
   trust still off:

   ```sh
   r=(--resolve s3.main.garage.noosphere.uk:443:192.168.1.105 --resolve harbor.noosphere.uk:443:192.168.1.105)
   curl -sS -o /dev/null -w '%{http_code}\n' "${r[@]}" --interface 192.168.1.249 https://s3.main.garage.noosphere.uk/  # 403 (Caddy)
   curl -sS "${r[@]}" --interface 192.168.1.240 https://s3.main.garage.noosphere.uk/  # Garage S3 XML; AccessDenied means reachable
   curl -sS -o /dev/null -w '%{http_code}\n' "${r[@]}" --interface 192.168.1.240 https://harbor.noosphere.uk/api/v2.0/ping  # 200
   ```

   The SNAT switch from inside a slot needs a delivered trusted run, so it
   waits for the trust flip (`trustedJobs`, above). Don't start the unit by
   hand to test it. It binds to the VM: an untrusted job would get the
   trusted source, and with the VM down the VM preflight refuses anyway.
6. After the trust flip, extend the trusted `workflow_dispatch` probe
   (trusted step 4 above). After delivery, `curl -sS
   https://s3.main.garage.noosphere.uk/` must return S3 XML and `curl -sS -o
   /dev/null -w '%{http_code}\n' https://harbor.noosphere.uk/api/v2.0/ping`
   must return 200. Cerberus's journal logs `trusted egress: the run now
   leaves from the slot host's trusted source`. While the job runs,
   `sudo iptables -t nat -S POSTROUTING` on Ryza lists the trusted rule
   first. The same curls in a reviewed fork PR probe get Caddy's 403.
   After the VM stops there's no `192.168.1.240` rule, `sudo conntrack -L
   --orig-src 10.99.2.2 --reply-dst 192.168.1.240` is empty, and the unit
   is inactive. On a conflict, the unit's journal says `another host
   answers ARP for 192.168.1.240 on ens18; not taking the address`.

**Rollback.** Set `egress.trusted = null` and deploy **Ryza first**: that
stops the unit (its `ExecStop` removes the rule and flows) and removes the
address. Only then deploy Cerberus, which removes the matcher and the flag.
In the opposite order the trusted source would briefly face Caddy with no
matcher, as an ordinary LAN client.

**What moves with Cerberus.** One setting, `guard` in
`modules/rites/_ci-slots.nix`, names the machine slot guests may reach on
the LAN. It sets the guests' DNS server and host pins, the slot firewall's
DNS/HTTPS exceptions and the trusted SNAT rule's destination. Moving
it also means moving what that machine serves: the Caddy matchers
(`machines/cerberus/proxy.nix`; evaluation fails if `guard` names another
machine), the forge, the ncps relay, and the `*.noosphere.uk` relay to
Garage S3 and Harbor, plus ntfy. The slot SNAT addresses stay with their
slot hosts. The dispatcher role (`dispatcher.host`, with the PAT vars and
the slotctl SSH key) moves separately.

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
