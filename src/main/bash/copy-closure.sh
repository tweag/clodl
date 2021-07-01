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

# --- begin runfiles.bash initialization ---
set -uo pipefail
f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }
unset f
set -e
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
    copy_lib "$libpath" "$DEST"
    traverse_deps $(library_name "$libpath")
done
