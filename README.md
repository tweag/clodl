# clodl: self-contained dynamic libraries

[![CircleCI](https://circleci.com/gh/tweag/clodl.svg?style=svg)](https://circleci.com/gh/tweag/clodl)

`clodl` computes the *closure* of a shared object. That is, given
a shared library or a position independent executable (PIE), it
returns a single, self-contained file packing all dependencies. Think
of the result as a poor man's container image. Compared to containers:

* closures **do not** provide isolation (e.g. separate process,
  network, filesystem namespaces),
* but closures **do** allow for deploying to other machines without
  concerns about missing dependencies.

Clodl can be used to build binary closures or library closures.

A binary closure is made from an executable and can be executed.
In practice, the binary closure is a zip file appended to a script
that uncompresses the file to a temporary folder and has the
executable invoked.

A library closure is a zip file containing the shared libraries in
the closure, and provides a top-level library which depends on all of
the others. When the closure is uncompressed, this top-level library
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
  name = "libhello.so",
  srcs = ["main.c"],
  linkshared = 1,
  linkstatic = 0,
  deps = ...
)

binary_closure(
  name = "hello-closure-bin",
  src = "libhello.so",
)
```

With Haskell:

```
haskell_binary(
    name = "hello-hs",
    srcs = ["src/test/haskell/hello/Main.hs"],
    compiler_flags = [
        "-threaded",
        "-dynamic",
        "-pie",
    ],
	...
)

binary_closure(
  name = "hello-closure-bin",
  src = "hello-hs",
)
```

The [BUILD file](BUILD) has a complete example.

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
* the [Nix][nix] package manager.

To build and test:

```
$ bazel build //...
$ bazel run hello-java
```

[nix]: https://nixos.org/nix

## Usage

Any shared library (`.so` file) or [position independent][wp-pic]
(dynamically linked) executable (PIE) can be "closed" using `clodl`.

On OS X, all executables are PIE.

To create a PIE on Linux and other platforms, pass the `-pie` flag to
the compiler. For example with GCC,

```
$ gcc -pie ...
```

Some distributions create position independent executables by default
(Ubuntu and Debian on some architectures).

[wp-pic]: https://en.wikipedia.org/wiki/Position-independent_code

## License

Copyright (c) 2015-2018 EURL Tweag.

All rights reserved.

clodl is free software, and may be redistributed under the terms
specified in the [LICENSE](LICENSE) file.

## About

[<img src="https://www.tweag.io/img/tweag-med.png" height="65">](http://tweag.io)

clodl is maintained by [Tweag I/O](http://tweag.io/).

Have questions? Need help? Tweet at
[@tweagio](http://twitter.com/tweagio).
