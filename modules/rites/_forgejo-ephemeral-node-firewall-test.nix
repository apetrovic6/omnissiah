# Exercise generated Luna scripts in a veth model, not a live Kubernetes dataplane.
{
  self,
  pkgs,
  lib,
}: let
  data = import ./_ci-slots.nix {
    nodes.luna = {
      hostRunnerEnabled = false;
      slotsEnabled = true;
      trustedEgress = true;
    };
  };
  luna = self.nixosConfigurations.luna.extendModules {
    specialArgs = {
      ciSlots = data.hosts;
      # The rollout state: trust on, both SNAT addresses claimed.
      ciDispatcher = data.dispatcher // {trustedJobs = true;};
      ciNodes = data.nodes;
    };
  };
  guard = luna.config.systemd.services.forgejo-ephemeral-firewall;
  snat = luna.config.systemd.services.forgejo-ephemeral-snat;
  # Take only the script options, not ExecStart or the production system closure.
  serviceCommands = [
    (pkgs.writeShellScriptBin "guard-start" guard.script)
    (pkgs.writeShellScriptBin "guard-reload" guard.reload)
    (pkgs.writeShellScriptBin "guard-stop" guard.preStop)
    (pkgs.writeShellScriptBin "snat-start" snat.script)
    (pkgs.writeShellScriptBin "snat-stop" snat.preStop)
  ];
  socketFixture = pkgs.writeText "firewall-fixture.py" ''
    import selectors
    import socket
    import sys
    from pathlib import Path

    action, *args = sys.argv[1:]
    if action == "probe":
        address, port = args
        try:
            conn = socket.create_connection((address, int(port)), timeout=1)
        except TimeoutError:
            print("dropped")
        else:
            with conn:
                print(conn.makefile().readline().strip())
    else:
        marker, *bindings = args
        with selectors.DefaultSelector() as poll:
            for binding in bindings:
                address, port = binding.rsplit(",", 1)
                family = socket.AF_INET6 if ":" in address else socket.AF_INET
                listener = socket.socket(family, socket.SOCK_STREAM)
                listener.bind((address, int(port)))
                listener.listen()
                poll.register(listener, selectors.EVENT_READ)
            Path(marker).touch()
            while True:
                for key, _ in poll.select():
                    conn, remote = key.fileobj.accept()
                    with conn:
                        local, port, *_ = conn.getsockname()
                        conn.sendall(f"{remote[0]} -> {local},{port}\n".encode())
  '';
