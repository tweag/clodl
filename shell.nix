{ pkgs ? import <nixpkgs> {}, ghc }:

with pkgs;

let
  openjdk = openjdk8;
in
haskell.lib.buildStackProject {
  name = "jarify";
  buildInputs = [ gradle openjdk which ];
  inherit ghc;
  LANG = "en_US.utf8";
}
