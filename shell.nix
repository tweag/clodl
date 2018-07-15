{ pkgs ? import ./nixpkgs.nix {} }:

with pkgs;

mkShell {
  buildInputs = [
    bash
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
