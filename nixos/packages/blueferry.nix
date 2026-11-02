# BlueFerry — iPhone messages, contacts and notifications over Bluetooth.
#
# Upstream only ships Arch/DEB/RPM recipes, so this follows packaging/arch/PKGBUILD
# and rewrites the FHS paths the Python code hardcodes (/usr/bin/btmgmt,
# /usr/share/blueferry/..., the set-cod helper) to store paths.
{
  lib,
  python3,
  fetchFromGitHub,
  bluez,
  dbus,
  gtk4,
  libadwaita,
  libsecret,
  systemd,
  wireplumber,
  gobject-introspection,
  wrapGAppsHook4,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "blueferry";
  version = "0.9.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "erikwb";
    repo = "blueferry";
    tag = "v${version}";
    hash = "sha256-Z+PgZVAu2LyTQB4OefocJlFUieuvtal7T0+hPsCUkKQ=";
  };

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies = with python3.pkgs; [
    cryptography
    dbus-python
    phonenumbers
    pygobject3
    regex
    textual
    typer
  ];

  nativeBuildInputs = [
    gobject-introspection
    wrapGAppsHook4
  ];

  buildInputs = [
    bluez
    dbus
    gtk4
    libadwaita
    libsecret
  ];

  # Upstream's suite needs a live BlueZ daemon, a private D-Bus session and the
  # FHS layout it asserts on; none of that exists in the build sandbox.
  doCheck = false;

  postPatch = ''
    substituteInPlace src/blueferry/backend_lifecycle.py \
      --replace-fail 'Path("/usr/share/blueferry/package-release")' \
        "Path(\"$out/share/blueferry/package-release\")"

    substituteInPlace src/blueferry/build_info.py \
      --replace-fail 'Path("/usr/share/blueferry/build-sha")' \
        "Path(\"$out/share/blueferry/build-sha\")"

    substituteInPlace src/blueferry/bluetooth_capabilities.py \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"' \
      --replace-fail '"/usr/lib/bluetooth/bluetoothd",' \
        '"${bluez}/libexec/bluetooth/bluetoothd",'

    substituteInPlace src/blueferry/bluez_setup.py \
      --replace-fail '"/usr/bin/btmgmt"' '"${bluez}/bin/btmgmt"' \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"' \
      --replace-fail '"/usr/lib/blueferry/blueferry-set-cod"' \
        "\"$out/lib/blueferry/blueferry-set-cod\""

    substituteInPlace src/blueferry/service_manager.py \
      --replace-fail '"/usr/bin/systemctl"' '"${systemd}/bin/systemctl"'

    substituteInPlace src/blueferry/wireplumber_policy.py \
      --replace-fail '"/usr/bin/wireplumber"' '"${wireplumber}/bin/wireplumber"'

    substituteInPlace systemd/blueferry.service \
      --replace-fail 'ExecStart=/usr/bin/blueferry run' "ExecStart=$out/bin/blueferry run"

    substituteInPlace systemd/blueferry-set-cod \
      --replace-fail '/usr/bin/btmgmt' '${bluez}/bin/btmgmt'

    substituteInPlace systemd/blueferry-btmgmt-set-class@.service \
      --replace-fail 'ExecStart=/usr/lib/blueferry/blueferry-set-cod' \
        "ExecStart=$out/lib/blueferry/blueferry-set-cod"
  '';

  postInstall = ''
    install -Dm644 systemd/blueferry.service $out/etc/systemd/user/blueferry.service
    install -Dm644 systemd/blueferry-btmgmt-set-class@.service \
      $out/lib/systemd/system/blueferry-btmgmt-set-class@.service
    install -Dm755 systemd/blueferry-set-cod $out/lib/blueferry/blueferry-set-cod
    install -Dm644 systemd/49-blueferry-cod.rules \
      $out/share/polkit-1/rules.d/49-blueferry-cod.rules

    install -Dm644 data/io.weirdware.BlueFerry.xml \
      $out/share/dbus-1/interfaces/io.weirdware.BlueFerry.xml
    install -Dm644 data/icons/io.weirdware.BlueFerry.svg \
      $out/share/icons/hicolor/scalable/apps/io.weirdware.BlueFerry.svg
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.desktop \
      $out/share/applications/io.weirdware.BlueFerry.Gtk.desktop
    install -Dm644 data/io.weirdware.BlueFerry.Gtk.metainfo.xml \
      $out/share/metainfo/io.weirdware.BlueFerry.Gtk.metainfo.xml

    # The Qt/Kirigami client needs PySide6, which is not a dependency here.
    rm -f $out/bin/blueferry-qt $out/bin/blueferry-tray
    rm -rf $out/${python3.sitePackages}/blueferry/qt

    # Release marker: clients restart a daemon left over from an older build.
    install -d $out/share/blueferry
    printf '%s\n' '${version}' > $out/share/blueferry/package-release
    printf '%s\n' 'c56ec96084fc0ffde318443fe5c1c5af83c6a0d1' \
      > $out/share/blueferry/build-sha
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [bluez dbus systemd]}
      --prefix PATH : ${placeholder "out"}/bin
    )
  '';

  meta = {
    description = "Bring iPhone messages, contacts and notifications to Linux over Bluetooth";
    homepage = "https://github.com/erikwb/blueferry";
    changelog = "https://github.com/erikwb/blueferry/blob/v${version}/CHANGELOG.md";
    license = lib.licenses.gpl2Plus;
    mainProgram = "blueferry";
    platforms = lib.platforms.linux;
  };
}
