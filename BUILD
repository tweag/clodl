package(default_visibility = ["//visibility:public"])

load(
    "@io_tweag_rules_haskell//haskell:haskell.bzl",
    "haskell_binary",
    "haskell_test",
    "haskell_toolchain",
)
load(
    "@io_tweag_clodl//clodl:clodl.bzl",
    "library_closure",
    "binary_closure",
)

haskell_toolchain(
    name = "ghc",
    tools = "@ghc//:bin",
    version = "8.2.2",
)

cc_library(
    name = "bootstrap",
    srcs = ["src/main/cc/bootstrap.c"],
    copts = ["-std=c99"],
    deps = [
        "@ghc//:include",
        "@openjdk//:include",
    ],
)

java_library(
    name = "base-jar",
    srcs = glob(["src/main/java/**/*.java"]),
)

# TODO should be haskell_binary. Blocked on
# https://github.com/tweag/rules_haskell/issues/179.
haskell_binary(
    name = "hello-hs",
    testonly = True,
    srcs = ["src/test/haskell/hello/Main.hs"],
    compiler_flags = [
        "-threaded",
        "-dynamic",
        "-pie",
    ],
    prebuilt_dependencies = ["base"],
    src_strip_prefix = "src/test/haskell/hello",
    deps = [":bootstrap"],
)

library_closure(
    name = "clotest",
    testonly = True,
    srcs = ["hello-hs"],
    excludes = [
        "ld-linux-x86-64\.so.*",
        "libgcc_s\.so.*",
        "libc\.so.*",
        "libdl\.so.*",
        "libm\.so.*",
        "libpthread\.so.*",
    ],
    outzip = "closure.zip",
)

binary_closure(
    name = "clotestbin",
    testonly = True,
    src = "hello-hs",
    excludes = [
        "ld-linux-x86-64\.so.*",
        "libgcc_s\.so.*",
        "libc\.so.*",
        "libdl\.so.*",
        "libm\.so.*",
        "libpthread\.so.*",
    ],
)

java_binary(
    name = "hello-java",
    testonly = True,
    classpath_resources = [":clotest"],
    main_class = "io.tweag.jarify.JarifyMain",
    runtime_deps = [":base-jar"],
)

sh_binary(
    name = "deps",
    srcs = ["src/main/bash/deps.sh"],
)
