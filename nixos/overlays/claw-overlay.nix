final: prev: {
  claw = prev.rustPlatform.buildRustPackage {
    pname = "claw";
    version = "0-unstable-2026-05-06";

    src = prev.fetchFromGitHub {
      owner = "ultraworkers";
      repo = "claw-code";
      rev = "ab44985916cb0d53d2f7a55ea90e0d7be97d4626";
      hash = "sha256-4iZJuKVAXeGc/tSjwPagaluShsT34dHLZcWIr13qtdA=";
    };

    sourceRoot = "source/rust";
    cargoHash = "sha256-bZKghBTbKrhm2Jiyg2su1c9Jlx2HVrMQjOTK6cgEc00=";

    doCheck = false;

    meta = {
      description = "Claw CLI — open-source Rust agent harness (claude CLI clone)";
      homepage = "https://github.com/ultraworkers/claw-code";
      license = prev.lib.licenses.mit;
      mainProgram = "claw";
    };
  };
}
