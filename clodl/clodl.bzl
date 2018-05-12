"""Rules for creating self-contained shared objects"""

load("@bazel_skylib//:lib.bzl", "paths")

def _impl_shared_lib_paths(ctx):
  libs_file = ctx.actions.declare_file(ctx.label.name + ".txt")
  args = ctx.actions.args();
  args.add(ctx.attr.srcs[0][DefaultInfo].files)
  args.add_joined(ctx.attr.srcs[0].default_runfiles.files, join_with="\n")
  args.add(libs_file)
  ctx.actions.run_shell(
    outputs = [libs_file],
    inputs = ctx.attr.srcs[0].default_runfiles.files + ctx.attr.srcs[0].files,
    arguments = [args],
    command = """
      set -e
      tops="$1"
      runfiles="$2"
      libs_file="$3"

      # find the list of libraries with ldd
      tmpdir=$(mktemp -d)
      tmplibs_file=$(mktemp tmp-libs.XXXXXXXXXX)
      ldd $tops \
        | grep '=>' \
        | grep -v 'linux-vdso.so' \
        | sed "s/^.* => \\(.*\\) (0x[0-9a-f]*)/\\1/" \
        | sort \
        | uniq > $libs_file
      # Fail if any there are any missing libraries
      ! grep 'not found' $tmplibs_file
    """
  )

  return DefaultInfo(files=depset([libs_file]))

_shared_lib_paths = rule(
  implementation = _impl_shared_lib_paths,
  attrs = { "srcs": attr.label_list() },
)

def _impl_expose_runfiles(ctx):
  libs = []
  for dep in ctx.attr.deps:
    for lib in dep.default_runfiles.files + dep.files:
      # Skip non-library files.
      if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
        libs.append(ctx.actions.declare_file(paths.join(ctx.attr.output_prefix, lib.basename)))

  args = ctx.actions.args();
  args.add(ctx.attr.deps[0][DefaultInfo].files)
  args.add_joined(ctx.attr.deps[0].default_runfiles.files, join_with="\n")
  args.add(ctx.attr.output_prefix)
  args.add(ctx.bin_dir.path)
  ctx.actions.run_shell(
    outputs = libs,
    inputs = ctx.attr.deps[0].default_runfiles.files + ctx.attr.deps[0].files,
    arguments = [args],
    command = """
      set -e
      tops="$1"
      runfiles="$2"
      output_prefix="$3"
      bin="$4"

      mkdir -p $output_prefix
      for f in $tops $runfiles
      do
        ln -s $(realpath $f) $bin/$output_prefix/$(basename $f)
      done
    """
  )

  return DefaultInfo(files=depset(libs))

_expose_runfiles = rule(
  implementation = _impl_expose_runfiles,
  attrs = {"deps": attr.label_list(),
           "output_prefix": attr.string(),
          },
)

def library_closure(name, srcs, **kwargs):
  libs_file = "%s-libs" % name
  with_runfiles = "%s-runfiles" % name
  param_file = "%s-params.ld" % name
  dirs_file = "%s-search_dirs.ld" % name
  wrapper_lib = "%s_wrapper" % name
  solibdir = "%s_solibdir" % name
  _expose_runfiles(
    name = with_runfiles,
    deps = srcs,
    output_prefix = solibdir,
    **kwargs
  )
  _shared_lib_paths(
    name = libs_file,
    srcs = srcs,
    **kwargs
  )
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
  native.cc_binary(
    name = wrapper_lib,
    linkopts = [
      "-shared",
      "-L" + solibdir,
      "-Wl,-rpath=$$ORIGIN",
      param_file,
      "-T$(location %s)" % dirs_file,
    ],
    srcs = [with_runfiles],
    deps = [param_file, dirs_file],
    **kwargs
  )
  native.genrule(
    name = name,
    srcs = [libs_file, wrapper_lib, with_runfiles],
    cmd = """
    tmpdir=$$(mktemp -d)
    # We might fail to copy some paths in the libs_file
    # which might be files in the runpath and are copied next.
    cp $$(cat $(location %s)) $$tmpdir || true
    cp $(SRCS) $$tmpdir
    zip -qjr $@ $$tmpdir
    rm -rf $$tmpdir
    """ % libs_file,
    outs = ["%s.zip" % name],
    **kwargs
  )
