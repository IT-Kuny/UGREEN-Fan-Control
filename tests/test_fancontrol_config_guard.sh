#!/bin/bash
#
# test_fancontrol_config_guard.sh
#
# Tests for the fancontrol-config-guard.sh script.
# These tests use a temporary directory to simulate /etc/fancontrol
# without requiring root or affecting the real system.

set -euo pipefail

PASS=0
FAIL=0
TEST_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

log_test() {
    echo "[TEST] $*"
}

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

# Create a valid test config
create_valid_config() {
    local file="$1"
    cat > "$file" << 'EOF'
INTERVAL=10
DEVPATH=hwmon2=hwmon2 hwmon3=hwmon3
DEVNAME=hwmon2=it8613-isa-0a30 hwmon3=acpitz-acpi-0
FCTEMPS=hwmon2/pwm3=hwmon3/temp1_input
MINTEMP=hwmon2/pwm3=22
MAXTEMP=hwmon2/pwm3=60
MINSTART=hwmon2/pwm3=105
MINSTOP=hwmon2/pwm3=26
MINPWM=hwmon2/pwm3=24
MAXPWM=hwmon2/pwm3=255
AVERAGE=hwmon2/pwm3=1
EOF
}

# Create an invalid config (missing required fields)
create_invalid_config() {
    local file="$1"
    cat > "$file" << 'EOF'
INTERVAL=10
MINTEMP=hwmon2/pwm3=22
EOF
}

# Source the real fancontrol-config-guard script so tests exercise the
# production implementation of validate_config/backup/restore logic.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/scripts/fancontrol-config-guard.sh"

# Override config paths to use test directory
CONFIG_FILE="$TEST_DIR/fancontrol"
BACKUP_DIR="$TEST_DIR/fancontrol.d"
BACKUP_FILE="${BACKUP_DIR}/fancontrol.bak"

# ---- Test: validate_config with valid config ----
log_test "validate_config with valid config"
config_file="$TEST_DIR/fancontrol"
create_valid_config "$config_file"
if validate_config "$config_file"; then
    pass "Valid config detected correctly"
else
    fail "Valid config not detected"
fi

# ---- Test: validate_config with invalid config ----
log_test "validate_config with invalid config (missing fields)"
config_file="$TEST_DIR/fancontrol_invalid"
create_invalid_config "$config_file"
if ! validate_config "$config_file"; then
    pass "Invalid config (missing fields) detected correctly"
else
    fail "Invalid config not detected"
fi

# ---- Test: validate_config with empty file ----
log_test "validate_config with empty file"
config_file="$TEST_DIR/fancontrol_empty"
touch "$config_file"
if ! validate_config "$config_file"; then
    pass "Empty config detected correctly"
else
    fail "Empty config not detected"
fi

# ---- Test: validate_config with missing file ----
log_test "validate_config with missing file"
config_file="$TEST_DIR/fancontrol_missing"
if ! validate_config "$config_file"; then
    pass "Missing config detected correctly"
else
    fail "Missing config not detected"
fi

# ---- Test: backup and restore logic ----
log_test "backup and restore"
CONFIG_FILE="$TEST_DIR/fancontrol_br"
BACKUP_DIR="$TEST_DIR/fancontrol_br.d"
BACKUP_FILE="${BACKUP_DIR}/fancontrol.bak"

create_valid_config "$CONFIG_FILE"
backup_config

if [ -f "$BACKUP_FILE" ] && diff -q "$CONFIG_FILE" "$BACKUP_FILE" > /dev/null; then
    pass "Backup created successfully"
else
    fail "Backup creation failed"
fi

# Simulate corruption (empty the config)
: > "$CONFIG_FILE"

# Restore using the real function
restore_config
if [ -s "$CONFIG_FILE" ] && validate_config "$CONFIG_FILE"; then
    pass "Config restored from backup successfully"
else
    fail "Config restore failed"
fi

# Reset config paths for remaining tests
CONFIG_FILE="$TEST_DIR/fancontrol"
BACKUP_DIR="$TEST_DIR/fancontrol.d"
BACKUP_FILE="${BACKUP_DIR}/fancontrol.bak"

# ---- Test: atomic file update (simulating device path update) ----
log_test "atomic file update simulation"
config_file="$TEST_DIR/fancontrol_atomic"
create_valid_config "$config_file"

# Simulate atomic update via temp file + mv
tmpfile=$(mktemp "${config_file}.XXXXXX")
sed "s|DEVPATH=hwmon2=hwmon2|DEVPATH=hwmon2=hwmon5|" "$config_file" > "$tmpfile"
mv "$tmpfile" "$config_file"

if grep -q "DEVPATH=hwmon2=hwmon5" "$config_file"; then
    pass "Atomic file update works correctly"
else
    fail "Atomic file update failed"
fi

# Verify no temp files left behind
remaining_tmp=$(find "$TEST_DIR" -name "fancontrol_atomic.*" 2>/dev/null | wc -l)
if [ "$remaining_tmp" -eq 0 ]; then
    pass "No temporary files left behind"
else
    fail "Temporary files remaining: $remaining_tmp"
fi

# ---- Test: concurrent access simulation ----
log_test "concurrent backup during read"
config_file="$TEST_DIR/fancontrol_concurrent"
backup_file="$TEST_DIR/fancontrol_concurrent.bak"
create_valid_config "$config_file"

# Simulate reading config while backup occurs
(
    for _ in $(seq 1 10); do
        cat "$config_file" > /dev/null 2>&1 || true
    done
) &
reader_pid=$!

for _ in $(seq 1 10); do
    cp -p "$config_file" "$backup_file" 2>/dev/null || true
done

wait "$reader_pid" 2>/dev/null || true

if [ -f "$config_file" ] && [ -s "$config_file" ] && validate_config "$config_file"; then
    pass "Config file intact after concurrent access"
else
    fail "Config file corrupted during concurrent access"
fi

# ---- Summary ----
echo ""
echo "============================================="
echo "  Test Results: $PASS passed, $FAIL failed"
echo "============================================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
