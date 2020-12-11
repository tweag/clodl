package(default_visibility = ["//visibility:public"])

load(
    "@rules_haskell//haskell:defs.bzl",
    "haskell_binary",
    "haskell_test",
    "haskell_toolchain_library",
)
load(
    "@io_tweag_clodl//clodl:clodl.bzl",
    "library_closure",
    "binary_closure",
)

cc_library(
    name = "bootstrap-bz",
    srcs = ["src/main/cc/bootstrap.c"],
    copts = ["-std=c99"],
    deps = [
        "@rules_haskell_ghc_nixpkgs//:include",
        "@openjdk//:include",
    ],
)

cc_binary(
    name = "libbootstrap.so",
    deps = ["bootstrap-bz"],
    linkshared = 1,
)

java_library(
    name = "base-jar",
    srcs = glob(["src/main/java/**/*.java"]),
)


haskell_toolchain_library(name = "base")
haskell_binary(
    name = "hello-hs",
    testonly = True,
    linkstatic = False,
    srcs = ["src/test/haskell/hello/Main.hs"],
    compiler_flags = [
        "-threaded",
        "-pie",
        "-optl-Wl,--dynamic-list=main-symbol-list.ld",
    ],
    extra_srcs = ["main-symbol-list.ld"],
    deps = [":base"],
    src_strip_prefix = "src/test/haskell/hello",
)

library_closure(
    name = "clotest",
    testonly = True,
    srcs = ["hello-hs", "libbootstrap.so"],
    excludes = [
        "ld-linux-x86-64\.so.*",
        "libgcc_s\.so.*",
        "libc\.so.*",
        "libdl\.so.*",
        "libm\.so.*",
        "libpthread\.so.*",
    ],
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

cc_library(
    name = "lib-cc",
    srcs = ["src/test/cc/hello/lib.c"],
    testonly = True,
)

cc_binary(
    name = "libhello-cc.so",
    srcs = ["src/test/cc/hello/main.c"],
    deps = ["lib-cc"],
    linkshared = 1,
    testonly = True,
)

binary_closure(
    name = "clotestbin-cc",
    testonly = True,
    src = "libhello-cc.so",
)

cc_binary(
    name = "libhello-cc-norunfiles.so",
    srcs = ["src/test/cc/hello/main.c"],
    linkshared = 1,
    testonly = True,
)

binary_closure(
    name = "clotestbin-cc-norunfiles",
    testonly = True,
    src = "libhello-cc-norunfiles.so",
)

cc_binary(
    name = "hello-cc-pie",
    srcs = ["src/test/cc/hello/main.c"],
    linkopts = ["-pie", "-Wl,--dynamic-list=main-symbol-list.ld"],
	deps = ["main-symbol-list.ld"],
    testonly = True,
)

binary_closure(
    name = "clotestbin-cc-pie",
    testonly = True,
    src = "hello-cc-pie",
)

sh_binary(
    name = "deps",
    srcs = ["src/main/bash/deps.sh"],
)

buildifier(
    name = "buildifier",
    lint_mode = "warn",
)
