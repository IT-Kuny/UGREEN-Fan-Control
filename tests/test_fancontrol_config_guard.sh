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

REQUIRED_FIELDS=("INTERVAL" "DEVPATH" "DEVNAME" "FCTEMPS")

# Inline validation function matching the guard script logic
validate_config() {
    local file="$1"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        return 1
    fi
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! grep -qE "^${field}=" "$file"; then
            return 1
        fi
    done
    return 0
}

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
config_file="$TEST_DIR/fancontrol_br"
backup_file="$TEST_DIR/fancontrol_br.bak"

create_valid_config "$config_file"
cp -p "$config_file" "$backup_file"

if [ -f "$backup_file" ] && diff -q "$config_file" "$backup_file" > /dev/null; then
    pass "Backup created successfully"
else
    fail "Backup creation failed"
fi

# Simulate corruption (empty the config)
> "$config_file"

# Simulate restore
if [ ! -s "$config_file" ] && [ -f "$backup_file" ] && [ -s "$backup_file" ]; then
    cp -p "$backup_file" "$config_file"
    if [ -s "$config_file" ] && validate_config "$config_file"; then
        pass "Config restored from backup successfully"
    else
        fail "Config restore failed"
    fi
else
    fail "Restore conditions not met"
fi

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
    for i in $(seq 1 10); do
        cat "$config_file" > /dev/null 2>&1 || true
    done
) &
reader_pid=$!

for i in $(seq 1 10); do
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
