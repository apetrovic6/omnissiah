# Grafana's read-only access to Blocky's query log, and the cluster side of it.
#
# Blocky (modules/rites/blocky.nix) writes every DNS query into the `blocky`
# database on cerberus's Postgres. Grafana, in the cluster (observability), reads it
# through a second, read-only role `blocky_grafana`. One clan var feeds both sides, so
# nobody types a password (same inversion as reliquary/ntfy and reliquary/memos):
#
#   - password            (secret) the role's password. Not deployed by this generator
#                         itself: the `postgresql-blocky_grafana` generator that
#                         modules/rites/postgresql.nix creates for the role copies it
#                         (passwordDependency), and postgresql-password-init sets it.
#   - grafana-datasource  (non-secret) a sops-encrypted SopsSecret. The operator turns
#                         it into a Secret in `observability` labelled
#                         `grafana_datasource`, which Grafana's datasource sidecar
#                         (kube-prometheus-stack's, resource=both, own namespace)
#                         loads as a provisioned datasource. The password sits in that
#                         Secret's datasource YAML (secureJsonData), so it is encrypted
#                         in git and never in a rendered manifest. Read into the
#                         prometheus-grafana app by
#                         apps/augur/prometheus-stack/blocky-querylog.nix.
#
# The host is cerberus's LAN IP, not a name: the cluster must not need DNS for it.
# Pods leave the cluster masqueraded to their node's address, which the pg_hba rule
# for the LAN cidr on cerberus already allows.
#
# Generate with:
#   clan vars generate cerberus --generator blocky-grafana
# Rotating (--regenerate) means: deploy cerberus (sets the new role password) and
# re-render + push the cluster manifests (the Secret changes), in either order; Grafana
# fails its queries in between.
{
  config,
  self,
  ...
}: let
  ageKey = config.noosphere.agePublicKey;
  generatorName = "blocky-grafana";
  secretFile = "grafana-datasource";
  # SopsSecret name == the Secret it produces. The sidecar picks it up by label.
  secretName = "grafana-datasource-blocky-querylog";
  namespace = "observability";
  # Referenced by the dashboard (apps/augur/prometheus-stack/blocky-querylog.nix).
  datasourceUid = "blocky-querylog";
in {
  flake.nixosModules.reliquary-blocky-grafana = {
    pkgs,
    config,
    ...
  }: {
    clan.core.vars.generators.${generatorName} = {
      share = true;

      files.password.secret = true;
      files.${secretFile}.secret = false;

      runtimeInputs = [pkgs.coreutils pkgs.openssl pkgs.sops pkgs.jq];

      script = ''
        set -euo pipefail

        # Hex only: the value goes into ALTER USER '...' and a connection setting.
        openssl rand -hex 32 | tr -d '\n' > "$out/password"
        password="$(cat "$out/password")"

        # One line of JSON (a YAML subset), so it can sit in a quoted YAML scalar.
        # sslmode=disable: cerberus's Postgres has no TLS; the traffic stays on the LAN.
        datasource="$(jq -cn --arg pw "$password" '{
          apiVersion: 1,
          datasources: [{
            name: "Blocky query log",
            uid: "${datasourceUid}",
            type: "grafana-postgresql-datasource",
            access: "proxy",
            url: "${self.lib.hosts.cerberus}:${toString config.services.imperium.postgresql.port}",
            user: "blocky_grafana",
            editable: false,
            jsonData: {database: "blocky", sslmode: "disable", postgresVersion: 1800, maxOpenConns: 5, maxIdleConns: 2},
            secureJsonData: {password: $pw}
          }]
        }')"

        sops encrypt \
          --age "${ageKey}" \
          --encrypted-suffix "Templates" \
          --input-type yaml --output-type yaml \
          /dev/stdin > "$out/${secretFile}" <<EOF
        apiVersion: isindir.github.com/v1alpha3
        kind: SopsSecret
        metadata:
          name: ${secretName}
          namespace: ${namespace}
        spec:
          secretTemplates:
            - name: ${secretName}
              type: Opaque
              labels:
                grafana_datasource: "1"
              stringData:
                blocky-querylog.yaml: '$datasource'
        EOF
      '';
    };
  };
}
