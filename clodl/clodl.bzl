"""Rules for creating self-contained shared objects"""

def library_closure(name, srcs, **kwargs):
  libs_file = "%s-libs.txt" % name
  param_file = "%s-params.ld" % name
  wrapper_lib = "%s_wrapper" % name
  native.genrule(
    name = "%s_libs" % name,
    srcs = srcs,
    cmd = """
    ldd $(SRCS) \
      | grep '=>' \
      | sed 's/^.* => \\(.*\\) (0x[0-9a-f]*)/\\1/' \
      | sort \
      | uniq > $@
    """,
    outs = [libs_file],
    **kwargs
  )
  native.genrule(
    name = "%s_params_file" % name,
    srcs = [libs_file],
    cmd = """
    echo "INPUT($$(cat $(location %s)))" > $@
    """ % libs_file,
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
    srcs = srcs,
    deps = [param_file],
    **kwargs
  )
  native.genrule(
    name = name,
    srcs = [libs_file, wrapper_lib] + srcs,
    cmd = """
    tmpdir=$$(mktemp -d)
    cp $$(cat $(location %s)) $$tmpdir
    cp $(SRCS) $$tmpdir
    zip -qjr $@ $$tmpdir
    rm -rf $$tmpdir
    """ % libs_file,
    outs = ["%s.zip" % name],
    **kwargs
  )
