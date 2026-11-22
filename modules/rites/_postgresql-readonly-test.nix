# VM test of the `readOnlyAccess` grants in modules/rites/postgresql.nix, with the
# real module (the Grafana role that reads Blocky's query log is the user).
# (Underscore prefix: import-tree would otherwise load it as a flake module.)
# Not a flake output; run with
#   nix build --impure -L --no-link --expr \
#     'import ./modules/rites/_postgresql-readonly-test.nix { flake = builtins.getFlake "git+file://'$PWD'"; }'
# `git add` new files first, or the flake's git-tree copy will not see them.
#
# What it proves, over TCP with scram passwords like production:
#   - the read-only role reads `log_entries`, which Blocky's role creates AFTER the
#     grants ran (the first-start order in production);
#   - it cannot INSERT/UPDATE/DELETE/TRUNCATE, run DDL (CREATE/ALTER/DROP), or
#     create objects in the schema;
#   - it cannot read a table in another database (nor pg_shadow);
#   - re-running the grants (every deploy does) is harmless.
# The clan vars generators are stubbed: the module only needs a password file path.
{flake}: let
  pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  pw = {
    blocky = "aaaa1111";
    ro = "bbbb2222";
    other = "cccc3333";
  };
  pwFile = name: pkgs.writeText "pw-${name}" pw.${name};
in
  pkgs.testers.runNixOSTest {
    name = "postgresql-readonly";

    nodes.db = {
      lib,
      config,
      ...
    }: {
      imports = [flake.nixosModules.postgresql];

      # Stand-in for clan-core's vars: the module declares generators and reads
      # `files.password.path`; here the path is a store file with a known password.
      options.clan.core.vars.generators = lib.mkOption {
        default = {};
        type = lib.types.attrsOf (lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.anything;
        });
      };
      config = {
        clan.core.vars.generators = {
          postgresql-blocky.files.password.path = pwFile "blocky";
          postgresql-blocky_grafana.files.password.path = pwFile "ro";
          postgresql-other.files.password.path = pwFile "other";
          postgresql-aaa_broken.files.password.path = pwFile "other";
        };

        services.imperium.postgresql = {
          enable = true;
          listenAddresses = "127.0.0.1";
          users.blocky = {
            databases = ["blocky"];
            ensureDBOwnership = true;
          };
          users.other = {
            databases = ["other"];
            ensureDBOwnership = true;
          };
          # As production: owns nothing, reads blocky's tables.
          users.blocky_grafana = {
            databases = [];
            readOnlyAccess.blocky = {
              owner = "blocky";
              revokePublicTemp = true;
            };
          };
          # Sorts BEFORE the others: its grant fails (no such database) and must
          # neither stop the later users nor go unnoticed.
          users.aaa_broken = {
            databases = [];
            readOnlyAccess.nosuchdb.owner = "x";
          };
        };
      };
    };

    testScript = ''
      def sql(user, password, database, query, check=True):
          cmd = (
              f"PGPASSWORD={password} psql -h 127.0.0.1 -U {user} -d {database} "
              f"-v ON_ERROR_STOP=1 -tA -c \"{query}\""
          )
          return db.succeed(cmd) if check else db.fail(cmd)

      ro = lambda q, database="blocky": sql("blocky_grafana", "${pw.ro}", database, q)
      ro_fails = lambda q, database="blocky": sql("blocky_grafana", "${pw.ro}", database, q, check=False)
      owner = lambda q: sql("blocky", "${pw.blocky}", "blocky", q)

      db.start()
      db.wait_for_unit("postgresql.service")
      db.wait_for_unit("multi-user.target")  # the init oneshot ran before it
      db.succeed("journalctl -u postgresql-password-init.service | grep -q \"read-only access to .blocky.\"")

      with subtest("grants exist before the table does; the role can connect and see nothing yet"):
          ro("select 1")
          ro_fails("select * from log_entries")  # no such table yet

      with subtest("Blocky creates its table AFTER the grants ran"):
          owner("create table log_entries (id serial primary key, question_name text)")
          owner("insert into log_entries (question_name) values ('example.net')")

      with subtest("read-only role reads the late table"):
          assert ro("select question_name from log_entries").strip() == "example.net"

      with subtest("a second table the owner creates later is readable too (default privileges)"):
          owner("create table schema_notes (x int)")
          ro("select count(*) from schema_notes")

      with subtest("DML is refused"):
          ro_fails("insert into log_entries (question_name) values ('x')")
          ro_fails("update log_entries set question_name = 'x'")
          ro_fails("delete from log_entries")
          ro_fails("truncate log_entries")

      with subtest("DDL is refused"):
          ro_fails("create table t (x int)")
          ro_fails("alter table log_entries add column y int")
          ro_fails("drop table log_entries")
          ro_fails("create index on log_entries (question_name)")
          ro_fails("create role evil login")
          # GRANT without grant option is only a warning in Postgres ("no privileges were
          # granted"), not an error, so assert on the resulting ACL instead.
          ro("grant all on log_entries to public")
          assert owner("select relacl from pg_class where relname = 'log_entries'").count("=") == 2, owner("select relacl from pg_class where relname = 'log_entries'")  # owner + blocky_grafana only

      with subtest("the data is untouched"):
          assert owner("select count(*) from log_entries").strip() == "1"

      with subtest("other databases are unreadable"):
          sql("other", "${pw.other}", "other", "create table secrets (v text)")
          sql("other", "${pw.other}", "other", "insert into secrets values ('hidden')")
          ro_fails("select * from secrets", database="other")
          ro_fails("select * from pg_shadow")

      with subtest("the role cannot even CONNECT to another database (pg_hba pin)"):
          for other_db in ["other", "postgres", "template1"]:
              out = db.fail(
                  f"PGPASSWORD=${pw.ro} psql -h 127.0.0.1 -U blocky_grafana -d {other_db} -tA -c 'select 1' 2>&1"
              )
              assert "pg_hba.conf rejects connection" in out, out
          # the pin does not lock out the other roles
          sql("other", "${pw.other}", "other", "select 1")
          # ... and the generated lines come first, before the generic ones
          hba = db.succeed("su postgres -c \"psql -tA -c \\\"select type, database, user_name, address, auth_method from pg_hba_file_rules order by line_number\\\"\"")
          lines = hba.strip().splitlines()
          pin = lines.index("host|{blocky}|{blocky_grafana}|127.0.0.1|scram-sha-256")
          generic = lines.index("host|{all}|{all}|127.0.0.1|scram-sha-256")
          assert pin < generic, hba

      with subtest("no temp tables where REVOKE TEMP applies"):
          ro_fails("create temp table t (x int)")

      with subtest("a failing grant is loud, fails the unit, and does not stop the later users"):
          db.succeed("systemctl is-failed postgresql-password-init.service")
          db.succeed("journalctl -u postgresql-password-init.service | grep -q \"read-only grant for 'aaa_broken' on 'nosuchdb' FAILED\"")
          # 'other' sorts after aaa_broken: its password was still set
          sql("other", "${pw.other}", "other", "select 1")

      with subtest("re-applying the grants (every deploy) is idempotent"):
          db.fail("systemctl restart postgresql-password-init.service")  # still fails: aaa_broken
          assert ro("select count(*) from log_entries").strip() == "1"
          ro_fails("delete from log_entries")
    '';
  }
