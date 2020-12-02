"""Library and binary closures"""

load("@bazel_skylib//lib:paths.bzl", "paths")

def _rename_as_solib_impl(ctx):
    """Renames files as libraries."""

    output_files = []
    for f in ctx.files.deps:
        if f.basename.endswith(".so") or f.basename.find(".so.") != -1:
            symlink = ctx.actions.declare_file(paths.join(ctx.attr.outputdir, f.basename))
        else:
            symlink = ctx.actions.declare_file(paths.join(ctx.attr.outputdir, "lib%s.so" % f.basename))
        output_files.append(symlink)
        ctx.actions.run_shell(
            inputs = depset([f]),
            outputs = [symlink],
            mnemonic = "Symlink",
            command = """
            set -eo pipefail
            mkdir -p {out_dir}
            ln -s $(realpath {target}) {link}
            """.format(
                target = f.path,
                link = symlink.path,
                out_dir = symlink.dirname,
            ),
        )

    return DefaultInfo(files = depset(output_files))

_rename_as_solib = rule(
    _rename_as_solib_impl,
    attrs = {
        "deps": attr.label_list(),
        "outputdir": attr.string(
          doc = "Where the outputs are placed.",
          mandatory = True,
        ),
    },
)
"""Renames files as shared libraries to make them suitable for linking
with `cc_binary`.

This is useful for linking executables built with `-pie`.

Example:

  ```bzl
  _rename_as_solib(
      name = "some_binary"
      dep = [":lib"]
      outputdir = "dir"
  )
  ```

  If some_binary has files `a.so` and `b`, the outputs are `dir/a.so`
  and `dir/b.so`. The outputs need to be placed in a new directory or
  bazel will complain of conflicts with the rules that initially
  created the runfiles.

  Note: Runfiles are not propagated.

"""

def _shared_lib_paths_impl(ctx):
    """Collects the list of shared library paths of an executable or library."""
    libs_file = ctx.actions.declare_file(ctx.label.name + ".txt")
    files = depset()
    runfiles = depset()
    for src in ctx.attr.srcs:
        files = depset(transitive = [src.files, files])
        runfiles = depset(transitive = [src.default_runfiles.files, runfiles])

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
        """.format(ldd = ldd.path, bash=bash.path, grep = grep.path, scanelf = scanelf.path),
    )

    if [] == ctx.attr.excludes:
        excludes = ""
    else:
        excludes = "'" + "' '".join(ctx.attr.excludes) + "'"

    args = ctx.actions.args()
    args.add_joined(files, join_with = " ")
    args.add(libs_file)
    ctx.actions.run_shell(
        outputs = [libs_file],
        inputs = depset([bash, grep, ldd, scanelf], transitive = [runfiles, files]),
        tools = [ctx.executable._deps_tool],
        arguments = [args],
        command = """
        set -eo pipefail
        tops="$1"
        libs_file="$2"

        # find the list of libraries with ldd
        PATH={tools}:$PATH {deps} $tops -- {excludes} > $libs_file
        """.format(
            deps = ctx.executable._deps_tool.path,
            excludes = excludes,
            tools = ldd.dirname,
        ),
    )

    return DefaultInfo(files = depset([libs_file]))

_shared_lib_paths = rule(
    _shared_lib_paths_impl,
    attrs = {
        "srcs": attr.label_list(),
        "excludes": attr.string_list(),
        "_deps_tool": attr.label(
            executable = True,
            cfg = "host",
            allow_files = True,
            default = Label("//:deps"),
        ),
    },
)
"""Collects the list of shared library paths of an executable or
library.

Produces a txt file containing the paths.

Example:

  ```bzl
  _shared_lib_paths = (
      name = "shared-libs"
      srcs = [":lib", ":exe"]
  )
  ```

  The output is shared-libs.txt.

