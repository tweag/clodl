workspace(name = "io_tweag_clodl")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_haskell",
    sha256 = "5760599f3866aaf01ac30d5ca740a6fe9aa16945c0de7ed1ee17e07d990779ef",
    strip_prefix = "rules_haskell-42b8b43623b82a6b7cfb151f01986735a135e0a9",
    urls = ["https://github.com/tweag/rules_haskell/archive/42b8b43623b82a6b7cfb151f01986735a135e0a9.tar.gz"],
)

http_archive(
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

load("@rules_haskell//haskell:repositories.bzl", "haskell_repositories")
haskell_repositories()

load(
    "@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
    "nixpkgs_git_repository",
    "nixpkgs_package",
)

nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "e7ebd6be80d80000ea9efb62c589a827ba4c22dc",
)

load("@rules_haskell//haskell:nixpkgs.bzl", "haskell_register_ghc_nixpkgs")

nixpkgs_package(
    name = "glibc_locales",
    attribute_path = "glibcLocales",
    build_file_content = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "locale-archive",
    srcs = ["lib/locale/locale-archive"],
)
""",
    repository = "@nixpkgs",
)

haskell_register_ghc_nixpkgs(
    attribute_path = "haskell.compiler.ghc8102",
    locale_archive = "@glibc_locales//:locale-archive",
    repositories = {"nixpkgs": "@nixpkgs"},
    version = "8.10.2",
    compiler_flags = [
        "-Werror",
        "-Wall",
        "-Wcompat",
        "-Wincomplete-record-updates",
        "-Wredundant-constraints",
    ],
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
)

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


http_archive(
    name = "io_bazel_stardoc",
    strip_prefix = "stardoc-0.4.0",
    urls = ["https://github.com/bazelbuild/stardoc/archive/0.4.0.tar.gz"],
)

load("@io_bazel_stardoc//:setup.bzl", "stardoc_repositories")
stardoc_repositories()
