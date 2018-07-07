#!/bin/bash
#
# deps.sh FILES [-- REGEXES]
#
# Produces the list of paths to dependencies of the given shared libraries.
#
# Dependencies and its transitive dependencies can be excluded
# from the listing by adding grep-style regular expressions following --.
#
# Requires ldd and objdump to be on the path.
set -euo pipefail

# tops contains the libraries to analyze.
# excludes contains the regexes provided by the user.
declare -a tops excludes=()

# Populates tops and excludes with the arguments of
# the invocation.
read_args() {
    local found_ddash=0
    for arg in "$@"
    do
        [ "$arg" == "--" ] && { found_ddash=1; continue; }
        if [ $found_ddash == "0" ]
        then
            tops+=($arg)
        else
            excludes+=($arg)
        fi
    done
}

# Prints a list of library paths for the dependencies of tops.
collect_lib_paths() {

    libs_str=$(ldd "${tops[@]}")

    # Fail if there are any missing libraries
    if echo "$libs_str" | grep 'not found'
    then
        exit 1
    fi

    # Collect library paths
    echo "$libs_str" \
      | grep '=>' \
      | grep -v 'linux-vdso.so' \
      | sed "s/^.* => \\(.*\\) (0x[0-9a-f]*)/\\1/" \
      | sort \
      | uniq
}

# excluded_libraries lib1 lib2 lib3 ...
# Prints the excluded libraries in the command line that match any
# of the regexes in excludes.
excluded_libraries() {
    if [ ${#excludes[@]} -gt 0 ]
    then
        printf '%s\n' "$@" \
          | grep -E $(printf ' -e %s' "${excludes[@]}")
    fi
}

# Produces the names of the libraries needed by the given shared libraries.
#
# The output is of the form [lib1]='needed libraries' [lib2]=...
# suitable for assignment of associative arrays.
needed_libs() {
    scanelf -qn "$@" | sed "s/\([^ ]*\)  \(.*\)/[\\2]='\\1'/;y/,/ /"
}


read_args "$@"

# paths is an associative array mapping each library name to its path. 
declare -A paths
for lib in $(collect_lib_paths)
do
    paths["${lib##*/}"]="$lib"
done

# needed is an associative array mapping paths to a list of names of
# needed libraries.
declare -A needed="($(needed_libs "${paths[@]}" "${tops[@]}"))"

# Libraries which should not be printed
declare -A dont_print
for lib in $(excluded_libraries "${!paths[@]}" "${tops[@]}")
do
    dont_print["$lib"]=1
done

# Produces the dependencies as they are found in a traversal
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
           echo "${paths["$lib"]}"
           dont_print["$lib"]=1
           traverse_deps "${paths["$lib"]}"
        fi
    done
}

for libpath in "${tops[@]}"
do
    traverse_deps $libpath
done
