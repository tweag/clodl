load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")

stardoc(
    name = "docs",
    input = "//clodl:clodl.bzl",
    out = "doc.md",
    deps = ["@bazel_skylib//lib:paths"],
)
