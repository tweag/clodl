HERE="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $HERE/../common/routines.sh

OTOOL_ARCH="-arch x86_64"

# needed_libs FILES
#
# Produces the names of the libraries needed by the given shared libraries.
#
# The output is of the form [lib1]='needed libraries' [lib2]=...
# suitable for assignment of associative arrays.
# 
# Requires otool to be on the path.
needed_libs() {
    TAB=$'\t'

    local arg
    for arg in "$@"
    do
        name=$(otool $OTOOL_ARCH -D "$arg" | tail -n +2)
        offset=3
        # if otool -D yields no output, we assume this is a binary without
        # and install name
        if [[ z"$name" == z ]]
        then
            name=$arg
            offset=2
        fi
        echo $name $(otool $OTOOL_ARCH -L "$arg" | tail -n +$offset | sed "s/$TAB.*\/\(.*\) (.*)/\\1/" | xargs echo -n)
    done
}

# tops contains the libraries to analyze.
# excludes contains the regexes provided by the user.
declare -a tops excludes=()

# Populates tops and excludes with the arguments of
# the invocation.
read_args() {
    local found_ddash=0
    local arg
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
    local lib
    for lib in $(excluded_libraries "$@")
    do
        excluded_libs["${lib##*/}"]=1
    done
}

# copy-lib FILE DEST
#
# Copies the shared library or executable to DEST,
# changing its dependencies to load from the same folder as the library.
#
# Dependencies that match regexes in excluded_libs aren't modified
#
# Requires otool and install_name_tool to be on the path.
copy_lib() {

    local TAB=$'\t'
    local ARG="$1"
    local DEST="$2"

    local FILE_NAME="${ARG##*/}"
    cp "$ARG" "$DEST"
    chmod u+w "$DEST/$FILE_NAME"
    local name=$(otool $OTOOL_ARCH -D "$ARG" | tail -n +2)
    local offset=3
    # if otool -D yields no output, we assume this is a binary without
    # and install name
    if [[ z"$name" == z ]]
    then
        name=$ARG
        offset=2
    else
        install_name_tool -id "@loader_path/$FILE_NAME" "$DEST/$FILE_NAME"
    fi

    local lib
    # First change absolute paths and then the others. This is an attempt to
    # make room early to change other load commands.
    for lib in $(otool $OTOOL_ARCH -L "$ARG" | tail -n +$offset | sed "s/$TAB\(.*\) (.*)/'\\1'/" | grep -e "^'/" | xargs echo -n)
    do
        if [ ! ${excluded_libs["${lib##*/}"]+defined} ]
        then
            install_name_tool -change "$lib" "@loader_path/${lib##*/}" "$DEST/$FILE_NAME"
        fi
    done
    for lib in $(otool $OTOOL_ARCH -L "$ARG" | tail -n +$offset | sed "s/$TAB\(.*\) (.*)/'\\1'/" | grep -v -e "^'/" | xargs echo -n)
    do
        if [ ! ${excluded_libs["${lib##*/}"]+defined} ]
        then
            install_name_tool -change "$lib" "@loader_path/${lib##*/}" "$DEST/$FILE_NAME"
        fi
    done
}

#
# ldd.sh FILES
#
# Print the paths to dependencies needed by the given executables or shared libraries.
#
collect_lib_paths() {
    DYLD_PRINT_LIBRARIES=1 $(rlocation io_tweag_clodl/loader) "$@" 2>&1 | sed "s/dyld: loaded: //" | sort | uniq
}
