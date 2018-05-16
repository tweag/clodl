"""Rules for creating self-contained shared objects"""

load("@bazel_skylib//:lib.bzl", "paths")


def _impl_shared_lib_paths(ctx):
  """Collects the list of shared library paths of an executable or library."""
  libs_file = ctx.actions.declare_file(ctx.label.name + ".txt")
  files = depset()
  runfiles = depset()
  for src in ctx.attr.srcs:
    files = depset(transitive=[src.files, files])
    runfiles = depset(transitive=[src.default_runfiles.files, runfiles])
  args = ctx.actions.args();
  args.add(files)
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
      # Fail if any there are any missing libraries
      ! grep 'not found' $libs_file
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


def _mangle_solib_dir(name):
  """
    Creates a unique directory name from the repo name and package name of the
    package being evaluated, and a given name.
  """
  components = [native.repository_name(), native.package_name(), name]
  components = [c.replace('@','') for c in components]
  components = [c for c in components if c]
  return '/'.join(components).replace('_', '_U').replace('/', '_S') + "_solib"


def _impl_expose_runfiles(ctx):
  """Produces as output all the files needed to load an executable or library."""
  files = depset()
  runfiles = depset()
  libs = []
  for dep in ctx.attr.deps:
    files = depset(transitive=[dep.files, files])
    runfiles = depset(transitive=[dep.default_runfiles.files, runfiles])
    for lib in dep.default_runfiles.files + dep.files:
      # Skip non-library files.
      if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
        libs.append(ctx.actions.declare_file(paths.join(ctx.attr.outputdir.name, lib.basename)))

  outputdir = ctx.actions.declare_directory(ctx.attr.outputdir.name)

  args = ctx.actions.args();
  args.add(files)
  args.add_joined(runfiles, join_with=" ")
  args.add(outputdir)
  ctx.actions.run_shell(
    outputs = libs + [outputdir],
    inputs = depset(transitive=[runfiles, files]),
    arguments = [args],
    command = """
      set -e
      tops="$1"
      runfiles="$2"
      outputdir="$3"

      mkdir -p $outputdir
      for f in $tops $runfiles
      do
        ln -s $(realpath $f) $outputdir/$(basename $f)
      done
    """
  )

  return DefaultInfo(files=depset(libs))


_expose_runfiles = rule(
  implementation = _impl_expose_runfiles,
  attrs = { "deps": attr.label_list(),
            "outputdir" : attr.output(doc="Where the outputs are placed.", mandatory=True),
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


def library_closure(name, srcs, **kwargs):
  """
  Produces a zip file containing a closure of all the shared libraries needed
  to load the given shared libraries.

  Example:
    ```bzl
    library_closure(
        name = "closure"
        srcs = [":lib1", ":lib2"]
        ...
    )
    ```
    The file closure.zip is created.
  """
  libs_file = "%s-libs" % name
  runfiles = "%s-runfiles" % name
  param_file = "%s-params.ld" % name
  dirs_file = "%s-search_dirs.ld" % name
  wrapper_lib = "%s_wrapper" % name
  solibdir = _mangle_solib_dir(name)

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
    srcs = [runfiles],
    deps = [param_file, dirs_file],
    **kwargs
  )
  # Copy the libraries to a folder and zip them
  native.genrule(
    name = name,
    srcs = [libs_file, wrapper_lib, runfiles],
    cmd = """
    tmpdir=$$(mktemp -d)
    # We might fail to copy some paths in the libs_file
    # which might be files in the runfiles and are copied next.
    # TODO: we can make cp succeed if we implement this rule with
    # a custom rule instead of a genrule.
    cp $$(cat $(location %s)) $$tmpdir || true
    cp $(SRCS) $$tmpdir
    zip -qjr $@ $$tmpdir
    rm -rf $$tmpdir
    """ % libs_file,
    outs = ["%s.zip" % name],
    **kwargs
  )
