# clodl: self-contained dynamic libraries

[![Build status](https://badge.buildkite.com/2d086847c269703f6ce1f0dd97b64ea00196e2b8e8bb68d2fb.svg?branch=master)](https://buildkite.com/tweag-1/clodl)
[![Build status in Darwin](https://circleci.com/gh/tweag/clodl/tree/master.svg?style=svg)](https://circleci.com/gh/tweag/clodl/tree/master)

`clodl` computes the *closure* of a shared object. That is, given
an executable or shared library, it returns a single self-contained
file packing all dependencies. Think of the result as a poor man's
container image. Compared to containers:

* closures **do not** provide isolation (e.g. separate process,
  network, filesystem namespaces),
* but closures **do** allow for deploying to other machines without
  concerns about missing dependencies.

Clodl can be used to build binary closures or library closures.

A binary closure is made from an executable or a shared library
defining symbol `main` and can be executed. In practice, the binary
closure is a zip file appended to a script that uncompresses the file
to a temporary folder and has `main` invoked.

A library closure is a zip file containing the shared libraries in
the closure, and provides one or more top-level libraries which depends on all of
the others. When the closure is uncompressed, these top-level libraries
can be loaded into the address space of an existing process.

Executing a closure in the address space of an existing process
enables lightweight high-speed interop between the closure and the
rest of the process. The closure can natively invoke any function in
the process without marshalling/unmarshalling any arguments, and vice
versa.

## Example of binary closure

`clodl` is implemented as a set
of [Bazel][bazel] [build rules][bazel-rules]. It integrates with your
Bazel build system, e.g. as follows:

```
cc_binary(
  name = "hello-cc",
  srcs = ["main.c"],
  deps = ...
)

binary_closure(
  name = "hello-closure-bin",
  src = "hello-cc",
)
```

With Haskell:

```
haskell_binary(
    name = "hello-hs",
    linkstatic = False,
    srcs = ["src/test/haskell/hello/Main.hs"],
	...
)

binary_closure(
  name = "hello-closure-bin",
  src = "hello-hs",
)
```

The [BUILD file](BUILD) has complete examples.

[bazel]: https://bazel.build
[bazel-rules]: https://docs.bazel.build/versions/master/skylark/rules.html

## Example of library closure

`clodl` is useful for "jarifying" native binaries. Provided shim Java
code, closures can be packed inside a JAR and then loaded at runtime
into the JVM. This makes JAR's an alternative packaging format to
publish and deploy native binaries.

```
cc_binary(
  name = "libhello.so",
  srcs = ["main.c"],
  linkshared = 1,
  linkstatic = 0,
  deps = ...
)

library_closure(
  name = "hello-closure",
  srcs = ["libhello.so"],
)

java_binary(
  name = "hello-jar",
  classpath_resources = [":hello-closure"],
  main_class = ...,
  srcs = ...,
  runtime_deps = ...,
)
```

## Building it

**Requirements:**
* The [Bazel][bazel] build tool;
* the [Nix][nix] package manager;
* in Linux, the `scanelf` tool from the `pax-utils` package;
* in OSX, `otool` and `install_name_tool`.

To build and test:

```
$ bazel build //...
$ bazel run hello-java
```

[nix]: https://nixos.org/nix

## License

Copyright (c) 2015-2018 EURL Tweag.

All rights reserved.

clodl is free software, and may be redistributed under the terms
specified in the [LICENSE](LICENSE) file.

## About

clodl is maintained by [Tweag I/O](http://tweag.io/).

Have questions? Need help? Tweet at
[@tweagio](http://twitter.com/tweagio).
