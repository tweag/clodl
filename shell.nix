{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

mkShell {
  buildInputs = [
    bazel
    binutils
    cacert
    git
    less
    nix
    openjdk11
    python3
    pax-utils
    unzip
    which
    zip
  ];
}
