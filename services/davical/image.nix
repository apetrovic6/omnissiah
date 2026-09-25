{
  lib,
  dockerTools,
  davical-go,
  cacert,
}:
dockerTools.buildLayeredImage {
  name = "davical-go";
  tag = davical-go.version;

  # The binaries are fully static, so (like upstream's `FROM scratch` image) the
  # image needs no libc, no shell and no zoneinfo — tzdata is compiled into the
  # Go binaries. cacert is the only extra: it makes outbound TLS verification
  # (sslmode=verify-full to PostgreSQL, `davical-cron tz-update`) work without
  # mounting the host bundle.
  # buildLayeredImage/streamLayeredImage take `contents` (buildImage's
  # copyToRoot is not forwarded here).
  contents = [
    davical-go
    cacert
  ];

  extraCommands = ''
    # Mirror the upstream image layout, so the documented commands
    # (`docker exec davical /davical-admin user list`, …) work unchanged.
    for b in davicald davical-admin davical-cron cfg2env; do
      ln -s ${davical-go}/bin/$b ./$b
    done
  '';

  config = {
    # Inbound TLS is expected to terminate in a reverse proxy; davicald speaks
    # plain HTTP on LISTEN.
    Env = [
      "LISTEN=:8080"
      "TZ=UTC"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-certificates.crt"
    ];
    ExposedPorts = {"8080/tcp" = {};};
    Entrypoint = ["/davicald"];
    Labels = {
      "org.opencontainers.image.title" = "davical-go";
      "org.opencontainers.image.version" = davical-go.version;
      "org.opencontainers.image.source" = "https://gitlab.com/davical-project/davical-go";
      "org.opencontainers.image.licenses" = "CC0-1.0 OR Apache-2.0";
    };
  };

  meta =
    davical-go.meta
    // {
      mainProgram = "davicald";
      hydraPlatforms = [];
    };
}
