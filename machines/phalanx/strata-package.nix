# Strata as Nix packages, replacing the imperative ~/programming/Strata checkout
# that ./setup.sh compiled and pip-installed into.
#
#   engine -- the CUDA binary `strata` plus libstrata_kq.so, built the way
#             setup.py builds it (same CMake flags), but from a pinned source.
#   server -- serve/server.py run straight out of the source in the store,
#             with a Python whose packages come from nixpkgs instead of a venv.
#
# The model data (GGUFs, the pack, the MTP draft head) stays imperative in
# ~/models/strata-data: it is ~80 GB, derived from the GGUFs by setup.py once,
# and is not something a derivation should hold.
{
  lib,
  cudaPackages_13_0,
  cmake,
  ninja,
  autoAddDriverRunpath,
  python3,
  writeShellApplication,
  src,
  llamaCpp,
}: let
  # setup.py wants CUDA 13.0: Strata's own flake pins it, and the ready-made
  # engine is built with 13.0.88 (13.2.0/13.2.1 miscompile for sm_120).
  cudaPackages = cudaPackages_13_0;

  # Strata downloads llama.cpp itself at this commit (get_llama_cpp). The flake
  # input has to match it; checked here, at evaluation, so a Strata bump that
  # moves the pin cannot quietly build against the old ggml.
  wantedLlama = let
    m = builtins.match ''.*LLAMA_CPP_COMMIT = "([0-9a-f]+)".*'' (builtins.readFile "${src}/setup.py");
  in
    if m == null
    then throw "strata: LLAMA_CPP_COMMIT not found in setup.py -- check how this version fetches llama.cpp"
    else builtins.head m;
  checkedLlama =
    if llamaCpp.rev == wantedLlama
    then llamaCpp
    else
      throw ''
        strata: this Strata version wants llama.cpp ${wantedLlama},
        but the strata-llama-cpp flake input is ${llamaCpp.rev}.
        Update its URL in flake.nix, then `nix flake update strata-llama-cpp`.'';

  # project(strata VERSION x.y.z) -- the engine's own version, which is not the
  # release tag (v0.2.11 ships engine 0.1.57).
  engineVersion = let
    m = builtins.match ''.*project\(strata VERSION ([0-9.]+).*'' (builtins.readFile "${src}/CMakeLists.txt");
  in
    if m == null
    then "0"
    else builtins.head m;

  engine = cudaPackages.backendStdenv.mkDerivation {
    pname = "strata-engine";
    version = engineVersion;
    inherit src;

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
    ];

    # setup.py's flags for a local CUDA build (build_engine), minus the paths
    # it discovers itself. STRATA_PORTABLE is the one difference: setup.py
    # compiles ggml-cpu with -march=native, which the Nix compiler wrapper
    # strips anyway; PORTABLE is upstream's own AVX2 baseline for the release
    # engine. The 5950X is Zen 3 -- AVX2/FMA/F16C/BMI2, no AVX-512 -- so the
    # baseline IS this CPU, and Strata's AVX-512 kernels are picked at run
    # time regardless.
    cmakeFlags = [
      (lib.cmakeBool "STRATA_ENABLE_CUDA" true)
      (lib.cmakeBool "STRATA_BUILD_TESTS" false)
      (lib.cmakeBool "STRATA_Q6K_EXPERTS" true)
      (lib.cmakeBool "STRATA_MMQ_KQUANTS" true)
      (lib.cmakeBool "STRATA_PORTABLE" true)
      (lib.cmakeBool "GGML_CCACHE" false)
      # nixpkgs.config.cudaCapabilities (["8.6"] in configuration.nix).
      (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cudaPackages.flags.cmakeCudaArchitecturesString)
      (lib.cmakeFeature "STRATA_GGML_DIR" "${checkedLlama}")
    ];

    # Only the engine target, as setup.py builds it; the default target pulls
    # in the benches and tools. `cmake --build`, not `ninja`: the generator is
    # the cmake hook's choice, not this file's.
    buildPhase = ''
      runHook preBuild
      cmake --build . --target strata -j$NIX_BUILD_CORES
      runHook postBuild
    '';

    # libstrata_kq.so must sit NEXT TO the real binary: the engine dlopens it
    # from the folder of /proc/self/exe (src/prefill/mmq_kq_loader.cpp). So the
    # binary is never wrapped or symlinked from bin/ -- the run config points
    # at libexec directly.
    installPhase = ''
      runHook preInstall
      install -Dm755 strata $out/libexec/strata/strata
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

  # requirements.txt + requirements-monitor.txt, from nixpkgs. The exact pins
  # there are upstream's reproducibility for pip; nixpkgs is ours.
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
    ]);
in {
  inherit engine src;

  # The server needs nothing built: it runs from the source tree, which it only
  # reads (ROOT = the parent of serve/). It writes next to its --config and in
  # the config's `cwd`/`log`, all of which the service points at a state dir.
  server = writeShellApplication {
    name = "strata-server";
    runtimeInputs = [python];
    text = ''
      # The store is read-only; without this every import tries to write a .pyc.
      export PYTHONDONTWRITEBYTECODE=1
      exec python ${src}/serve/server.py "$@"
    '';
  };
}
