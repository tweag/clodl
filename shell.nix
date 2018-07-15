{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

mkShell {
  buildInputs = [
    bazel
    binutils
    nix
    pax-utils
    python
    unzip
    which
    zip
  ];
}
