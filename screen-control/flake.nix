{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        rustPlatform = pkgs.rustPlatform;

        pkg = rustPlatform.buildRustPackage {
          pname = "screen-control";
          version = "0.1.0";
          src = ./.;
          # Vendors every crate from Cargo.lock (fetched once, from
          # static.crates.io, as a fixed-output derivation) and builds
          # offline inside the sandbox.
          cargoLock.lockFile = ./Cargo.lock;
        };
      in {
        packages.default = pkg;
        # Legacy alias consumed by ../flake.nix (arch-configuration.nix)
        defaultPackage = pkg;

        devShell = with pkgs;
          mkShell {
            buildInputs = [
              cargo
              rustc
              rustfmt
              pre-commit
              rustPackages.clippy
              rust-analyzer
            ];
            RUST_SRC_PATH = rustPlatform.rustLibSrc;
          };
      }
    );
}
