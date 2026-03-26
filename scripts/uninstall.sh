#!/bin/bash
#
# uninstall.sh
#
# Removes the UGREEN Fan Control setup including DKMS driver,
# systemd services, and modprobe configuration.
# Does NOT remove the fancontrol configuration file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IT87_DIR="$REPO_DIR/it87"

log() {
    echo "[uninstall] $*"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "[uninstall] ERROR: This script must be run as root (use sudo)" >&2
        exit 1
    fi
}

check_root

log "Stopping services..."
systemctl stop fancontrol 2>/dev/null || true
systemctl stop fancontrol-config-guard 2>/dev/null || true
systemctl stop it87-driver 2>/dev/null || true

log "Disabling services..."
systemctl disable fancontrol-config-guard.service 2>/dev/null || true
systemctl disable it87-driver.service 2>/dev/null || true

log "Removing systemd files..."
rm -f /etc/systemd/system/it87-driver.service
rm -f /etc/systemd/system/fancontrol-config-guard.service
rm -rf /etc/systemd/system/fancontrol.service.d
systemctl daemon-reload

log "Removing modprobe configuration..."
rm -f /etc/modprobe.d/it87.conf
rm -f /etc/modules-load.d/it87.conf

log "Removing config guard script..."
rm -f /usr/local/sbin/fancontrol-config-guard.sh

log "Removing DKMS driver..."
if cd "$IT87_DIR" 2>/dev/null; then
    make dkms_clean 2>/dev/null || true
fi

log "Unloading module..."
modprobe -r it87 2>/dev/null || true

log ""
log "Uninstallation complete."
log "Note: /etc/fancontrol and /etc/fancontrol.d/ were preserved."
log "Remove them manually if no longer needed."
