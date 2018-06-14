package(default_visibility = ["//visibility:public"])

load(
  "@io_tweag_rules_haskell//haskell:haskell.bzl",
  "haskell_test",
  "haskell_binary",
  "haskell_toolchain",
)

load(
  "@io_tweag_clodl//clodl:clodl.bzl",
  "library_closure",
)

haskell_toolchain(
  name = "ghc",
  version = "8.2.2",
  tools = "@ghc//:bin",
)

cc_library(
  name = "bootstrap",
  srcs = ["src/main/cc/bootstrap.c"],
  deps = ["@ghc//:include", "@openjdk//:include"],
  copts = ["-std=c99"],
)

java_library(
  name = "base-jar",
  srcs = glob(["src/main/java/**/*.java"]),
)

# TODO should be haskell_binary. Blocked on
# https://github.com/tweag/rules_haskell/issues/179.
haskell_binary(
  name = "hello-hs",
  src_strip_prefix = "src/test/haskell/hello",
  srcs = ["src/test/haskell/hello/Main.hs"],
  compiler_flags = ["-threaded", "-dynamic", "-pie"],
  deps = [":bootstrap"],
  prebuilt_dependencies = ["base"],
  testonly = True,
)

library_closure(
  name = "clotest",
  srcs = ["hello-hs"],
  outzip = "closure.zip",
  excludes = [
    "ld-linux-x86-64\.so.*",
    "libgcc_s\.so.*",
    "libc\.so.*",
    "libdl\.so.*",
    "libm\.so.*",
    "libpthread\.so.*",
  ],
  testonly = True,
)

java_binary(
  name = "hello-java",
  runtime_deps = [":base-jar"],
  classpath_resources = [":clotest"],
  main_class = "io.tweag.jarify.JarifyMain",
  testonly = True,
)
