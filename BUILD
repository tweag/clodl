load("@rules_cc//cc:defs.bzl", "cc_binary")

package(default_visibility = ["//visibility:public"])

cc_binary(
    name = "loader",
    srcs = ["src/main/cc/loader.cc"],
    linkopts = ["-ldl"],
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
