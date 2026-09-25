{
  lib,
  buildGoModule,
  fetchFromGitLab,
}:
buildGoModule rec {
  pname = "davical-go";
  version = "1.0.1";

  src = fetchFromGitLab {
    owner = "davical-project";
    repo = "davical-go";
    rev = "v${version}";
    hash = "sha256-3G15xr/12BYkrvh9cHeN63fn+vrV4b/N6y27yYVZHBg=";
  };

  # Update both hashes with `nix-update davical-go` (or `nix build` prints the
  # expected value on a mismatch).
  vendorHash = "sha256-z6e3HBW4T0ZqlMmTFInsjoGRfXgvfleO9C6thpZV8t0=";

  # The server, the maintenance runner and the admin CLI. cmd/davical-test and
  # cmd/fbtest are the upstream regression harness / free-busy probe and need a
  # live DAViCal database, so they are not packaged.
  subPackages = [
    "cmd/davicald"
    "cmd/davical-cron"
    "cmd/davical-admin"
    "cmd/cfg2env"
  ];

  # Fully static binaries (pure-Go postgres driver, tzdata embedded via
  # `import _ "time/tzdata"`), which is what upstream ships in its FROM scratch
  # image too: no libc, no /etc/localtime, no zoneinfo volume.
  # buildGoModule reads CGO_ENABLED from `env`, not from the derivation args.
  env.CGO_ENABLED = 0;

  # Same as upstream's Dockerfile: -trimpath (added by buildGoModule) + -s -w.
  ldflags = ["-s" "-w"];

  # Upstream `make test` / `davical-test run` replays the regression suite
  # against a real PostgreSQL DAViCal schema, so there is nothing unit-testable
  # to run in the sandbox.
  doCheck = false;

  postInstall = ''
    mkdir -p $out/share/licenses/davical-go
    install -m 0644 $src/LICENSE $out/share/licenses/davical-go/LICENSE
    install -m 0644 $src/LICENSE-APACHE $out/share/licenses/davical-go/LICENSE-APACHE
    install -m 0644 -D $src/CONFIGURATION.md $out/share/doc/davical-go/CONFIGURATION.md
  '';

  meta = {
    description = "CalDAV/CardDAV server - Go rewrite of DAViCal, using the existing DAViCal PostgreSQL schema";
    homepage = "https://gitlab.com/davical-project/davical-go";
    changelog = "https://gitlab.com/davical-project/davical-go/-/blob/v${version}/CHANGES.md";
    # dual-licensed upstream: CC0-1.0 OR Apache-2.0
    license = [lib.licenses.cc0 lib.licenses.asl20];
    mainProgram = "davicald";
    platforms = lib.platforms.all;
    maintainers = [];
  };
}
