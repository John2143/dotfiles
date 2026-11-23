# Discord Rich Presence bridge for Wine/Proton games (enderice2/rpc-bridge).
#
# Proton games look for Discord at the Windows named pipe
# \\.\pipe\discord-ipc-0, but the native Discord client listens on the Linux
# socket $XDG_RUNTIME_DIR/discord-ipc-0, and Wine does not join the two.
# bridge.exe runs inside the game's prefix and copies bytes between them.
# Not in nixpkgs. Installed on arch from arch-configuration.nix.
#
# Use per game, in Steam → Properties → Launch Options:
#   /run/current-system/sw/bin/rpc-bridge-steam %command%
# Start Discord before the game: the bridge exits if no socket is there when
# the game connects, and nothing restarts it until the next launch.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  makeWrapper,
  coreutils,
  findutils,
}:
stdenvNoCC.mkDerivation rec {
  pname = "rpc-bridge";
  version = "1.4.1.4";

  # The release zip holds the prebuilt bridge.exe, bridge.sh and launchd.sh
  # (macOS) at its root. Hash is GitHub's published asset digest.
  src = fetchurl {
    url = "https://github.com/enderice2/rpc-bridge/releases/download/v${version}/bridge.zip";
    hash = "sha256-sxTQvtnPBgfUEQ7tL46ai0JH2wGbckOZnc+wvLVHN74=";
  };
  sourceRoot = ".";

  nativeBuildInputs = [unzip makeWrapper];

  # bridge.sh finds bridge.exe next to itself and hands that path to Proton
  # (PROTON_REMOTE_DEBUG_CMD) and to pressure-vessel's bind list. Pin it to the
  # store path so the container is given the real file, not a symlink to it.
  installPhase = ''
    runHook preInstall
    install -Dm644 bridge.exe $out/share/rpc-bridge/bridge.exe
    install -Dm755 bridge.sh $out/share/rpc-bridge/bridge.sh
    substituteInPlace $out/share/rpc-bridge/bridge.sh \
      --replace-fail 'BRIDGE_PATH="$(dirname "$0")/bridge.exe"' \
                     'BRIDGE_PATH="${placeholder "out"}/share/rpc-bridge/bridge.exe"'
    makeWrapper $out/share/rpc-bridge/bridge.sh $out/bin/rpc-bridge-steam \
      --prefix PATH : ${lib.makeBinPath [coreutils findutils]}
    runHook postInstall
  '';

  meta = {
    description = "Discord Rich Presence for Wine/Proton applications via the native Linux client";
    homepage = "https://github.com/enderice2/rpc-bridge";
    license = lib.licenses.mit;
    platforms = ["x86_64-linux"];
    mainProgram = "rpc-bridge-steam";
  };
}
