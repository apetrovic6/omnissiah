{lib, ...}: {
  repo = "oci://ghcr.io/fallenbagel/jellyseerr/jellyseerr-chart";
  chart = "jellyseer-chart";
  version = "3.0.0";
  chartHash = lib.fakeHash;
}
