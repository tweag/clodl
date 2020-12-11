"""Library and binary closures"""

load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")

def remove_library_flags(flags):
    return [f for f in flags if not f.startswith("-l")]

def quote_list(xs):
    if [] == xs:
        return ""
    else:
        return "'" + "' '".join(xs) + "'"

def _library_closure_impl(ctx):
    if ctx.attr.executable:
        action_name = ACTION_NAMES.cpp_link_executable
    else:
        action_name = ACTION_NAMES.cpp_link_nodeps_dynamic_library
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        unsupported_features = ctx.disabled_features,
    )
    compiler = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = action_name,
    )
    compiler_variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )
    compiler_options = remove_library_flags(cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compiler_variables,
    ))
    compiler_env = cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = action_name,
        variables = compiler_variables,
    )

    output_file = ctx.actions.declare_file(ctx.label.name + ".zip")
    cc_tools = ctx.attr._cc_toolchain.files
    files = depset(ctx.files.srcs)
    runfiles = depset(transitive = [src.default_runfiles.files for src in ctx.attr.srcs])

    # find tools
    bash = ctx.actions.declare_file("bash")
    grep = ctx.actions.declare_file("grep")
    ldd = ctx.actions.declare_file("ldd")
    scanelf = ctx.actions.declare_file("scanelf")
    ctx.actions.run_shell(
        outputs = [bash, grep, ldd, scanelf],
        use_default_shell_env = True,
        command = """
        set -eo pipefail
        ln -s $(command -v bash) {bash}
        ln -s $(command -v ldd) {ldd}
        ln -s $(command -v grep) {grep}
        ln -s $(command -v scanelf) {scanelf}
        """.format(ldd = ldd.path, bash = bash.path, grep = grep.path, scanelf = scanelf.path),
    )

    excludes = quote_list(ctx.attr.excludes)

    args = ctx.actions.args()
    args.add_joined(files, join_with = " ")
    args.add(output_file)
    ctx.actions.run_shell(
        outputs = [output_file],
        inputs = depset([bash, grep, ldd, scanelf], transitive = [runfiles, files]),
        tools = [ctx.executable._deps_tool] + cc_tools.to_list(),
        arguments = [args],
        env = compiler_env,
        command = """

        set -euo pipefail
        srclibs="$1"
        output_file="$2"
        executable={executable}
        tmpdir=$(mktemp -d -p $PWD)

        PATH={tools}:$PATH {deps} $srclibs -- {excludes} > libs.txt
        for lib in $srclibs
        do
          echo $lib >> libs.txt
        done
        cp $(cat libs.txt) $tmpdir

        # Build the wrapper library that links directly to all dependencies.
        # Loading the wrapper ensures that the transitive dependencies are found
        # in the final closure no matter how the runpaths of the direct
        # dependencies were set.
        cat libs.txt \
          | sort | uniq \
          | sed "s/.*\\/\\(.*\\)/-l:\\1/" \
          > params
        echo \
          -L$tmpdir \
          "{compiler_options}" \
          >> params
        echo '-Wl,-rpath=$ORIGIN' >> params
        if [ $executable == False ]
        then
          echo -o $tmpdir/libclodl-top.so >> params
        else
          echo -o $tmpdir/clodl-exe-top >> params
        fi
        {compiler} @params

        # zip all the libraries
        zip -X -qjr $output_file $tmpdir
        rm -rf $tmpdir

        # Check that the excluded libraries have been really excluded.

        # Check first that there are files to exclude.
        [ '{excludes}' ] || exit 0

        # Produce a file with regexes to exclude libs from the zip.
        tmpx_file=$(mktemp tmpexcludes_file.XXXXXX -p $PWD)
        # Note: quotes are important in shell expansion to preserve newlines.
        echo '{n_excludes}' > $tmpx_file

        # Check that excluded libraries don't appear in the zip file.
        if unzip -t $@ \
            | grep -e '^[ ]*testing: ' \
            | sed "s/^[ ]*testing: \\([^ ]*\\).*/\\1/" \
            | grep -Ef $tmpx_file
        then
            echo "library_closure: lint: Some files were not excluded."
            exit 1
        fi

        rm -rf $tmpx_file
        """.format(
            executable = ctx.attr.executable,
            excludes = excludes,
            n_excludes = "\n".join(ctx.attr.excludes),
            deps = ctx.executable._deps_tool.path,
            tools = ldd.dirname,
            compiler = compiler,
            compiler_options = quote_list(compiler_options),
        ),
    )

    return DefaultInfo(files = depset([output_file]))

library_closure = rule(
    _library_closure_impl,
    attrs = {
        "srcs": attr.label_list(),
        "excludes": attr.string_list(),
        "executable": attr.bool(),
        "_deps_tool": attr.label(
            executable = True,
            cfg = "host",
            allow_files = True,
            default = Label("//:deps"),
        ),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
    doc = """
    Produces a zip file containing a closure of all the shared
    libraries needed to load the given shared libraries or executables.

    Example:

      ```bzl
      library_closure(
          name = "closure"
          srcs = [":lib1", ":lib2"]
          excludes = ["libexclude_this\\.so", "libthis_too\\.so"]
          ...
      )
      ```

      The zip file `closure.zip` is created, with all the
      shared libraries required by `:lib1` and `:lib2` except those in
      excludes.

    Args:
      name: A unique name for this rule.

      srcs: Libraries whose dependencies need to be included.

      excludes: Patterns matching the names of libraries that should
                be excluded from the closure. Extended regular
                expresions as provided by grep can be used here.

      executable: Includes a wrapper in the zip file capable of executing the
                  closure (`clodl-exe-top`). If executable is False, the wrapper
                  is just a shared library `libclodl-top.so` that depends on
                  all the other libraries in the closure.

    """,
)

def binary_closure(name, src, excludes = [], **kwargs):
    """
    Produce a closure of a given position independent executable.

    Produces a zip file containing a closure of all the shared libraries needed
    to load the given position independent executable or shared library defining
    symbol main. The zipfile is prepended with a script that uncompresses the
    zip file and executes main.

    Example:
      ```bzl
      cc_binary(
          name = "hello-cc",
          srcs = ["src/test/cc/hello/main.c"],
          linkopts = ["-pie", "-Wl,--dynamic-list", "main-symbol-list.ld"],
          deps = ["main-symbol-list.ld"],
      )

      binary_closure(
          name = "closure"
          src = "hello-cc"
          excludes = ["libexclude_this\\.so", "libthis_too\\.so"]
          ...
      )
      ```
      The zip file closure is created, with all the
      shared libraries required by "hello-cc" except those in excludes.

    Args:
      name: A unique name for this rule
      src: The position independent executable or a shared library.
      excludes: Same purpose as in library_closure

    """
    zip_name = "%s-closure" % name
    library_closure(
        name = zip_name,
        srcs = [src],
        excludes = excludes,
        executable = True,
        **kwargs
    )

    # Prepend a script to execute the closure
    native.genrule(
        name = name,
        srcs = [zip_name],
        cmd = """
    set -eu
    zip_file_path="$(SRCS)"

    cat - "$$zip_file_path" > $@ <<END
    #!/usr/bin/env bash
    set -eu
    tmpdir=\\$$(mktemp -d)
    trap "rm -rf '\\$$tmpdir'" EXIT
    unzip -q "\\$$0" -d "\\$$tmpdir" 2> /dev/null || true
    "\\$$tmpdir/clodl-exe-top"
    exit 0
END
    chmod +x $@

    """,
        executable = True,
        outs = [name + ".sh"],
        **kwargs
    )
