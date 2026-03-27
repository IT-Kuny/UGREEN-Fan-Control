#!/bin/bash
#
# fancontrol-config-guard.sh
#
# Backs up the fancontrol configuration file before the fancontrol service
# starts and restores it if the configuration is missing or corrupted.
# This prevents loss of fan control settings due to race conditions,
# unexpected shutdowns, or device path changes.

set -euo pipefail

CONFIG_FILE="/etc/fancontrol"
BACKUP_DIR="/etc/fancontrol.d"
BACKUP_FILE="${BACKUP_DIR}/fancontrol.bak"

log() {
    echo "[fancontrol-config-guard] $*"
}

# Validate that a fancontrol config file has the minimum required fields
validate_config() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    if [ ! -s "$file" ]; then
        log "Config file is empty: $file"
        return 1
    fi

    # Check for minimum required configuration fields
    local required_fields=("INTERVAL" "DEVPATH" "DEVNAME" "FCTEMPS")
    for field in "${required_fields[@]}"; do
        if ! grep -qE "^${field}=" "$file"; then
            log "Missing required field: $field in $file"
            return 1
        fi
    done

    return 0
}

# Create a backup of the current configuration
backup_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "No config file to back up"
        return 1
    fi

    mkdir -p "$BACKUP_DIR"

    if validate_config "$CONFIG_FILE"; then
        cp -p "$CONFIG_FILE" "$BACKUP_FILE"
        log "Configuration backed up to $BACKUP_FILE"
        return 0
    else
        log "Current config is invalid, skipping backup"
        return 1
    fi
}

# Restore config from backup if current config is missing or invalid
restore_config() {
    if validate_config "$CONFIG_FILE"; then
        log "Current configuration is valid"
        return 0
    fi

    if [ -f "$BACKUP_FILE" ] && validate_config "$BACKUP_FILE"; then
        log "Restoring configuration from backup"
        cp -p "$BACKUP_FILE" "$CONFIG_FILE"
        log "Configuration restored successfully"
        return 0
    fi

    log "ERROR: No valid configuration or backup found"
    log "Please run 'sudo pwmconfig' to create a new configuration"
    return 1
}

# Update device paths in configuration if they have changed after reboot
update_device_paths() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    local devpath_line
    devpath_line=$(grep -E "^DEVPATH=" "$CONFIG_FILE" || true)
    if [ -z "$devpath_line" ]; then
        return 1
    fi

    local devname_line
    devname_line=$(grep -E "^DEVNAME=" "$CONFIG_FILE" || true)
    if [ -z "$devname_line" ]; then
        return 1
    fi

    local needs_update=0
    local new_devpath="DEVPATH="
    local first=1

    # Parse DEVPATH entries and check if device paths are still valid
    local entries
    entries=$(echo "${devpath_line#DEVPATH=}" | tr ' ' '\n')
    for entry in $entries; do
        local hwmon_name="${entry%%=*}"
        local old_path="${entry#*=}"

        # Find the current path for this hwmon device by matching DEVNAME
        local dev_name=""
        local devname_entries
        devname_entries=$(echo "${devname_line#DEVNAME=}" | tr ' ' '\n')
        for dentry in $devname_entries; do
            local dname="${dentry%%=*}"
            if [ "$dname" = "$hwmon_name" ]; then
                dev_name="${dentry#*=}"
                break
            fi
        done

        if [ -z "$dev_name" ]; then
            # Keep the old path if we can't find the device name
            if [ "$first" -eq 0 ]; then
                new_devpath="$new_devpath "
            fi
            new_devpath="$new_devpath$entry"
            first=0
            continue
        fi

        # Search for the device by name in current hwmon devices.
        # DEVNAME from pwmconfig includes the bus/address suffix (e.g.
        # "it8613-isa-0a30"), while the hwmon name file often contains
        # only the driver name (e.g. "it8613").  We normalise both sides
        # by stripping everything from the first '-' onward so that a
        # prefix match succeeds even when the suffixes differ.
        local found_path=""
        local dev_name_prefix="${dev_name%%-*}"
        for hwmon_dir in /sys/class/hwmon/hwmon*; do
            if [ -f "$hwmon_dir/name" ]; then
                local current_name
                current_name=$(cat "$hwmon_dir/name" 2>/dev/null || true)
                local current_prefix="${current_name%%-*}"
                if [ "$current_prefix" = "$dev_name_prefix" ]; then
                    local current_path
                    current_path=$(basename "$hwmon_dir")
                    found_path="$current_path"
                    break
                fi
            fi
        done

        if [ -n "$found_path" ] && [ "$found_path" != "$old_path" ]; then
            log "Device path changed for $hwmon_name: $old_path -> $found_path"
            needs_update=1

            # Update the DEVPATH entry for this hwmon device
            if [ "$first" -eq 0 ]; then
                new_devpath="$new_devpath "
            fi
            new_devpath="$new_devpath${hwmon_name}=${found_path}"
        else
            if [ "$first" -eq 0 ]; then
                new_devpath="$new_devpath "
            fi
            new_devpath="$new_devpath$entry"
        fi
        first=0
    done

    if [ "$needs_update" -eq 1 ]; then
        log "Updating device paths in configuration"
        # Create a backup before modifying
        backup_config
        # Update DEVPATH in a temp file and then atomically replace
        local tmpfile
        tmpfile=$(mktemp "${CONFIG_FILE}.XXXXXX")
        # Ensure the temporary file inherits permissions, ownership, and
        # (where supported) SELinux context from the original config before
        # it is moved into place. This avoids changing attributes that
        # services or security policies may rely on.
        if [ -e "$CONFIG_FILE" ]; then
            # Best-effort: ignore failures on systems lacking these utilities/options.
            chown --reference="$CONFIG_FILE" "$tmpfile" 2>/dev/null || true
            chmod --reference="$CONFIG_FILE" "$tmpfile" 2>/dev/null || true
            if command -v chcon >/dev/null 2>&1; then
                chcon --reference="$CONFIG_FILE" "$tmpfile" 2>/dev/null || true
            fi
        fi
        sed "s|^DEVPATH=.*|${new_devpath}|" "$CONFIG_FILE" > "$tmpfile"
        mv "$tmpfile" "$CONFIG_FILE"
        log "Device paths updated successfully"
    else
        log "Device paths are up to date"
    fi
}

# Only run main logic when executed directly, not when sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-guard}" in
        backup)
            backup_config
            ;;
        restore)
            restore_config
            ;;
        update-paths)
            update_device_paths
            ;;
        guard)
            # Default action: restore if needed, update paths, then backup
            restore_config
            update_device_paths
            backup_config
            ;;
        validate)
            if validate_config "$CONFIG_FILE"; then
                log "Configuration is valid"
                exit 0
            else
                log "Configuration is INVALID"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {backup|restore|update-paths|guard|validate}"
            exit 1
            ;;
    esac
fi
