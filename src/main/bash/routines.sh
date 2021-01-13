HERE="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source $HERE/common/routines.sh

# Produces the names of the libraries needed by the given shared libraries.
#
# The output is of the form: lib1 'needed libraries' lib2 '...' ...
# suitable for assignment of associative arrays.
#
# Requires scanelf to be on the path.
needed_libs() {
    scanelf -qn "$@" | sed "s/\([^ ]*\)  \(.*\)/"\\2" "\\1"/;y/,/ /"
}

# copy-lib FILE DEST
#
# Copies the shared library or executable to DEST.
#
copy_lib() {
	cp "$@"
}

# collect_lib_paths FILES
#
# Print the paths to dependencies needed by the given executables or shared libraries.
#
collect_lib_paths() {

    libs_str=$(ldd "$@")

    # Fail if there are any missing libraries
    if echo "$libs_str" | grep 'not found' 1>&2
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
