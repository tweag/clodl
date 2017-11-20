{ pkgs ?  import ./nixpkgs.nix {}
, ghc ? pkgs.haskell.compiler.ghc802 }:

with pkgs;

let
  openjdk = openjdk8;
in
haskell.lib.buildStackProject {
  name = "jarify";
  buildInputs = [ autoconf automake git gradle openjdk which zlib ];
  inherit ghc;
  LANG = "en_US.utf8";
}
