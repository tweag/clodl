# shellcheck shell=bash
HERE="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../common/routines.sh"

OTOOL_ARCH="-arch x86_64"

# otool_with_kill PID ARGS...
#
# Like "otool ARGS..." but kills PID if otool fails
otool_with_kill() {
	local PID="$1"
	shift
	local RC=0
	otool "$@" || RC=$?
	[[ $RC == 0 ]] || kill "$PID"
	exit $RC
}

# Produces the library name used by needed_libs
#
# Requires otool to be on the path.
library_name() {
    local arg=$1
    local name
    name=$(otool_with_kill $$ $OTOOL_ARCH -D "$arg" | tail -n +2)
    # if otool -D yields no output, we assume this is a binary without
    # and install name
    if [[ z"$name" == z ]]
    then
        name=$arg
    fi
    echo -n "$name"
}

# needed_libs FILES
#
# Produces the names of the libraries needed by the given shared libraries.
#
# The output is of the form
#
#     lib1 <needed libraries ...>
#     lib2 <...>
#     ...
#
# suitable for assignment of associative arrays.
# 
# Requires otool to be on the path.
needed_libs() {
    TAB=$'\t'

    local arg
    for arg in "$@"
    do
        # skip excluded libraries
        [ ${excluded_libs["${arg##*/}"]+defined} ] && continue || true

        local name
        name=$(otool_with_kill $$ $OTOOL_ARCH -D "$arg" | tail -n +2)
        offset=3
        # if otool -D yields no output, we assume this is a binary without
        # and install name
        if [[ z"$name" == z ]]
        then
            name=$arg
            offset=2
        fi
        echo -n "$name"; echo -n " "; otool $OTOOL_ARCH -L "$arg" | tail -n +$offset | sed "s/$TAB.*\/\(.*\) (.*)/\\1/" | xargs echo
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
    local name
    name=$(otool_with_kill $$ $OTOOL_ARCH -D "$ARG" | tail -n +2)
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
    for lib in $(otool_with_kill $$ $OTOOL_ARCH -L "$ARG" | tail -n +$offset | sed "s/$TAB\(.*\) (.*)/'\\1'/" | grep -e "^'/" | xargs echo -n)
    do
        if [ ! ${excluded_libs["${lib##*/}"]+defined} ]
        then
            install_name_tool -change "$lib" "@loader_path/${lib##*/}" "$DEST/$FILE_NAME"
        fi
    done
    for lib in $(otool_with_kill $$ $OTOOL_ARCH -L "$ARG" | tail -n +$offset | sed "s/$TAB\(.*\) (.*)/'\\1'/" | grep -v -e "^'/" | xargs echo -n)
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
    DYLD_PRINT_LIBRARIES=1 $(rlocation io_tweag_clodl/loader) "$@" 2>&1 | sed "s/dyld: loaded: \(<[^ ]*> \)\?//" | sort -u
}
