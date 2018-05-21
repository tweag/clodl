package(default_visibility = ["//visibility:public"])

load(
  "@io_tweag_rules_haskell//haskell:haskell.bzl",
  "haskell_test",
  "haskell_binary",
  "haskell_toolchain",
  "cc_haskell_import",
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

cc_haskell_import(
  name ="hello-cc",
  dep = ":hello-hs",
  testonly = True,
)

library_closure(
  name = "clotest",
  srcs = ["hello-cc"],
  excludes = [
    "ld-linux-x86-64.so.2",
    "libgcc_s.so.1",
    "libc.so.6",
    "libdl.so.2",
    "libm.so.6",
    "libpthread.so.0",
  ],
  testonly = True,
)

java_binary(
  name = "hello-java",
  runtime_deps = [":base-jar"],
  resources = [":clotest"],
  main_class = "io.tweag.jarify.JarifyMain",
  testonly = True,
)
