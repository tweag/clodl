load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

stardoc(
    name = "docs",
    out = "doc.md",
    input = "//clodl:clodl.bzl",
    deps = [
        ":refs",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "refs",
    srcs = ["@bazel_tools//tools:bzl_srcs"],
)
