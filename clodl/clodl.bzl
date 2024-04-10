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
    files = depset([f for f in ctx.files.srcs if f.extension != "a"])
    if files == depset():
        fail("no input files, or all of them are static libraries")
    runfiles = depset(transitive = [src.default_runfiles.files for src in ctx.attr.srcs])
    transitive_library_deps = depset(
        [
            lib.dynamic_library
            for src in ctx.attr.srcs
            if CcInfo in src
            for linker_input in src[CcInfo].linking_context.linker_inputs.to_list()
            for lib in linker_input.libraries
        ],
    )

    # find tools
    bash = ctx.actions.declare_file("bash")
    grep = ctx.actions.declare_file("grep")
    ldd = ctx.actions.declare_file("ldd")
    patchelf = ctx.actions.declare_file("patchelf")
    scanelf = ctx.actions.declare_file("scanelf")
    otool = ctx.actions.declare_file("otool")
    install_name_tool = ctx.actions.declare_file("install_name_tool")
    ctx.actions.run_shell(
        outputs = [bash, grep, ldd, patchelf, scanelf, otool, install_name_tool],
        use_default_shell_env = True,
        command = """
        set -eo pipefail
        ln -s $(command -v bash) {bash}
        if [[ $(uname -s) == "Darwin" ]]
        then
            touch {ldd}; chmod +x {ldd}
            touch {patchelf}; chmod +x {patchelf}
        else
            ln -s $(command -v ldd) {ldd}
            ln -s $(command -v patchelf) {patchelf}
        fi
        ln -s $(command -v grep) {grep}
        ln -s $(command -v scanelf) {scanelf}
        if [[ $(uname -s) == "Darwin" ]]
        then
            ln -s $(command -v otool) {otool}
            ln -s $(command -v install_name_tool) {install_name_tool}
        else
            touch {otool}; chmod +x {otool}
            touch {install_name_tool}; chmod +x {install_name_tool}
        fi
        """.format(
            ldd = ldd.path,
            bash = bash.path,
            grep = grep.path,
            patchelf = patchelf.path,
            scanelf = scanelf.path,
            otool = otool.path,
            install_name_tool = install_name_tool.path,
        ),
    )

    excludes = quote_list(ctx.attr.excludes)

    args = ctx.actions.args()
    args.add_joined(files, join_with = " ")
    args.add(output_file)
    ctx.actions.run_shell(
        outputs = [output_file],
        inputs = depset([bash, grep, ldd, patchelf, scanelf, otool, install_name_tool], transitive = [runfiles, files, transitive_library_deps]),
        tools = [ctx.executable._copy_closure_tool] + cc_tools.to_list(),
        arguments = [args],
        env = compiler_env,
        command = """

        set -euo pipefail
        srclibs="$1"
        output_file="$2"
        executable={executable}
        tmpdir=$(mktemp -d -p $PWD)

        PATH={tools}:$PATH {copy_closure} "$tmpdir" $srclibs -- {excludes}

        if [[ $(uname -s) == "Darwin" ]]
        then
            i=0
            for src in $srclibs
            do
                mv $tmpdir/${{src##*/}} $tmpdir/clodl-top$i
                i=$((i+1))
            done
		elif [[ $executable == "False" ]]
		then
            # Build the wrapper library that links directly to all dependencies.
            # Loading the wrapper ensures that the transitive dependencies are found
            # in the final closure no matter how the runpaths of the direct
            # dependencies were set.
            find $tmpdir/* \
              | sort -u \
              | sed "s/.*\\/\\(.*\\)/-l:\\1/" \
              > params
            echo \
              -L$tmpdir \
              "{compiler_options}" \
              >> params
            echo '-Wl,-rpath=$ORIGIN' >> params
            echo -o $tmpdir/clodl-top0 >> params
            {compiler} @params
		else
		    cp $tmpdir/${{srclibs##*/}} $tmpdir/clodl-top0
			chmod +w $tmpdir/clodl-top0
			{tools}/patchelf --set-rpath '$ORIGIN' $tmpdir/clodl-top0
			chmod -w $tmpdir/clodl-top0
        fi

        # zip all the libraries
        zip -0 -X -qjr $output_file $tmpdir
        rm -rf $tmpdir

        # Check that the excluded libraries have been really excluded.

        # Check first that there are files to exclude.
        [ '{excludes}' ] || exit 0

        # Produce a file with regexes to exclude libs from the zip.
        tmpx_file=$(mktemp tmpexcludes_file.XXXXXX -p $PWD)
        # Note: quotes are important in shell expansion to preserve newlines.
        echo '{n_excludes}' > $tmpx_file

        # Check that excluded libraries don't appear in the zip file.
        if unzip -t $output_file \
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
            copy_closure = ctx.executable._copy_closure_tool.path,
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
        "_copy_closure_tool": attr.label(
            executable = True,
            cfg = "host",
            allow_files = True,
            default = Label("//:copy-closure"),
        ),
        "_cc_toolchain": attr.label(default = Label("@bazel_tools//tools/cpp:current_cc_toolchain")),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
    doc = """
    Produces a zip file containing a closure of all the shared
    libraries needed to load the given shared libraries or executables.

    The zip file contains a clodl-top0 wrapper library or executable,
    linking to all of the other libraries. In OSX no wrapper is produced
    but the given binaries in srcs are renamed to clodl-top0, clodl-top1,
    etc, in the order they were given to library_closure.

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

      executable: Includes a wrapper (`clodl-top0`) in the zip file capable
                  of executing the closure . If executable is False, the wrapper
                  is just a shared library that depends on all the other
                  libraries in the closure.
    """,
)

def binary_closure(name, src, excludes = [], **kwargs):
    """
    Produce a closure of a given executable.

    Produces a zip file containing a closure of all the shared libraries needed
    to load the executable. The zipfile is prepended with a script that
    uncompresses the zip file and executes the binary.

    Example:
      ```bzl
      cc_binary(
          name = "hello-cc",
          srcs = ["src/test/cc/hello/main.c"],
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
      src: The executable
      excludes: Same purpose as in library_closure
      **kwargs: Extra arguments

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
    tmpdir="\\$$(mktemp -d)"
    trap "rm -rf '\\$$tmpdir'" EXIT
    unzip -q "\\$$0" -d "\\$$tmpdir" 2> /dev/null || true
    "\\$$tmpdir/ld-linux-x86-64.so.2" --library-path "\\$$tmpdir" "\\$$tmpdir/clodl-top0"
    exit 0
END
    chmod +x $@

    """,
        executable = True,
        outs = [name + ".sh"],
        **kwargs
    )
