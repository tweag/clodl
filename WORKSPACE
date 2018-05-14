workspace(name = "io_tweag_clodl")

http_archive(
  name = "io_tweag_rules_haskell",
  strip_prefix = "rules_haskell-413a76b6ec8a116225e395425248ba8c9cd5fec1",
  urls = ["https://github.com/tweag/rules_haskell/archive/413a76b6ec8a116225e395425248ba8c9cd5fec1.tar.gz"],
)

load("@io_tweag_rules_haskell//haskell:repositories.bzl", "haskell_repositories")
haskell_repositories()

http_archive(
  name = "io_tweag_rules_nixpkgs",
  strip_prefix = "rules_nixpkgs-0.2.1",
  urls = ["https://github.com/tweag/rules_nixpkgs/archive/v0.2.1.tar.gz"],
)

new_http_archive(
  name = "org_nixos_patchelf",
  strip_prefix = "patchelf-1fa4d36fead44333528cbee4b5c04c207ce77ca4",
  urls = ["https://github.com/NixOS/patchelf/archive/1fa4d36fead44333528cbee4b5c04c207ce77ca4.tar.gz"],
  build_file_content = """
cc_binary(
  name = "patchelf",
  srcs = ["src/patchelf.cc", "src/elf.h"],
  copts = ["-DPAGESIZE=4096", '-DPACKAGE_STRING=\\\\"patchelf\\\\"'],
  visibility = [ "//visibility:public" ],
)
"""
)

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
  "nixpkgs_git_repository",
  "nixpkgs_package",
)

nixpkgs_git_repository(
  name = "nixpkgs",
  # Nixpkgs from 2018-02-23
  revision = "1c3b6d509d06af14b1858ffa2d27f3c902f549bd",
)

prebuilt_packages = [
  "base",
  "bytestring",
  "directory",
  "filepath",
  "process",
  "regex-tdfa",
  "temporary",
  "text",
  "unix",
  "zip-archive",
]

nixpkgs_package(
  name = "ghc",
  repository = "@nixpkgs",
  nix_file_content = """
let pkgs = import <nixpkgs> {{}};
in pkgs.haskell.packages.ghc822.ghcWithPackages (p: with p; [{0}])
""".format(" ".join(prebuilt_packages)),
  build_file_content = """
package(default_visibility = [ "//visibility:public" ])

filegroup(
  name = "bin",
  srcs = glob(["bin/*"]),
)

cc_library(
  name = "include",
  hdrs = glob(["lib/ghc-*/include/**/*.h"]),
  strip_include_prefix = glob(["lib/ghc-*/include"], exclude_directories=0)[0],
)
"""
)

nixpkgs_package(
  name = "gcc",
  repository = "@nixpkgs",
)

register_toolchains("//:ghc")

nixpkgs_package(
  name = "openjdk",
  repository = "@nixpkgs",
  build_file_content = """
package(default_visibility = ["//visibility:public"])

cc_library(
  name = "include",
  hdrs = glob(["include/*.h"]),
  strip_include_prefix = "include",
)
"""
)
