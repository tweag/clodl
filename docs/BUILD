load("@io_bazel_stardoc//stardoc:stardoc.bzl", "stardoc")
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

stardoc(
    name = "docs",
    input = "//clodl:clodl.bzl",
    out = "doc.md",
    deps = [
        "@bazel_skylib//lib:paths",
        ":refs",
    ],
)

bzl_library(
    name = "refs",
    srcs = ["@bazel_tools//tools:bzl_srcs"],
)
