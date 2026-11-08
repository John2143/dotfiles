# deSEC DNS API client — `desec` CLI for domains, RRsets and auth tokens.
#
# Upstream (s-hamann/desec-dns) publishes to PyPI only; nixpkgs has no package
# for it. Do not confuse this with the deSEC server stack (desec-io/desec-stack).
# Wired into the overlay in shared-configuration.nix and installed by home.nix.
{
  lib,
  fetchurl,
  python3,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "desec-dns";
  version = "1.5.0";
  pyproject = true;

  # fetchPypi builds `desec-dns-1.5.0.tar.gz`; PyPI normalises the sdist name to
  # `desec_dns-1.5.0.tar.gz`, so the mirror path has to be given verbatim.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/07/8d/81428c2511ac66e1bbf713d70d5d4c2b047077139671c25a312712ebac4a/desec_dns-${version}.tar.gz";
    hash = "sha256-cBBq5Hjzms+IETD81/yI+uV7UBTpybZy7zG1EC+KD6g=";
  };

  build-system = with python3.pkgs; [poetry-core];

  # These are upstream's optional `tlsa` and `zonefiles` extras. Both earn their
  # keep: `import-zone` is the only way to create a new zone's records in one
  # request instead of running into deSEC's 15/min per-domain RRset write limit,
  # and TLSA records are how DANE is published for the mail hosts.
  dependencies = with python3.pkgs; [
    cryptography
    dnspython
    requests
  ];

  # Tests replay recorded HTTP responses through pytest-recording; there is no
  # offline suite worth carrying here.
  doCheck = false;

  pythonImportsCheck = ["desec"];

  meta = {
    description = "Simple deSEC.io API client (domain, record and token management)";
    homepage = "https://github.com/s-hamann/desec-dns";
    license = lib.licenses.mit;
    mainProgram = "desec";
  };
}
