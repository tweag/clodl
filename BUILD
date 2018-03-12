package(default_visibility = ["//visibility:public"])

load(
  "@io_tweag_rules_haskell//haskell:haskell.bzl",
  "haskell_test",
  "haskell_library",
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
)

java_library(
  name = "base-jar",
  srcs = glob(["src/main/java/**"]),
)

# TODO should be haskell_binary. Blocked on
# https://github.com/tweag/rules_haskell/issues/179.
haskell_library(
  name = "hello-hs",
  src_strip_prefix = "src/test/haskell/hello",
  srcs = ["src/test/haskell/hello/Main.hs"],
  compiler_flags = ["-dynamic", "-pie"],
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
  testonly = True,
)

java_binary(
  name = "hello-java",
  runtime_deps = [":base-jar"],
  resources = [":clotest"],
  main_class = "io.tweag.jarify.JarifyMain",
  testonly = True,
)
