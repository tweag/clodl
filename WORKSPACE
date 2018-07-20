workspace(name = "io_tweag_clodl")

http_archive(
    name = "io_tweag_rules_haskell",
    strip_prefix = "rules_haskell-5c94b23107809026d7e6de25a891bd3874dbc522",
    urls = ["https://github.com/tweag/rules_haskell/archive/5c94b23107809026d7e6de25a891bd3874dbc522.tar.gz"],
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
    build_file_content = """
cc_binary(
    name = "patchelf",
    srcs = ["src/patchelf.cc", "src/elf.h"],
    copts = ["-DPAGESIZE=4096", '-DPACKAGE_STRING=\\\\"patchelf\\\\"'],
    visibility = [ "//visibility:public" ],
)
""",
    strip_prefix = "patchelf-1fa4d36fead44333528cbee4b5c04c207ce77ca4",
    urls = ["https://github.com/NixOS/patchelf/archive/1fa4d36fead44333528cbee4b5c04c207ce77ca4.tar.gz"],
)

load(
    "@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
    "nixpkgs_git_repository",
    "nixpkgs_package",
)

nixpkgs_git_repository(
    name = "nixpkgs",
    # Nixpkgs from 2018-07-19
    revision = "80d44926bf7099f2bc77ca5e9288c0c0ca35e99d",
)

nixpkgs_package(
    name = "ghc",
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
""",
    nix_file_content = """
let pkgs = import <nixpkgs> {{}};
in pkgs.haskell.packages.ghc822.ghcWithPackages (p: with p; [{0}])
""".format("base"),
    repository = "@nixpkgs",
)

register_toolchains("//:ghc")

nixpkgs_package(
    name = "openjdk",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

cc_library(
    name = "include",
    hdrs = glob(["include/*.h"]),
    strip_include_prefix = "include",
)
""",
    repository = "@nixpkgs",
)

# For Skydoc

http_archive(
    name = "io_bazel_rules_sass",
    strip_prefix = "rules_sass-0.0.3",
    urls = ["https://github.com/bazelbuild/rules_sass/archive/0.0.3.tar.gz"],
)
load("@io_bazel_rules_sass//sass:sass.bzl", "sass_repositories")
sass_repositories()

http_archive(
    name = "io_bazel_skydoc",
    strip_prefix = "skydoc-f531844d137c7accc44d841c08a2a2a366688571",
    urls = ["https://github.com/bazelbuild/skydoc/archive/f531844d137c7accc44d841c08a2a2a366688571.tar.gz"],
)
load("@io_bazel_skydoc//skylark:skylark.bzl", "skydoc_repositories")
skydoc_repositories()
