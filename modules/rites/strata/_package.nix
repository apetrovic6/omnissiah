# Strata as Nix packages, replacing the imperative ~/programming/Strata checkout
# that ./setup.sh compiled and pip-installed into.
#
#   engine -- the CUDA binary `strata`, built the way terminal/setup.py builds
#             it (same CMake flags), but from a pinned source.
#   server -- terminal/serve/server.py run straight out of the source in the
#             store, with a Python whose packages come from nixpkgs instead of
#             a venv.
#
# Source layout is the 0.2.16+ one: engine/ (CMake project), terminal/ (setup,
# server, tools, data), app/ and docs/. Releases before 0.2.16 kept all of it at
# the top level and built against an external llama.cpp; this file no longer
# handles them.
#
# Model data (GGUFs, prepared packs and MTP heads) stays outside the Nix store.
{
  lib,
  cudaPackages_13_0,
  cmake,
  ninja,
  autoAddDriverRunpath,
  python3,
  writeShellApplication,
  zstd,
  src,
}: let
  # setup.py wants CUDA 13.0 (MIN_DRIVER 580, and the ready-made engine is
  # built with 13.0; 13.2.0/13.2.1 miscompile K-quant MMQ for sm_120).
  cudaPackages = cudaPackages_13_0;

  # project(strata VERSION x.y.z) -- the engine's own version, which is not the
  # release tag (v0.2.22 ships engine 0.1.69).
  engineVersion = let
    m = builtins.match ''.*project\(strata VERSION ([0-9.]+).*'' (builtins.readFile "${src}/engine/CMakeLists.txt");
  in
    if m == null
    then throw "strata: no project(strata VERSION ...) in engine/CMakeLists.txt -- has the source layout moved again?"
    else builtins.head m;

  engine = cudaPackages.backendStdenv.mkDerivation {
    pname = "strata-engine";
    version = engineVersion;
    inherit src;
    # The whole tree, not just engine/: a few CMake rules reach into
    # ../terminal (HIP tuners, test fixtures). None of them are built here, but
    # configure must not fail on a missing path.
    sourceRoot = "source/engine";

    nativeBuildInputs = [
      cmake
      ninja
      cudaPackages.cuda_nvcc
      # libcuda.so.1 is the DRIVER, found only in /run/opengl-driver/lib on
      # NixOS; this puts that directory in the binary's RUNPATH.
      autoAddDriverRunpath
    ];

    buildInputs = with cudaPackages; [
      cuda_cudart
      cuda_cccl
      libcublas
      # strata-hy4 reads zstd-compressed .strata manifests; without a system
      # zstd it falls back to a bundled decoder.
      zstd
    ];

    # setup.py's flags for a local CUDA build (build_engine), minus the paths
    # it discovers itself. STRATA_PORTABLE is the one difference: setup.py
    # compiles ggml-cpu with -march=native, which the Nix compiler wrapper
    # strips anyway; PORTABLE uses the AVX2 baseline and selects newer CPU
    # kernels at run time on both workstations.
    #
    # Gone since v0.2.11: STRATA_MMQ_KQUANTS (the K-quant kernels are part of
    # the engine now, and libstrata_kq.so is no longer built) and
    # STRATA_GGML_DIR (ggml is vendored; the variable survives only as an
    # override "kept for two releases").
    cmakeFlags = [
      (lib.cmakeBool "STRATA_ENABLE_CUDA" true)
      (lib.cmakeBool "STRATA_BUILD_TESTS" false)
      (lib.cmakeBool "STRATA_Q6K_EXPERTS" true)
      (lib.cmakeBool "STRATA_PORTABLE" true)
      # The shape engines (0.2.18+): strata-inkling (Inkling 2 Mini) defaults
      # ON, strata-hy4 (Tencent Hy4-Flash) is opt-in.
      (lib.cmakeBool "STRATA_BUILD_INKLING" true)
      (lib.cmakeBool "STRATA_BUILD_HY4" true)
      # The vendored ggml wraps every compile in ccache/sccache when one is on
      # PATH (setup.py passes this too).
      (lib.cmakeBool "GGML_CCACHE" false)
      # Each host supplies nixpkgs.config.cudaCapabilities.
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
    ];

    # Only the engine targets, as setup.py builds them (setup.py builds the
    # shape engines in a separate tree; one tree is fine here). The default
    # target pulls in the benches and tools. `cmake --build`, not `ninja`: the generator is
    # the cmake hook's choice, not this file's.
    buildPhase = ''
      runHook preBuild
      cmake --build . --target strata strata-inkling strata-hy4 -j$NIX_BUILD_CORES
      runHook postBuild
    '';

    # Kept in libexec rather than bin/: older engines dlopened libstrata_kq.so
    # from the folder of /proc/self/exe, so the binary was never wrapped or
    # symlinked. The lib is gone since 0.2.16 but the copy stays conditional in
    # case a build option brings it back.
    installPhase = ''
      runHook preInstall
      install -Dm755 strata $out/libexec/strata/strata
      install -Dm755 src/inkling2/strata-inkling $out/libexec/strata/strata-inkling
      install -Dm755 strata-hy4 $out/libexec/strata/strata-hy4
      if [ -e libstrata_kq.so ]; then
        install -Dm755 libstrata_kq.so $out/libexec/strata/libstrata_kq.so
      fi
      runHook postInstall
    '';

    meta = {
      description = "Strata inference engine (CUDA)";
      homepage = "https://github.com/Niko1221/Strata";
      license = lib.licenses.asl20;
      platforms = ["x86_64-linux"];
      mainProgram = "strata";
    };
  };

  # terminal/requirements.txt + requirements-monitor.txt, from nixpkgs. The
  # exact pins there are upstream's reproducibility for pip; nixpkgs is ours.
  # jsonschema (+ referencing) is an optional import of serve/structured.py,
  # used to validate structured-output schemas; without it that path degrades.
  python = python3.withPackages (ps:
    with ps; [
      numpy
      jinja2
      regex
      pyyaml
      tqdm
      requests
      pillow
      psutil
      truststore
      textual
      jsonschema
      referencing
    ]);
in {
  inherit engine src;

  # The server needs nothing built: it runs from the source tree, which it only
  # reads (ROOT = terminal/, the parent of serve/). It writes next to its
  # --config and in the config's `cwd`/`log`, all of which the service points
  # at a state dir.
  server = writeShellApplication {
    name = "strata-server";
    runtimeInputs = [python];
    text = ''
      # The store is read-only; without this every import tries to write a .pyc.
      export PYTHONDONTWRITEBYTECODE=1
      exec python ${src}/terminal/serve/server.py "$@"
    '';
  };
}
