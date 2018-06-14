"""Rules for creating self-contained shared objects"""

load("@bazel_skylib//:lib.bzl", "paths")


def _impl_rename_as_solib(ctx): 
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
        set -e
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
  implementation = _impl_rename_as_solib,
  attrs = { "deps": attr.label_list(),
            "outputdir" : attr.string(doc="Where the outputs are placed.", mandatory=True),
          },
)
"""
Renames files as shared libraries to make them suitable for linking with cc_binary.
This is useful for linking executables built with -pie.

Example:
  ```bzl
  _rename_as_solib(
      name = "some_binary"
      dep = [":lib"]
      outputdir = "dir"
  )
  ```
  If some_binary has files a.so and b, the outputs are dir/a.so and dir/b.so.
  The outputs need to be placed in a new directory or bazel will complain of conflicts
  with the rules that initially created the runfiles.

  Note: Runfiles are not propagated.
"""


def _impl_shared_lib_paths(ctx):
  """Collects the list of shared library paths of an executable or library."""
  libs_file = ctx.actions.declare_file(ctx.label.name + ".txt")
  files = depset()
  runfiles = depset()
  for src in ctx.attr.srcs:
    files = depset(transitive=[src.files, files])
    runfiles = depset(transitive=[src.default_runfiles.files, runfiles])
  args = ctx.actions.args();
  args.add_joined(files, join_with=" ")
  args.add(libs_file)
  ctx.actions.run_shell(
    outputs = [libs_file],
    inputs = depset(transitive=[runfiles, files]),
    arguments = [args],
    command = """
      set -e
      tops="$1"
      libs_file="$2"

      # find the list of libraries with ldd
      ldd $tops \
        | grep '=>' \
        | grep -v 'linux-vdso.so' \
        | sed "s/^.* => \\(.*\\) (0x[0-9a-f]*)/\\1/" \
        | sort \
        | uniq > $libs_file
      # Fail if there are any missing libraries
      if grep 'not found' $libs_file
      then
        exit 1
      fi
    """
  )

  return DefaultInfo(files=depset([libs_file]))


_shared_lib_paths = rule(
  implementation = _impl_shared_lib_paths,
  attrs = { "srcs": attr.label_list() },
)
"""
Collects the list of shared library paths of an executable or library.

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
  """
    Creates a unique directory name from the repo name and package name of the
    package being evaluated, and a given name.
  """
  components = [native.repository_name(), native.package_name(), name]
  components = [c.replace('@','') for c in components]
  components = [c for c in components if c]
  return '/'.join(components).replace('_', '_U').replace('/', '_S')


def _impl_expose_runfiles(ctx):
  """Produces as output all the files needed to load an executable or library."""
  outputdir = ctx.attr.outputdir

  output_libs = {}
  input_libs = {}
  for dep in ctx.attr.deps:
    for lib in dep.default_runfiles.files:
      # Skip non-library files.
      if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
        input_libs[lib.basename] = lib
        output_libs[lib.basename] = ctx.actions.declare_file(paths.join(outputdir, lib.basename))

  input_libs_files = input_libs.values()
  output_libs_files = output_libs.values()
  args = ctx.actions.args();
  args.add(output_libs_files[0].dirname if len(input_libs) > 0 else outputdir)
  args.add_joined(input_libs_files, join_with=" ")
  ctx.actions.run_shell(
    outputs = output_libs_files,
    inputs = input_libs_files,
    arguments = [args],
    command = """
      set -e
      outputdir="$1"
      runfiles="$2"

      mkdir -p $outputdir
      for f in $runfiles
      do
        ln -s $(realpath $f) $outputdir/$(basename $f)
      done
    """
  )

  return DefaultInfo(files=depset(output_libs_files))


_expose_runfiles = rule(
  implementation = _impl_expose_runfiles,
  attrs = { "deps": attr.label_list(),
            "outputdir" : attr.string(doc="Where the outputs are placed.", mandatory=True),
          },
)
"""
Produces as output all the files needed to load an executable or library.

Example:
  ```bzl
  _expose_runfiles(
      name = "lib_runfiles"
      deps = [":lib"]
      outputdir = "dir"
  )
  ```
  The outputs are placed in the directory dir. The outputs need to be placed in
  a new directory or bazel will complain of conflicts with the rules that
  initially created the runfiles.
"""


def library_closure(name, srcs, outzip = "", excludes = [], **kwargs):
  """
  Produces a zip file containing a closure of all the shared libraries needed
  to load the given shared libraries.

  Args:
    name: A unique name for this rule.
    srcs: Libraries whose dependencies need to be included.
    outzip: The name of the zip file to produce. If omitted, the file is named
            as the rule with a .zip file extension. If present, the file is
            created inside a directory with a name generated from the rule name.
    excludes: Patterns matching the names of libraries that should be excluded
              from the closure. Extended regular expresions as provided by grep
              can be used here.

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
    The zip file <generated_dir>/file.zip is created, with all the
    shared libraries required by ":lib1" and ":lib2" except those in excludes.
    <generated_dir> is a name which depends on name.
  """
  libs_file = "%s-libs" % name
  srclibs = "%s-as-libs" % name
  runfiles = "%s-runfiles" % name
  param_file = "%s-params.ld" % name
  dirs_file = "%s-search_dirs.ld" % name
  wrapper_lib = "%s_wrapper" % name
  solibdir = _mangle_dir(name + "_solib")
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
    outputdir = solibdir,
    **kwargs
  )

  # Get the paths of srcs dependencies.
  _shared_lib_paths(
    name = libs_file,
    srcs = srcs,
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
  _expose_runfiles(
    name = runfiles,
    deps = srcs,
    outputdir = solibdir,
    **kwargs
  )
  # Build the wrapper library that links directly to all dependencies.
  # Loading the wrapper ensures that the transitive dependencies are found
  # in the final closure no matter how the runpaths of the direct
  # dependencies were set.
  native.cc_binary(
    name = wrapper_lib,
    linkopts = [
      "-shared",
      "-L" + solibdir,
      "-Wl,-rpath=$$ORIGIN",
      param_file,
      "-T$(location %s)" % dirs_file,
    ],
    srcs = [runfiles, srclibs],
    deps = [param_file, dirs_file],
    **kwargs
  )
  # Copy the libraries to a folder and zip them
  native.genrule(
    name = name,
    srcs = [libs_file, wrapper_lib, runfiles, srclibs],
    cmd = """
    libs_file="$(location %s)"
    outputdir="%s"
    excludes="%s"
    tmpdir=$$(mktemp -d)
    # Produce a file with regexes to exclude libs from the zip.
    tmpx_file=$$(mktemp tmpexcludes_file.XXXX)
    # Note: quotes are important in shell expansion to preserve newlines.
    echo "$$excludes" | sed "s/\\(.*\\)/^(.*\\/)?\\1$$/" > $$tmpx_file

    # We might fail to copy some paths in the libs_file
    # which might be files in the runfiles and are copied next.
    # TODO: we can make cp succeed if we implement this rule with
    # a custom rule instead of a genrule.
    cp $$(cat $$libs_file | grep -Evf $$tmpx_file) $$tmpdir || true
    cp $$(echo -n $(SRCS) | xargs -L 1 -d ' ' | grep -Evf $$tmpx_file) $$tmpdir
    
    mkdir -p "$$outputdir"
    zip -qjr $@ $$tmpdir
    rm -rf $$tmpdir $$tmpx_file
    """ % (libs_file, outputdir, '\n'.join(excludes)),
    outs = [outzip],
    **kwargs
  )
