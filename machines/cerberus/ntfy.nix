# ntfy — the homelab's push-notification relay, and the far end of Alertmanager.
#
# Alertmanager (observability, in-cluster) publishes every critical/warning alert
# here; the phone subscribes to `homelab-alerts`. ntfy lives on cerberus rather than
# in the cluster on purpose: the thing that notifies you when the cluster is down
# must not be inside the cluster.
#
# Addressing, and why the cluster can reach it but the public internet cannot:
#   https://ntfy.{$LAB_DOMAIN} (ugalabugala.org) -> Caddy on this host -> :102.
#   Technitium on this host is primary for the zone, so a pod in the cluster asks
#   CoreDNS, CoreDNS forwards to its resolv.conf (192.168.1.105, see
#   nixidy/_env/prod.nix `coredns-config`), and gets 192.168.1.105. A public
#   resolver answers 152.53.34.16 (the VPS in front of Pangolin) for the same name.
#   Both are "correct"; only the LAN answer reaches ntfy, which is why the cluster
#   side pins the zone to 192.168.1.105 in CoreDNS rather than trusting the node's
#   resolver. Verified: dig through 192.168.1.105 answers ntfy.ugalabugala.org ->
#   192.168.1.105 (the zone is wildcarded), @1.1.1.1 answers 152.53.34.16.
#
# Access control: everything below the ACL level of `deny-all`, with accounts minted
# by the shared `ntfy-access` clan var
# (modules/noosphere/taghmata/rke2/kube-secrets/ntfy/default.nix). The var's env file
# is loaded via EnvironmentFile, which systemd parses as root before the service
# drops to its dynamic user, so the credentials stay in the sops secret store and
# never enter the nix store or a manifest.
{
  self,
  config,
  ...
}: let
  access = config.clan.core.vars.generators."ntfy-access";
in {
  imports = [self.nixosModules.vox];

  services.imperium.ntfy-sh = {
    enable = true;

    # The vox module renders https://ntfy.<domain> from this subdomain
    # (base-url + a Caddy virtual host on {$LAB_DOMAIN}), and points ntfy at
    # :<port>. openFirewall stays false: only Caddy (local) talks to ntfy.
    subdomain = "ntfy";
    port = 102;
  };

  services.ntfy-sh = {
    settings = {
      # A fresh ntfy server is open: any visitor may read and write any topic.
      # `ntfy.ugalabugala.org` resolves publicly to the VPS, so even if Pangolin
      # never tunnels to this host, the name is reachable from outside and the
      # topic name must not be the only thing protecting it. With deny-all nothing
      # is readable or writable unless a user/ACL says so, so the accounts below
      # are the whole access list.
      auth-default-access = "deny-all";

      # No self-service accounts: accounts exist exactly as the var declares them.
      enable-signup = false;
      enable-login = true;

      # Caddy terminates TLS in front of ntfy. Without behind-proxy every visitor on
      # the LAN shares one rate-limit bucket (ntfy defaults: 60 requests burst per
      # visitor), so Alertmanager + a phone + UnifiedPush apps on this host would
      # throttle each other, and any abusive LAN client would be indistinguishable
      # from Alertmanager. With it, ntfy trusts X-Forwarded-For, which Caddy sets.
      behind-proxy = true;

      # Cached messages are what a phone that was offline (tunnel down, plane mode)
      # catches up from. ntfy's default is 12h; a day survives a night plus a
      # working day without holding meaningful disk.
      cache-duration = "24h";

      # The web app requires a login, so an unauthenticated visitor on the public
      # name sees a sign-in form instead of a topic browser.
      require-login = true;
    };

    # NTFY_AUTH_USERS / NTFY_AUTH_ACCESS / NTFY_AUTH_TOKENS, one line each.
    #
    # `settings` is not usable for this: services.ntfy-sh renders it with
    # pkgs.formats.yaml into a derivation, and every derivation in the store is
    # world-readable, which would publish the token and both password hashes to
    # every account on this host (and to anyone who can read the store path of a
    # build result). ntfy reads its configuration from the environment as well as
    # from server.yml, and the nixpkgs module's `environmentFile` documents exactly
    # this use: "pass secrets such as creating declarative users or token without
    # putting them in the Nix store".
    #
    # Read-only here: `settings` above holds non-secret switches only.
    environmentFile = access.files."ntfy.env".path;
  };

  # The accounts and ACLs come from the var, so `settings` above never carries a
  # credential: homelab-alerts is write-only for `alertmanager` (token) and
  # read-only for `apetrovic` (password + read token), everything else denied.
  # Verified against a throwaway server built exactly this way: anonymous publish
  # 403, token publish 200, token *read* 403 (write-only cannot read), reader
  # publish 403 (read-only cannot write), wrong password 401.
  #
  # Phone credentials, in one place:
  #   sudo cat /run/secrets/vars/shared/ntfy-access/ntfy.env
  # (the real path of access.files."ntfy.env".path; NTFY_AUTH_* lines carry the
  # password hashes and both tokens -- the reader line is the one for the phone).
  # The app connects to https://ntfy.ugalabugala.org, logs in / uses the read token,
  # and subscribes to homelab-alerts.
  #
  # Push reachability is worth being clear about: `upstream-base-url = ntfy.sh` comes
  # from the vox module, which is what lets iOS wake up through UnifiedPush -- but
  # UnifiedPush only *wakes* the phone; the app then fetches the message from this
  # server. So the phone must be able to reach ntfy.ugalabugala.org, and from outside
  # the lab that means through Pangolin. No new connector resource is needed for it:
  # the existing `ugala-bugala` host route already carries alias *.ugalabugala.org
  # with tcp/443 to 192.168.1.105 (see the note next to the newt blueprint in
  # ./configuration.nix). What the phone needs is site access -- a newt client on the
  # phone, or a Pangolin Endpoint/Perimeter resource pointing at 192.168.1.105 -- and
  # olm answering the name locally. Do NOT add a second host resource for
  # 192.168.1.105: newt keeps one route per destination IP and the last written port
  # list wins, which is what blackholed 53/80/22/2222 on 2026-08-29.
}
