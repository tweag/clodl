// This program loads any binaries or shared libraries given to it in
// the command line. It's only purpose is to offer a way to print the
// dependencies of the arguments with DYLD_PRINT_LIBRARIES
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char* argv[]) {
    for(int i=1;i<argc;i++) {
        void* h=dlopen(argv[i], RTLD_LAZY);
        if (!h)
          fprintf(stderr, "error loading %s: %s", argv[i], dlerror());
    }
    return 0;
}
