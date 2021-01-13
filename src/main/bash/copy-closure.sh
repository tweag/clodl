#!/usr/bin/env bash
#
# deps.sh DEST FILES [-- REGEXES]
#
# Copies to DIR the dependencies of the given shared libraries.
#
# Dependencies and its transitive dependencies can be excluded
# from the listing by adding grep-style regular expressions following --.
#
# Requires otool and install_name_tool to be on the path.
set -euo pipefail

# --- begin runfiles.bash initialization ---
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
    if [[ -f "$0.runfiles_manifest" ]]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [[ -f "$0.runfiles/MANIFEST" ]]; then
      export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
    elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
      export RUNFILES_DIR="$0.runfiles"
    fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---


if [[ $(uname -s) == "Darwin" ]]
then
	source "$(rlocation io_tweag_clodl/src/main/bash/darwin/routines.sh)"
else
	source "$(rlocation io_tweag_clodl/src/main/bash/routines.sh)"
fi

DEST=$1
shift

# Fill arrays tops and excludes
read_args "$@"

# paths is an associative array mapping each library name to its path. 
declare -A paths
while read lib
do
    paths["${lib##*/}"]="$lib"
done < <(collect_lib_paths "${tops[@]}")

# needed is an associative array mapping paths to a list of names of
# needed libraries.
declare -A needed
while read -r key val
do
	needed[$key]="$val"
done < <(needed_libs "${paths[@]}" "${tops[@]}")

compute_excluded_libs "${paths[@]}" "${tops[@]}"

# Libraries which should not be printed
declare -A dont_print
for lib in "${!excluded_libs[@]}"
do
    dont_print["$lib"]=1
done

# Copies the dependencies as they are found in a traversal
# of the dependency tree of a given shared library.
#
# Dependencies are printed the first time they are encountered
# only.
traverse_deps() {
    # We avoid using subshells in this function to keep it fast.
    # At the time of this writing, each subshell took in the
    # order of 10 ms.
    for lib in ${needed[$1]-}
    do
        if [ ! ${dont_print["$lib"]+defined} ]
        then
           copy_lib ${paths["$lib"]} "$DEST"
           dont_print["$lib"]=1
           traverse_deps "${paths["$lib"]}"
        fi
    done
}

for libpath in "${tops[@]}"
do
    echo "$libpath"
    copy_lib "$libpath" "$DEST"
    traverse_deps $libpath
done
