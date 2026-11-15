# Paths into the clan vars store (the repository's vars/ directory).
#
# The one place that knows where vars/ is relative to the modules, so a module
# can move without its `../../..` chain being recounted.
#
# These return path values, never strings. Reading one (`builtins.readFile`)
# or interpolating one (`"${vars.shared "a" "b"}"`, which copies that single
# file to the store) both work. `toString` does not: it yields the path the
# file would have inside a store copy of the whole flake, which Nix 2.35 no
# longer creates.
{
  # vars/shared/<generator>/<file>/value
  shared = generator: file: ../../vars/shared + "/${generator}/${file}/value";

  # vars/per-machine/<machine>/<generator>/<file>/value
  machine = machine: generator: file:
    ../../vars/per-machine + "/${machine}/${generator}/${file}/value";
}