"""

def _mangle_dir(name):
    """Creates a unique directory name from the repo name and package
      name of the package being evaluated, and a given name.

    """
    components = [native.repository_name(), native.package_name(), name]
    components = [c.replace("@", "") for c in components]
    components = [c for c in components if c]
    return "/".join(components).replace("_", "_U").replace("/", "_S")

def library_closure(name, srcs, outzip = "", excludes = [], executable = False, **kwargs):
    """
    Produce a closure of the given shared libraries.

    Produces a zip file containing a closure of all the shared
    libraries needed to load the given shared libraries.

    Example:

      ```bzl
      library_closure(
          name = "closure"
          srcs = [":lib1", ":lib2"]
          excludes = ["libexclude_this\.so", "libthis_too\.so"]
          outzip = "file.zip"
          ...
      )
      ```

      The zip file `<generated_dir>/file.zip` is created, with all the
      shared libraries required by `:lib1` and `:lib2` except those in
      excludes. `<generated_dir>` is a name which depends on `name`.

    Args:
      name: A unique name for this rule.

      srcs: Libraries whose dependencies need to be included.

      outzip: The name of the zip file to produce. If omitted, the
              file is named as the rule with a `.zip` file extension.
              If present, the file is created inside a directory with
              a name generated from the rule name.

      excludes: Patterns matching the names of libraries that should
                be excluded from the closure. Extended regular
                expresions as provided by grep can be used here.

      executable: Includes a wrapper in the zip file capable of executing the
                  closure (`<name>_wrapper`). If executable is False, the wrapper
                  is just a shared library `lib<name>_wrapper.so` that depends on
                  all the other libraries in the closure.

    """
    libs_file = "%s-libs" % name
    srclibs = "%s-as-libs" % name
    param_file = "%s-params.ld" % name
    dirs_file = "%s-search_dirs.ld" % name
    if executable:
        wrapper_lib = "%s_wrapper" % name
    else:
        wrapper_lib = "lib%s_wrapper.so" % name
    solibdir = _mangle_dir(name + "_solib")
    solibdir_renamed = solibdir + "_renamed"
    if outzip == "":
        outputdir = "."
        outzip = "%s.zip" % name
    else:
        outputdir = _mangle_dir(name)
        outzip = paths.join(outputdir, outzip)

    # Rename the inputs to solibs as expected by cc_binary.
    _rename_as_solib(
        name = srclibs,
        deps = srcs,
        outputdir = solibdir_renamed,
        **kwargs
    )

    # Get the paths of srcs dependencies.
    # It would be simpler if we could give the shared libraries
    # as outputs. Unfortunately, that information is currently
    # discovered when running the actions and isn't available when
    # wiring them.
    _shared_lib_paths(
        name = libs_file,
        srcs = srcs,
        excludes = excludes,
        **kwargs
    )

    # Produce the arguments for linking the wrapper library
    #
    # cc_binary links any libraries passed to it in srcs. But
    # we need these extra arguments to link all of the dependencies
    # that may reside outside the sandbox.
    #
    # We produce two files:
    # * params_file contains the dependencies names, and
    # * dirs_file contains the paths in which to look for dependencies.
    #
    # The linker fails with an obscure error if the contents of both files
    # are put into one.
    native.genrule(
        name = "%s_params_file" % name,
        srcs = [libs_file],
        cmd = """
        libs_file=$(SRCS)
        param_file=$(location %s)
        dirs_file=$(location %s)
        cat $$libs_file \
          | cut -f 2 \
          | sed "s/\\(.*\\)\\/.*/SEARCH_DIR(\\1)/" \
          | sort | uniq \
          > $$dirs_file
        echo "INPUT(" > $$param_file
        cat $$libs_file \
          | cut -f 2 \
          | sed "s/.*\\/\\(.*\\)/\\1/" \
          | sort | uniq \
          >> $$param_file
        echo ")" >> $$param_file
        """ % (param_file, dirs_file),
        outs = [param_file, dirs_file],
        **kwargs
    )

    # Build the wrapper library that links directly to all dependencies.
    # Loading the wrapper ensures that the transitive dependencies are found
    # in the final closure no matter how the runpaths of the direct
    # dependencies were set.
    native.cc_binary(
        name = wrapper_lib,
        linkshared = not executable,
        linkopts = [
            "-Wl,-rpath=$$ORIGIN",
            "$(location %s)" % param_file,
            "-T$(location %s)" % dirs_file,
        ],
        srcs = [srclibs],
        deps = [param_file, dirs_file],
        **kwargs
    )

    # Copy the libraries to a folder and zip them
    native.genrule(
        name = name,
        srcs = [libs_file, wrapper_lib, srclibs],
        cmd = """
        set -euo pipefail
        libs_file="$(location %s)"
        outputdir="%s"
        excludes="%s"
        srclibs="$(locations %s)"
        wrapper_lib="$(location %s)"
        tmpdir=$$(mktemp -d)

        # Put srclibs and the wrapper_lib names in an associative array
        declare -A srcnames
        for i in $${wrapper_lib} $${srclibs}
        do
            srcnames["$${i##*/}"]=1
        done
        # Keep the libraries which are not in SRCS
        declare -a libs=()
        while read i
        do
            if [ ! $${srcnames["$${i##*/}"]+defined} ]
            then
                echo "$$i" | {
                    read -r -d $$'\t' name
                    read -r path
                    cp "$$path" "$$tmpdir/$$name"
                }
            fi
        done < <(cat $$libs_file)
        cp "$${wrapper_lib}" $${srclibs} $$tmpdir

        mkdir -p "$$outputdir"
        zip -X -qjr $@ $$tmpdir
        rm -rf $$tmpdir

        # Check that the excluded libraries have been really excluded.

        # Check first that there are files to exclude.
        [ "$$excludes" ] || exit 0

        # Produce a file with regexes to exclude libs from the zip.
        tmpx_file=$$(mktemp tmpexcludes_file.XXXXXX)
        # Note: quotes are important in shell expansion to preserve newlines.
        echo "$$excludes" > $$tmpx_file

        # Check that excluded libraries don't appear in the zip file.
        if unzip -t $@ \
            | grep -e '^[ ]*testing: ' \
            | sed "s/^[ ]*testing: \\([^ ]*\\).*/\\1/" \
            | grep -Ef $$tmpx_file
        then
            echo "library_closure: lint: Some files were not excluded."
            exit 1
        fi

        rm -rf $$tmpx_file
        """ % (libs_file, outputdir, "\n".join(excludes), srclibs, wrapper_lib),
        outs = [outzip],
        **kwargs
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
          excludes = ["libexclude_this\.so", "libthis_too\.so"]
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
    zip_name="{zip_name}"
    zip_file_path="$(SRCS)"

    cat - "$$zip_file_path" > $@ <<END
    #!/usr/bin/env bash
    set -eu
    tmpdir=\$$(mktemp -d)
    trap "rm -rf '\$$tmpdir'" EXIT
    unzip -q "\$$0" -d "\$$tmpdir" 2> /dev/null || true
    "\$$tmpdir/{zip_name}_wrapper"
    exit 0
END
    chmod +x $@

    """.format(zip_name = zip_name),
        executable = True,
        outs = [name + ".sh"],
        **kwargs
    )
