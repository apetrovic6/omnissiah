# davical-go — CalDAV/CardDAV server, built with Nix

[davical-go](https://gitlab.com/davical-project/davical-go) is the official Go
rewrite of DAViCal. It speaks the same protocols (CalDAV/CardDAV/WebDAV +
scheduling) and runs against the **same PostgreSQL schema** as PHP DAViCal, so it
is a drop-in replacement and can run next to the PHP server during a migration.

Everything in this directory is built from source by Nix: **no Dockerfile, no
`FROM php:…`/apache base image, no `dockerTools.pullImage`, no runtime
`config.php` generation**. `davicald` is one static binary configured entirely
by environment variables, and the container image is just the Nix store subtree
holding those binaries.

| upstream tag | image size (this build) | upstream image |
|---|---|---|
| `v1.0.1` | 15.5 MiB compressed / 46 MiB unpacked | ~40 MiB |

## Files

| file | purpose |
|---|---|
| `package.nix` | `buildGoModule` package → `davicald`, `davical-admin`, `davical-cron`, `cfg2env` |
| `image.nix` | `dockerTools.buildLayeredImage` — scratch-equivalent image (`/davicald` etc. + CA bundle) |
| `default.nix` | aggregates the package and the image |
| `docker-compose.yml` | reference deployment: `davicald` + PostgreSQL 17 + one-shot `admin`/`cron` tools |
| `.env.example` | environment for the compose file |
| `CONFIGURATION.md` | upstream env-var reference (also installed under `$out/share/doc`) |

Flake outputs:

```
nix build .#davical-go         # binaries only (run them directly, e.g. in a systemd unit)
nix build .#davical-go-image   # docker/podman image tarball
```

## Build and load the image

```bash
nix build .#davical-go-image
podman load -i result          # docker: docker load < result
podman images | grep davical   # localhost/davical-go:1.0.1
```

Push it to a registry if the deploy host is remote:

```bash
podman tag localhost/davical-go:1.0.1 harbor.example.org/library/davical-go:1.0.1
podman push harbor.example.org/library/davical-go:1.0.1
```

## Run it (this sequence was verified against PostgreSQL 17)

```bash
NET=davical; podman network create $NET 2>/dev/null

# 1. PostgreSQL (or point DATABASE at your existing cluster — CloudNativePG etc.)
podman run -d --name davical-pg --network $NET \
  -e POSTGRES_DB=davical -e POSTGRES_USER=davical -e POSTGRES_PASSWORD='secret' \
  -v davical-pgdata:/var/lib/postgresql/data \
  docker.io/library/postgres:17-alpine

DSN='postgres://davical:secret@davical-pg:5432/davical?sslmode=disable'

# 2. bootstrap the schema once (DDL + patches live inside davical-admin)
podman run --rm --network $NET --entrypoint /davical-admin -e DATABASE="$DSN" \
  localhost/davical-go:1.0.1 db init

# 3. first user (a calendar is created with it; -admin for admin rights)
podman run --rm --network $NET --entrypoint /davical-admin -e DATABASE="$DSN" \
  localhost/davical-go:1.0.1 user create alice -fullname 'Alice' -password 'wibble' -admin

# 4. the server
podman run -d --name davical --network $NET -p 127.0.0.1:8080:8080 \
  -e DATABASE="$DSN" -e TZ=Pacific/Auckland -e SERVER_DISPLAYNAME='DAViCal' \
  localhost/davical-go:1.0.1
```

Sanity check:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/          # 200 (landing page)
curl -s -u alice:wibble -X PROPFIND -H 'Depth: 0' \
  --data '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>' \
  http://127.0.0.1:8080/alice/                                            # 207 + multistatus
```

Clients use `https://your-host/` (the principal is `/<username>/`); the usual
`.well-known/{caldav,carddav}` redirects are served by davicald.

## With docker-compose

The `.env`-driven reference deployment lives here, but this machine has no
`docker compose`/`podman-compose` provider installed, so it is untested locally —
the equivalent podman commands above are what was verified.

```bash
cp .env.example .env      # set DAVICAL_DB_PASSWORD, SECRET_KEY, BASE_URL
docker compose up -d db davical
docker compose run --rm admin db init
docker compose run --rm admin user create alice -fullname 'Alice' -password 'wibble' -admin
```

## Database

`davical-admin` has the schema (`dba/*.sql`, patches, `appuser_permissions.txt`)
**embedded in the binary**, so `db init` / `db upgrade` / `db status` work from
the image with no source tree.

Two roles are supported: `OWNER_DSN` (DDL, may `CREATE DATABASE`/`CREATE ROLE`)
and `DATABASE` (least-privilege app role used by `davicald`). If `OWNER_DSN` is
unset, single-role mode is used and grants are skipped — fine for a quick setup,
use a separate owner for anything long-lived. The privileged DSN is kept on the
one-shot `admin` service in the compose file, never in the `davicald` container.

Backups are plain `pg_dump` of that database (same as PHP DAViCal).

## Maintenance (cron)

```cron
*/5  * * * *  docker compose -f /path/to/docker-compose.yml run --rm cron refresh-alarms
17   3 * * *  docker compose -f /path/to/docker-compose.yml run --rm cron tz-update
```

`tz-update` fetches over HTTPS — unlike upstream's image, this one ships
`cacert` and sets `SSL_CERT_FILE`, so outbound TLS verification works out of the
box (and `sslmode=verify-full` to PostgreSQL works too).

## TLS / reverse proxy

`davicald` speaks plain HTTP on `LISTEN` (`:8080`), so keep it on loopback and
terminate TLS in front of it:

```caddy
dav.example.org {
    reverse_proxy 127.0.0.1:8080
}
```

## Migrating from PHP DAViCal

1. `pg_dump` the old DAViCal database and restore it into the new PostgreSQL.
2. `davical-admin db status` (as an owner DSN) → `db upgrade` if patches are pending.
3. `cfg2env /etc/davical/config.php > davical.env` converts the old config on a
   best-effort basis (settings without a davical-go equivalent are emitted as
   comments) — review before using.
4. Run both servers against the same database if you want to compare client
   behaviour before switching over.

## Updating

`package.nix` pins `rev = "v<version>"` plus two hashes (source + Go module
bundle). Bump `version`, then let Nix print the new hashes:

```bash
nix build .#davical-go 2>&1 | grep -E 'specified|got'   # copy the "got:" values in
nix-update --flake .#davical-go                          # or automate it
```

Read `CHANGES.md` on every bump — upstream is still moving quickly (1.0.x).

## Notes for whoever wires this into a module later

- `buildLayeredImage`/`streamLayeredImage` accept **`contents`**, not
  `copyToRoot` (that one is `buildImage`-only and is not forwarded).
- `buildGoModule` reads `CGO_ENABLED` from its **`env`** attribute, not from the
  derivation args (passing it as a top-level attr is an overlapping-attr error).
- `go.mod` declares `go 1.26`; `pkgs.go` at this nixpkgs pin is 1.26.7. Go's
  `GOTOOLCHAIN=local` in nixpkgs means an older `go` would fail the build.
- The image has no shell, `curl` or `nc`, so an in-container `HEALTHCHECK` is
  impossible — probe `:8080` from outside.
- `davicald` handles `SIGTERM` gracefully and reloads its request-log config on
  `SIGHUP` (`LOG_CONFIG=/path.yaml`); it needs no init/supervisor shim as PID 1.
- Request logging is off by default (zero overhead); mount a YAML file at
  `LOG_CONFIG` for access logs / `logrotate`.
