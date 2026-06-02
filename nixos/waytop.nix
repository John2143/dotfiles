{ lib, stdenv, wayland, libglvnd, mpv, pkg-config, src }:

stdenv.mkDerivation rec {
  pname = "waytop";
  version = "unstable-2026-06-02";
  inherit src;

  nativeBuildInputs = [ pkg-config wayland ];

  buildInputs = [
    wayland
    libglvnd
    mpv
  ];

  enableParallelBuilding = true;

  installPhase = ''
    mkdir -p $out/bin
    cp waytop overlay-ctl $out/bin/
    chmod +x $out/bin/overlay-ctl
  '';

  meta = with lib; {
    description = "Click-through video overlay for Wayland compositors";
    homepage = "https://github.com/vevota/waytop";
    license = licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
