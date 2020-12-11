workspace(name = "io_tweag_clodl")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "rules_haskell",
    sha256 = "110073731641ab509780b609bbba144c249a2c2f1a10e469eec47e1ceacf4bad",
    strip_prefix = "rules_haskell-6604b8c19701a64986e98d475959ff2a2e8a1379",
    urls = ["https://github.com/tweag/rules_haskell/archive/6604b8c19701a64986e98d475959ff2a2e8a1379.tar.gz"],
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

##################################################################
#  buildifier setup
##################################################################

# buildifier is written in Go and hence needs rules_go to be built.
# See https://github.com/bazelbuild/rules_go for the up to date setup instructions.
http_archive(
    name = "io_bazel_rules_go",
    sha256 = "d1ffd055969c8f8d431e2d439813e42326961d0942bdf734d2c95dc30c369566",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/rules_go/releases/download/v0.24.5/rules_go-v0.24.5.tar.gz",
        "https://github.com/bazelbuild/rules_go/releases/download/v0.24.5/rules_go-v0.24.5.tar.gz",
    ],
)

load("@io_bazel_rules_go//go:deps.bzl", "go_register_toolchains", "go_rules_dependencies")

go_rules_dependencies()

go_register_toolchains()

http_archive(
    name = "bazel_gazelle",
    sha256 = "b85f48fa105c4403326e9525ad2b2cc437babaa6e15a3fc0b1dbab0ab064bc7c",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-gazelle/releases/download/v0.22.2/bazel-gazelle-v0.22.2.tar.gz",
        "https://github.com/bazelbuild/bazel-gazelle/releases/download/v0.22.2/bazel-gazelle-v0.22.2.tar.gz",
    ],
)

load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")

gazelle_dependencies()

http_archive(
    name = "com_google_protobuf",
    strip_prefix = "protobuf-master",
    urls = ["https://github.com/protocolbuffers/protobuf/archive/master.zip"],
)

load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")

protobuf_deps()

http_archive(
    name = "com_github_bazelbuild_buildtools",
    strip_prefix = "buildtools-master",
    url = "https://github.com/bazelbuild/buildtools/archive/master.zip",
)
