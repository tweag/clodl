load("@rules_java//java:defs.bzl", "java_binary", "java_library")
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")
load(
    "@rules_haskell//haskell:defs.bzl",
    "haskell_binary",
    "haskell_library",
    "haskell_toolchain_library",
)
load(
    "@io_tweag_clodl//clodl:clodl.bzl",
    "binary_closure",
    "library_closure",
)
load("@com_github_bazelbuild_buildtools//buildifier:def.bzl", "buildifier")

package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "libbootstrap.so",
    srcs = ["src/main/cc/bootstrap.c"],
    copts = ["-std=c99"],
    linkshared = 1,
    deps = [
        "@openjdk//:include",
        "@rules_haskell_ghc_nixpkgs//:include",
    ],
)

cc_binary(
    name = "loader",
    srcs = ["src/main/cc/loader.cc"],
    linkopts = ["-ldl"],
)

java_library(
    name = "base-jar",
    srcs = glob(["src/main/java/**/*.java"]),
)

haskell_toolchain_library(name = "base")

haskell_library(
    name = "hello-hs-lib",
    testonly = True,
    srcs = ["src/test/haskell/hello/Main.hs"],
    compiler_flags = [
        "-threaded",
        "-flink-rts",
    ],
    src_strip_prefix = "src/test/haskell/hello",
    deps = [":base"],
)

haskell_binary(
    name = "hello-hs",
    testonly = True,
    srcs = ["src/test/haskell/hello/Main.hs"],
    compiler_flags = ["-threaded"],
    deps = [":base"],
)

binary_closure(
    name = "clotestbin",
    testonly = True,
    src = "hello-hs",
    excludes = [
        "^/System/",
        "^/usr/lib/",
        "ld-linux-x86-64\\.so.*",
        "libgcc_s\\.so.*",
        "libc\\.so.*",
        "libdl\\.so.*",
        "libm\\.so.*",
        "libpthread\\.so.*",
    ],
)

library_closure(
    name = "clotest",
    testonly = True,
    srcs = [
        "hello-hs-lib",
        "libbootstrap.so",
    ],
    excludes = [
        "^/System/",
        "^/usr/lib/",
        "ld-linux-x86-64\\.so.*",
        "libgcc_s\\.so.*",
        "libc\\.so.*",
        "libdl\\.so.*",
        "libm\\.so.*",
        "libpthread\\.so.*",
    ],
)

java_binary(
    name = "hello-java",
    testonly = True,
    classpath_resources = [":clotest"],
    main_class = "io.tweag.jarify.JarifyMain",
    runtime_deps = [":base-jar"],
)

cc_library(
    name = "lib-cc",
    testonly = True,
    srcs = ["src/test/cc/hello/lib.c"],
)

cc_binary(
    name = "hello-cc-exe",
    testonly = True,
    srcs = ["src/test/cc/hello/main.c"],
    deps = ["lib-cc"],
)

binary_closure(
    name = "clotestbin-cc",
    testonly = True,
    src = "hello-cc-exe",
    excludes = [
        "^/System/",
        "^/usr/lib/",
    ],
)

sh_binary(
    name = "copy-closure",
    srcs = ["src/main/bash/copy-closure.sh"],
    data = ["src/main/bash/common/routines.sh"] + select({
        "@bazel_tools//src/conditions:darwin": [
            "src/main/bash/darwin/routines.sh",
            ":loader",
        ],
        "//conditions:default": ["src/main/bash/routines.sh"],
    }),
    deps = ["@bazel_tools//tools/bash/runfiles"],
)

buildifier(
    name = "buildifier-diff",
    mode = "diff",
)

buildifier(
    name = "buildifier",
    lint_mode = "warn",
)