in
  pkgs.testers.runNixOSTest {
    name = "forgejo-ephemeral-node-firewall";

    nodes.firewall = {
      networking.firewall.enable = false;
      environment.systemPackages =
        [luna.config.networking.firewall.package pkgs.iproute2 pkgs.python3]
        ++ serviceCommands;
      environment.etc."firewall-fixture.py".source = socketFixture;
    };

    testScript = ''
      import json

      firewall.start()

      node = "${self.lib.hosts.luna}"
      guard = "${self.lib.hosts.${data.guard}}"
      snat = "${self.lib.lan.luna-eph}"
      trusted_snat = "${self.lib.lan.luna-eph-trusted}"
      cluster = "10.43.0.1"
      local_service = "10.43.0.2"
      vip = "192.168.1.251"
      pod = "10.42.1.2"
      guest = "10.99.2.2"
      gateway = "10.99.2.1"
      host6 = "fd00:1::1"
      guest6 = "fd00:1::2"
      uplink6 = "fd00:2::2"
      # These public-shaped addresses are bound only in the isolated uplink
      # namespace. No veth connects this topology to the VM's own network.
      public = "11.0.0.2"
      public_alias = "11.0.0.3"
      tap = "vm-eph-1"
      uplink = "enp1s0"
      snat_device = "dummy-ci-snat"
      ip = "${lib.getExe' pkgs.iproute2 "ip"}"
      arping = "${lib.getExe' pkgs.iputils "arping"}"
      python = "${lib.getExe pkgs.python3} /etc/firewall-fixture.py"

      def run(ns, *commands):
          return firewall.succeed(*(f"{ip} netns exec {ns} {cmd}" for cmd in commands))

      def connect(left, left_if, right, right_if):
          run(left,
              f"ip link add {left_if} type veth peer name {right_if}",
              f"ip link set {right_if} netns {right}",
          )

      def listen(ns, *bindings):
          marker = f"/run/listen-{ns}"
          addresses = " ".join(f"{address},{port}" for address, port in bindings)
          firewall.succeed(
              f"systemd-run --unit=listen-{ns} -p Type=exec "
              f"{ip} netns exec {ns} {python} listen {marker} {addresses}"
          )
          firewall.wait_until_succeeds(f"test -f {marker}")

      for ns in ("host", "slot", "lan", "pod"):
          firewall.succeed(f"ip netns add {ns}")
          run(ns, "ip link set lo up")

      connect("host", tap, "slot", "slot0")
      connect("host", uplink, "lan", "lan0")
      connect("host", "cali0", "pod", "pod0")
      run("host",
          f"ip link set {tap} address 02:00:00:00:00:01 up",
          f"ip link set {uplink} up",
          "ip link set cali0 up",
          f"ip addr add {gateway}/24 dev {tap}",
          f"ip addr add {node}/24 dev {uplink}",
          f"ip addr add 11.0.0.1/24 dev {uplink}",
          "ip addr add 10.42.1.1/24 dev cali0",
          "sysctl -w net.ipv4.ip_forward=1 net.ipv6.conf.all.forwarding=1",
          f"ip -6 addr add {host6}/64 dev {tap} nodad",
          f"ip -6 neigh add {guest6} lladdr 02:00:00:00:00:02 nud permanent dev {tap}",
          f"ip -6 addr add fd00:2::1/64 dev {uplink} nodad",
      )
      run("slot",
          "ip link set slot0 address 02:00:00:00:00:02 up",
          f"ip addr add {guest}/24 dev slot0",
          f"ip route add default via {gateway}",
          f"ip -6 addr add {guest6}/64 dev slot0 nodad",
          f"ip -6 neigh add {host6} lladdr 02:00:00:00:00:01 nud permanent dev slot0",
          f"ip -6 route add default via {host6}",
      )
      run("lan",
          "ip link set lan0 up",
          f"ip addr add {guard}/24 dev lan0",
          f"ip addr add {public}/24 dev lan0",
          f"ip route add 10.99.2.0/24 via {node}",
          f"ip -6 addr add {uplink6}/64 dev lan0 nodad",
          "ip -6 route add fd00:1::/64 via fd00:2::1",
      )
      run("pod",
          "ip link set pod0 up",
          f"ip addr add {pod}/24 dev pod0",
          "ip route add default via 10.42.1.1",
      )

      def uplink_addresses():
          return run("host", f"ip -4 -o addr show dev {uplink}")

      original_uplink_addresses = uplink_addresses()

      def check_no_snat_device():
          firewall.fail(f"{ip} -n host link show dev {snat_device}")
          assert uplink_addresses() == original_uplink_addresses

      # Approximate kube-proxy's PREROUTING DNAT. The public-shaped alias
      # DNATs to an otherwise *allowed* destination, testing the DNAT fence
      # independently of private-address or wrong-interface drops.
      run("host", "iptables -t nat -N KUBE-SERVICES",
          "iptables -t nat -A PREROUTING -j KUBE-SERVICES")
      services = ((cluster, pod), (vip, pod), (local_service, node), (public_alias, public))
      for address, backend in services:
          run("host", f"iptables -t nat -A KUBE-SERVICES -d {address} -p tcp --dport 443 "
              f"-j DNAT --to-destination {backend}")

      listen("host", (node, 2379), (node, 10250), (node, 443), (host6, 443))
      listen("slot", (guest, 443), (guest6, 443))
      listen("lan", (guard, 443), (public, 443), (public, 80), (uplink6, 443))
      listen("pod", (pod, 443))

      # Model a Calico chain returning a terminal ACCEPT, even ahead of the
      # guard's filter hooks. Insert these before start, then promote them to
      # the head after start/reload to reproduce a later rule reconciliation.
      def place_accepts(create=False):
          for cmd in ("iptables", "ip6tables"):
              for hook, direction in (("INPUT", "-i"), ("OUTPUT", "-o"),
                                      ("FORWARD", "-i"), ("FORWARD", "-o")):
                  chain = f"cali-{hook}-{direction[-1]}"
                  rule = f"{hook} {direction} {tap} -j {chain}"
                  if create:
                      run("host", f"{cmd} -N {chain}", f"{cmd} -A {chain} -j ACCEPT")
                  else:
                      run("host", f"{cmd} -D {rule}")
                  run("host", f"{cmd} -I {rule}")

      def probe(ns, address, port, expected):
          got = run(ns, f"{python} probe {address} {port}").strip()
          assert got == expected, f"{ns} -> {address},{port}: expected {expected!r}, got {got!r}"

      # ns, target, port, observed source and listener address absent the guard.
      denied = [
          ("slot", cluster, 443, guest, pod),  # PREROUTING DNAT -> FORWARD
          ("slot", vip, 443, guest, pod),
          ("slot", local_service, 443, guest, node),  # PREROUTING DNAT -> INPUT
          ("slot", pod, 443, guest, pod),
          ("slot", node, 2379, guest, node),  # INPUT (etcd, kubelet)
          ("slot", node, 10250, guest, node),
          ("host", guest, 443, gateway, guest),  # OUTPUT to tap
          ("lan", guest, 443, guard, guest),  # unsolicited FORWARD to tap
          ("slot", public_alias, 443, guest, public),
          ("slot", public, 80, guest, public),
          ("slot", host6, 443, guest6, host6),
          ("host", guest6, 443, host6, guest6),
          ("slot", uplink6, 443, guest6, uplink6),
          ("lan", guest6, 443, uplink6, guest6),
      ]

      def check_egress(source):
          # Both HTTPS controls must complete the handshake and receive a reply.
          for target in (guard, public):
              probe("slot", target, 443, f"{source} -> {target},443")

      def exercise(active):
          for ns, target, port, source, listener in denied:
              expected = "dropped" if active else f"{source} -> {listener},{port}"
              probe(ns, target, port, expected)
          check_egress(snat if active else guest)

      place_accepts(create=True)
      with subtest("Without the guard, listeners and translated paths work"):
          exercise(active=False)
      with subtest("LAN duplicate prevents SNAT address setup"):
          run("lan", f"ip addr add {snat}/32 dev lan0")
          try:
              status, output = firewall.execute(f"{ip} netns exec host snat-start 2>&1")
              assert status != 0 and f"duplicate-address probe for {snat} on {uplink} failed" in output, output
              check_no_snat_device()
          finally:
              run("lan", f"ip addr del {snat}/32 dev lan0")
      with subtest("SNAT setup binds both /32s to the dummy and answers ARP on enp1s0"):
          run("host", "snat-start")
          assert uplink_addresses() == original_uplink_addresses
          (device,) = json.loads(run("host", f"ip -d -j -4 addr show dev {snat_device}"))
          assert device["linkinfo"]["info_kind"] == "dummy"
          assert {(addr["local"], addr["prefixlen"]) for addr in device["addr_info"]} == {
              (snat, 32), (trusted_snat, 32),
          }
          run("lan", f"{arping} -c 1 -w 3 -I lan0 -s {guard} {snat}")
      with subtest("Start isolates the slot even after competing filter verdicts move ahead"):
          run("host", "guard-start")
          check_egress(snat)
          place_accepts()
          exercise(active=True)
      with subtest("Reload keeps isolation and permits SNATed connections"):
          run("host", "guard-reload")
          place_accepts()
          exercise(active=True)
      with subtest("Stop removes the guard without touching kube-proxy or Calico rules"):
          run("host", "guard-stop")
          exercise(active=False)
      with subtest("Stopping SNAT removes its dummy without changing enp1s0"):
          run("host", "snat-stop")
          check_no_snat_device()
    '';
  }
