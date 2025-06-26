#!/bin/bash

populate_variables() {
    declare -g SERVER_LATEST_BACKUP_FILE_PATH="$1" # Tham số 1: Đường dẫn file backup
    declare -g MAX_SIZE_GB="$2"                     # Tham số 2: Kích thước tối đa (GB)

    declare -g MAX_SIZE_BYTES=$((MAX_SIZE_GB * 1024 * 1024 * 1024))
}

function main() {
    set -euo pipefail

    populate_variables "$@"

    if [[ -z "$SERVER_LATEST_BACKUP_FILE_PATH" ]]; then
        echo "Error: Backup file path is empty." >&2
        echo "use_self_hosted=false"
        exit 1
    fi

    if [[ ! -f "$SERVER_LATEST_BACKUP_FILE_PATH" ]]; then
        echo "Warning: Backup file not found at '$SERVER_LATEST_BACKUP_FILE_PATH'. Assuming self-hosted runner is not needed." >&2
        echo "use_self_hosted=false"
        exit 0
    fi

    remote_size=$(stat -c%s -- "$SERVER_LATEST_BACKUP_FILE_PATH" 2>/dev/null || echo 0)

    if [[ ! "$remote_size" =~ ^[0-9]+$ ]]; then
        echo "Error: Could not retrieve file size for '$SERVER_LATEST_BACKUP_FILE_PATH'." >&2
        echo "use_self_hosted=false"
        exit 1
    fi

    if (( remote_size > MAX_SIZE_BYTES )); then
        echo "use_self_hosted=true"
    else
        echo "use_self_hosted=false"
    fi
}

main "$@"