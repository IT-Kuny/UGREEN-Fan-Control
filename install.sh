#!/usr/bin/env bash
# UGREEN Fan Control - Installation Script
#
# This script automates the installation of the it87 kernel module via DKMS
# and configures the system so that fan control survives reboots.
#
# Usage: sudo ./install.sh
#
# What this script does:
#   1. Verifies required packages are available
#   2. Initializes and updates the it87 git submodule
#   3. Handles the BTF vmlinux issue if needed
#   4. Registers and installs the it87 module via DKMS
#   5. Configures the module to load automatically at boot
#   6. Creates a systemd drop-in for fancontrol to ensure proper start order
#
set -euo pipefail

# -- Colour helpers (fall back to plain text if not a terminal) ------------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -- Root check ------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use sudo)."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IT87_DIR="${SCRIPT_DIR}/it87"

# -- Dependency check ------------------------------------------------------
MISSING_DEPS=()
for cmd in gcc make dkms depmod modprobe git; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_DEPS+=("$cmd")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    error "Missing required commands: ${MISSING_DEPS[*]}"
    echo "Please install the following packages first:"
    echo "  Fedora : sudo dnf install gcc make dkms dwarves kernel-headers kernel-devel git"
    echo "  Debian : sudo apt install gcc make dkms dwarves linux-headers-\$(uname -r) git"
    echo "  Arch   : sudo pacman -S gcc make dkms linux-headers git"
    exit 1
fi

# -- Initialise / update the it87 submodule --------------------------------
info "Initialising it87 submodule ..."
cd "$SCRIPT_DIR"
git submodule update --init --recursive

if [ ! -f "${IT87_DIR}/Makefile" ]; then
    error "it87 submodule is empty. Please check your network and retry."
    exit 1
fi

# -- Handle BTF vmlinux issue (common on Fedora) ---------------------------
KVER="$(uname -r)"
BUILD_DIR="/usr/lib/modules/${KVER}/build"
if [ -d "$BUILD_DIR" ] && [ ! -e "${BUILD_DIR}/vmlinux" ]; then
    if [ -e /sys/kernel/btf/vmlinux ]; then
        info "Copying BTF vmlinux to kernel build directory ..."
        cp /sys/kernel/btf/vmlinux "${BUILD_DIR}/vmlinux"
    fi
fi

# -- Build and install via DKMS --------------------------------------------
info "Installing it87 module via DKMS ..."
cd "$IT87_DIR"

# Clean any leftover build artifacts
make clean 2>/dev/null || true

# The Makefile's 'dkms' target handles:
#   - Copying sources to /usr/src/it87-<version>
#   - dkms add / build / install
#   - modprobe it87
make dkms

info "DKMS module installed successfully."

# -- Ensure module loads on every boot -------------------------------------
MODULES_LOAD_DIR="/etc/modules-load.d"
MODULES_LOAD_CONF="${MODULES_LOAD_DIR}/it87.conf"

if [ ! -d "$MODULES_LOAD_DIR" ]; then
    mkdir -p "$MODULES_LOAD_DIR"
fi

if [ ! -f "$MODULES_LOAD_CONF" ] || ! grep -q '^it87$' "$MODULES_LOAD_CONF" 2>/dev/null; then
    info "Configuring it87 module to load at boot ..."
    echo "it87" > "$MODULES_LOAD_CONF"
fi

# -- Add systemd drop-in for fancontrol ordering ---------------------------
# Problem: fancontrol.service may start before the it87 module is loaded and
# before hwmon devices are available.  This causes it to fail with errors
# about missing /sys/class/hwmon paths.
#
# Solution: Add a drop-in that:
#   - Waits for systemd-modules-load.service (loads /etc/modules-load.d/*)
#   - Polls for hwmon devices to appear (up to 30 s) before starting
#   - Automatically restarts the service on failure
DROPIN_DIR="/etc/systemd/system/fancontrol.service.d"
DROPIN_CONF="${DROPIN_DIR}/10-wait-for-hwmon.conf"

info "Creating systemd drop-in for fancontrol ..."
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_CONF" <<'DROPINEOF'
# Drop-in for fancontrol.service
# Ensures the it87 kernel module is loaded and hwmon devices are available
# before fancontrol starts.  Also adds restart-on-failure so transient
# enumeration delays do not leave the system without fan control.
[Unit]
After=systemd-modules-load.service
Wants=systemd-modules-load.service

[Service]
# Poll for hwmon devices to appear (up to 30 seconds) before starting.
# This is more robust than a fixed sleep because it adapts to both fast
# and slow hardware enumeration.
ExecStartPre=/bin/bash -c 'for i in $(seq 1 30); do if ls /sys/class/hwmon/hwmon*/name 1>/dev/null 2>&1; then exit 0; fi; sleep 1; done; echo "Timed out waiting for hwmon devices"; exit 1'
Restart=on-failure
RestartSec=5
DROPINEOF

systemctl daemon-reload
info "Systemd drop-in created at ${DROPIN_CONF}"

# -- Summary ---------------------------------------------------------------
echo ""
info "Installation complete!"
echo ""
echo "Next steps:"
echo "  1) Run 'sudo sensors-detect' and answer Y to all questions"
echo "  2) Run 'sudo pwmconfig' to map fans to channels"
echo "     (this creates /etc/fancontrol)"
echo "  3) Enable the fancontrol service:"
echo "     systemctl enable --now fancontrol"
echo ""
echo "The it87 module will now load automatically on every boot, and"
echo "the fancontrol service will wait for sensor hardware before starting."
