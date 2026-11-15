# Everything in this directory that is plain data, for code that is not a
# module of this flake (the OpenTofu configuration, the clan inventory).
(import ./_chart.nix)
// {
  noosphere = import ./_noosphere-values.nix;
  vars = import ./_vars.nix;
}
