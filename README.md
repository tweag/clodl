# JARify: transmutation of native binaries into JVM apps

Give `jarify` a dynamically linked executable `launch-missiles`, out
comes a standalone JVM application `launch-missiles.jar`. You can run
it with

```
$ java -jar launch-missiles.jar
```

The resulting JAR does not fork `launch-missiles` in a separate
process when run. It is dynamically loaded into the same address space
as the JVM spawned by `java` and can therefore call into the JVM (e.g.
using the [JNI][jni]).

[jni]: https://docs.oracle.com/javase/8/docs/technotes/guides/jni/spec/jniTOC.html

## Building it

**Requirements:**
* the [Stack][stack] build tool (version 1.2 or above);
* either, the [Nix][nix] package manager,
* or, OpenJDK and Gradle installed globally on your system.

To build and copy `jarify` to `~/.local/bin`:

```
$ stack build --copy-bins
```

You can optionally get Stack to download a JDK in a local sandbox
(using [Nix][nix]) for good build results reproducibility. **This is
the recommended way to build jarify.** Alternatively, you'll need
it installed through your OS distribution's package manager for the
next steps (and you'll need to tell Stack how to find the JVM header
files and shared libraries).

To use Nix, set the following in your `~/.stack/config.yaml` (or pass
`--nix` to all Stack commands, see the [Stack manual][stack-nix] for
more):

```yaml
nix:
  enable: true
```

[stack]: https://github.com/commercialhaskell/stack
[stack-nix]: https://docs.haskellstack.org/en/stable/nix_integration/#configuration
[nix]: http://nixos.org/nix

## Usage

Any [position independent][wp-pic] (dynamically linked) executable
(PIE) can be transmutated in this way:

```
$ jarify <FILE>
```

On OS X, all executables are PIE.

To create a PIE on Linux and other platforms, pass the `-pie` flag to
the linker. Currently, we furthermore require "origin processing" to
be turned on. Here is the full set of options to pass to `ld`:

```
$ gcc -pie -Wl,-z,origin -Wl,-rpath,$ORIGIN ...
```

Some distributions create position independent executables by default
(Ubuntu and Debian on some architectures).

[wp-pic]: https://en.wikipedia.org/wiki/Position-independent_code

## License

Copyright (c) 2015-2016 EURL Tweag.

All rights reserved.

jarify is free software, and may be redistributed under the terms
specified in the [LICENSE](LICENSE) file.

## About

![Tweag I/O](http://i.imgur.com/0HK8X4y.png)

jarify is maintained by [Tweag I/O](http://tweag.io/).

Have questions? Need help? Tweet at
[@tweagio](http://twitter.com/tweagio).
