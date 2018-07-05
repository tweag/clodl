# clodl: self-contained dynamic libraries

`clodl` computes the *closure* of a shared object. That is, given
a shared library or a position independent executable (PIE), it
returns a single, self-contained file packing all dependencies. Think
of the result as a poor man's container image. Compared to containers:

* closures **do not** provide isolation (e.g. separate process,
  network, filesystem namespaces),
* but closures **do** allow for loading into the same address space as
  an existing process.
  
Executing a closure in the address space of an existing process
enables lightweight high-speed interop between the closure and the
rest of the process. The closure can natively invoke any function in
the process without marshalling/unmarshalling any arguments, and vice
versa.

`clodl` is useful for "jarifying" native binaries. Provided shim Java
code, closures can be packed inside a JAR and then loaded at runtime
into the JVM. This makes JAR's an alternative packaging format to
publish and deploy native binaries.

## Example

`clodl` is implemented as a set
of [Bazel][bazel] [build rules][bazel-rules]. It integrates with your
Bazel build system, e.g. as follows:

```
cc_binary(
  name = "hello.so",
  srcs = ["*.c"],
  linkedshared = 1,
)

library_closure(
  name = "hello-closure",
  srcs = ["hello.so"],
  testonly = True,
)

java_binary(
  name = "hello-jar",
  resources = [":hello-closure"],
  main_class = ...,
  srcs = ...,
  runtime_deps = ...,
)
```

[bazel]: https://bazel.build
[bazel-rules]: https://docs.bazel.build/versions/master/skylark/rules.html

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
