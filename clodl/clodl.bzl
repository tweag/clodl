"""Library and binary closures"""

load("@bazel_skylib//:lib.bzl", "paths")

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
        inputs = depset([ctx.executable._deps_tool, bash, grep, ldd, scanelf], transitive = [runfiles, files]),
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

def _add_runfiles_impl(ctx):
    """Produces as output all the files needed to load an executable or library."""
    outputdir = ctx.attr.outputdir

    output_libs = {}
    input_libs = {}

    files = {}
    for f in ctx.files.deps:
        files[f.basename] = f
    for f in ctx.files.other_files:
        files[f.basename] = f
        input_libs[f.basename] = f
        output_libs[f.basename] = ctx.actions.declare_file(paths.join(outputdir, f.basename))

    for dep in ctx.attr.deps:
        for lib in dep.default_runfiles.files:
            # Runfiles might appear in inputs too. We don't duplicate them.
            if files.get(lib.basename, None) == None:
                # Skip non-library files.
                if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
                    input_libs[lib.basename] = lib
                    output_libs[lib.basename] = ctx.actions.declare_file(paths.join(outputdir, lib.basename))

    input_libs_files = input_libs.values()
    output_libs_files = output_libs.values()
    args = ctx.actions.args()
    args.add(output_libs_files[0].dirname if len(input_libs) > 0 else outputdir)
    args.add_joined(input_libs_files, join_with = " ")
    ctx.actions.run_shell(
        outputs = output_libs_files,
        inputs = input_libs_files,
        arguments = [args],
        command = """
        set -eo pipefail
        outputdir="$1"
        runfiles="$2"

        mkdir -p $outputdir
        for f in $runfiles
        do
            ln -s $(realpath $f) $outputdir/$(basename $f)
        done
    """,
    )

    return DefaultInfo(files = depset(output_libs_files))

_add_runfiles = rule(
    _add_runfiles_impl,
    attrs = {
        "deps": attr.label_list(),
        "other_files": attr.label_list(),
        "outputdir": attr.string(
          doc = "Where the outputs are placed.",
          mandatory = True
        ),
    },
)
"""Produces as output all the files needed to load an executable or library.

  The runfiles are output together with the files in "other_files".
  This is to ensure that the rule always produces some output to keep
  bazel checks happy.

Example:

  ```bzl
  _expose_runfiles(
      name = "lib_runfiles"
      deps = [":lib"]
      other_files = ["a", "b"]
      outputdir = "dir"
  )
  ```

  The outputs are placed in the directory `dir`. The outputs need to
  be placed in a new directory or bazel will complain of conflicts
  with the rules that initially created the runfiles.

"""

def library_closure(name, srcs, outzip = "", excludes = [], executable = False, **kwargs):
    """Produces a zip file containing a closure of all the shared
    libraries needed to load the given shared libraries.

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

    """
    libs_file = "%s-libs" % name
    srclibs = "%s-as-libs" % name
    runfiles_srclibs = "%s-runfiles-srclibs" % name
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
    _shared_lib_paths(
        name = libs_file,
        srcs = srcs,
        excludes = excludes,
        **kwargs
    )

    # Produce the arguments for linking the wrapper library
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
          | sed "s/\\(.*\\)\\/.*/SEARCH_DIR(\\1)/" \
          | sort | uniq \
          > $$dirs_file
        echo "INPUT(" > $$param_file
        cat $$libs_file \
          | sed "s/.*\\/\\(.*\\)/\\1/" \
          | sort | uniq \
          >> $$param_file
        echo ")" >> $$param_file
        """ % (param_file, dirs_file),
        outs = [param_file, dirs_file],
        **kwargs
    )

    # Expose the runfiles for linking the wrapper library.
    _add_runfiles(
        name = runfiles_srclibs,
        deps = srcs,
        other_files = [srclibs],
        outputdir = solibdir,
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
            param_file,
            "-T$(location %s)" % dirs_file,
        ],
        srcs = [runfiles_srclibs],
        deps = [param_file, dirs_file],
        **kwargs
    )

    # Copy the libraries to a folder and zip them
    native.genrule(
        name = name,
        srcs = [libs_file, wrapper_lib, runfiles_srclibs],
        cmd = """
        set -euo pipefail
        libs_file="$(location %s)"
        outputdir="%s"
        excludes="%s"
        tmpdir=$$(mktemp -d)

        # Put SRCS names in an associative array
        declare -A srcnames
        for i in $(SRCS)
        do
            srcnames["$${i##*/}"]=1
        done
        # Keep the libraries which are not in SRCS
        declare -a libs=()
        for i in $$(cat $$libs_file)
        do
            if [ ! $${srcnames["$${i##*/}"]+defined} ]
            then
                libs+=($$i)
            fi
        done
        cp $(SRCS) "$${libs[@]}" $$tmpdir
    
        mkdir -p "$$outputdir"
        zip -qjr $@ $$tmpdir
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
        """ % (libs_file, outputdir, "\n".join(excludes)),
        outs = [outzip],
        **kwargs
    )

def binary_closure(name, src, excludes = [], **kwargs):
    """
    Produces a zip file containing a closure of all the shared libraries needed
    to load the given executable. The zipfile is prepended with a script that
    uncompresses the zip file and executes the binary.

    Args:
      name: A unique name for this rule
      src: The executable binary
      excludes: Same purpose as in library_closure

    Example:
      ```bzl
      binary_closure(
          name = "closure"
          src = ":exe"
          excludes = ["libexclude_this\.so", "libthis_too\.so"]
          ...
      )
      ```
      The zip file closure is created, with all the
      shared libraries required by ":exe" except those in excludes.
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
