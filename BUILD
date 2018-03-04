package(default_visibility = ["//visibility:public"])

load(
  "@io_tweag_rules_haskell//haskell:haskell.bzl",
  "haskell_test",
  "haskell_binary",
  "haskell_toolchain",
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

java_binary(
  name = "base-jar",
  srcs = glob(["src/main/java/**"]),
  main_class = "io.tweag.jarify.JarifyMain",
)

haskell_binary(
  name = "jarify",
  src_strip_prefix = "src/main/haskell",
  srcs = ["src/main/haskell/Main.hs"],
  data = [
    ":base-jar",
    "@org_nixos_patchelf//:patchelf",
    "@gcc//:bin",
  ],
  args = ["--base-jar", "$(location :base-jar)"],
  prebuilt_dependencies = [
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
  ],
)

haskell_binary(
  name = "hello",
  src_strip_prefix = "src/test/haskell/hello",
  srcs = ["src/test/haskell/hello/Main.hs"],
  compiler_flags = ["-dynamic", "-pie"],
  prebuilt_dependencies = ["base"],
  testonly = True,
)

sh_test(
  name = "hello-test",
  srcs = ["test-cmd.sh"],
  args = [
    "$(location :jarify)",
    "--base-jar",
    "$(location :base-jar)",
    "$(location :hello)",
  ],
  data = [":jarify", ":base-jar", ":hello"],
  timeout = "short",
)
