# shellcheck shell=bash

# tops contains the shared libraries and executables to analyze.
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
            tops+=("$arg")
        else
            excludes+=("$arg")
        fi
    done
}

# excluded_libraries lib1 lib2 lib3 ...
# Prints the excluded libraries in stdout that match any
# of the regexes in excludes.
excluded_libraries() {
    if [ ${#excludes[@]} -gt 0 ]
    then
        printf '%s\n' "$@" \
          | grep -E $(printf ' -e %s' "${excludes[@]}")
    fi
}

declare -A excluded_libs

# compute_excluded_libs path/to/lib1 path/to/lib2 ...
#
# Fills the excluded libs array with the file names of
# libraries which have been excluded.
compute_excluded_libs() {
    for lib in $(excluded_libraries "$@")
    do
        excluded_libs["${lib##*/}"]=1
    done
}
