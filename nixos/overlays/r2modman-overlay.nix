final: prev:

let
  customVersion = "3.2.1";
in {
  r2modman = prev.r2modman.overrideAttrs (old: rec {
    version = customVersion;

    src = prev.fetchFromGitHub {
      owner = "ebkr";
      repo = "r2modmanPlus";
      rev = "v${version}";
      hash = "sha256-hZGWso7gLiylYVxt6XMv8AKMic5A0L6zselKHExApqM="; # Replace with correct hash
    };

    offlineCache = prev.fetchYarnDeps {
      yarnLock = "${src}/yarn.lock";
      hash = "sha256-HLVHxjyymi0diurVamETrfwYM2mkUrIOHhbYCrqGkeg="; # Replace with correct hash
    };

    meta = old.meta // {
      changelog = "https://github.com/ebkr/r2modmanPlus/releases/tag/v${version}";
    };
  });
}

