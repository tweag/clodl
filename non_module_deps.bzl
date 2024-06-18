load("@rules_nixpkgs_cc//:cc.bzl", "nixpkgs_cc_configure")

def _non_module_deps_impl(_ctx):
    nixpkgs_cc_configure(
        repository = "@nixpkgs",
        register = False,
    )

non_module_deps = module_extension(
    implementation = _non_module_deps_impl,
)
