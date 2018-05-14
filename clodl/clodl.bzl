"""Rules for creating self-contained shared objects"""

def _impl_add_runfiles(ctx):
  libs = []
  for dep in ctx.attr.deps:
    for lib in dep.default_runfiles.files:
      # Skip non-library files.
      if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
        # Skip libraries in _solib_* directories because they are rejected
        # by cc_binary.
        if not lib.short_path.startswith("_solib_"):
          libs.append(lib)
    for lib in dep.files:
      if lib.basename.endswith(".so") or lib.basename.find(".so.") != -1:
        if not lib.short_path.startswith("_solib_"):
          libs.append(lib)
  
  return DefaultInfo(files=depset(libs))

_add_runfiles = rule(
  implementation = _impl_add_runfiles,
  attrs = {"deps": attr.label_list()},
)

def library_closure(name, srcs, **kwargs):
  libs_file = "%s-libs.txt" % name
  libs_file2 = "%s-libs2.txt" % name
  with_runfiles = "%s-runfiles" % name
  param_file = "%s-params.ld" % name
  wrapper_lib = "%s_wrapper" % name
  _add_runfiles(
    name = with_runfiles,
    deps = srcs,
    **kwargs
  )
  native.genrule(
    name = "%s_libs" % name,
    srcs = srcs,
    cmd = """
    ldd $(SRCS) \
      | grep '=>' \
      | grep -v 'not found' \
      | sed 's/^.* => \\(.*\\) (0x[0-9a-f]*)/\\1/' \
      | sort \
      | uniq > $@
    """,
    outs = [libs_file],
    **kwargs
  )
  native.genrule(
    name = "%s_libs2" % name,
    srcs = [with_runfiles],
    cmd = """
    for f in $(SRCS)
    do
        # TODO: Write a rule that uses the short_path instead of the basename
        echo $$(basename $$f) >> $@
    done
    """,
    outs = [libs_file2],
    **kwargs
  )
  native.genrule(
    name = "%s_params_file" % name,
    srcs = [libs_file, libs_file2],
    cmd = """
    echo "INPUT($$(cat $(location %s)) $$(cat $(location %s)))" > $@
    """ % (libs_file, libs_file2),
    outs = [param_file],
    **kwargs
  )
  native.cc_binary(
    name = wrapper_lib,
    linkopts = [
      "-shared",
      "-Wl,-rpath=$$ORIGIN",
      param_file,
    ],
    # TODO: Investigate why libs from with_runfiles don't show up in the
    # gcc invocation. The libs are reachable still, but they need to be
    # included in the param_file instead.
    srcs = [with_runfiles],
    deps = [param_file],
    **kwargs
  )
  native.genrule(
    name = name,
    srcs = [libs_file, wrapper_lib, with_runfiles],
    cmd = """
    echo $(SRCS) > /tmp/out.txt
    tmpdir=$$(mktemp -d)
    cp $$(cat $(location %s)) $$tmpdir
    cp $(SRCS) $$tmpdir
    zip -qjr $@ $$tmpdir
    rm -rf $$tmpdir
    """ % libs_file,
    outs = ["%s.zip" % name],
    **kwargs
  )
