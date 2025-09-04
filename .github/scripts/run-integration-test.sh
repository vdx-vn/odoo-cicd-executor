#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

populate_variables() {
    declare -g received_backup_file_path=$1
    declare -g commit_hash=$2
    declare -g ignore_test=$3
    declare -g odoo_container_store_backup_folder="/tmp/odoo/restore"
    declare -g extracted_backup_folder_name="odoo"

    # Fetch config values with fallback to default if not set
    declare -g db_host=$(get_config_value "db_host" || echo 'db')
    declare -g db_port=$(get_config_value "db_port" || echo '5432')
    declare -g db_user=$(get_config_value "db_user" || echo 'odoo')
    declare -g db_password=$(get_config_value "db_password" || echo 'odoo')
    declare -g data_dir=$(get_config_value "data_dir" || echo '/var/lib/odoo')
}

function update_config_file {
    sed -i "s/^\s*command\s*.*//g" $ODOO_CONFIG_FILE
    sed -i "s/^\s*db_name\s*.*//g" $ODOO_CONFIG_FILE
}

get_config_value() {
    param=$1
    grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_CONFIG_FILE"
    if [[ $? == 0 ]]; then
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_CONFIG_FILE" | cut -d " " -f3 | sed 's/["\n\r]//g')
    fi
    echo "$value"
}

function update_config_file_after_restoration {
    # Test only the changed add-ons found in the commit.
    custom_addons=$(get_list_changed_addons_should_run_test "$ODOO_ADDONS_PATH" "$commit_hash" "$ignore_test")
    tagged_custom_addons=$(echo $custom_addons | sed "s/,/,\//g" | sed "s/^/\//")
    sed -i "s/^\s*command\s*.*//g" $ODOO_CONFIG_FILE
    echo -en "\ncommand = \
    --stop-after-init \
    --workers 0 \
    --database $ODOO_TEST_DATABASE_NAME \
    --logfile $ODOO_LOG_FILE_CONTAINER \
    --log-level error \
    --update $custom_addons \
    --init $custom_addons \
    --test-tags ${tagged_custom_addons}\n" >>$ODOO_CONFIG_FILE
}

copy_backup() {
    odoo_container_id=$(get_odoo_container_id)
    received_backup_file_name=$(basename $received_backup_file_path)
    docker_odoo_exec "mkdir -p $odoo_container_store_backup_folder"
    docker cp "$received_backup_file_path" $odoo_container_id:$odoo_container_store_backup_folder
    docker_odoo_exec "cd $odoo_container_store_backup_folder && unzip -qo $received_backup_file_name"
}

config_psql_without_password() {
    pgpass_path="~/.pgpass"
    docker_odoo_exec "touch $pgpass_path ; echo $db_host:$db_port:postgres:$db_user:$db_password > $pgpass_path ; chmod 0600 $pgpass_path"
    docker_odoo_exec "echo '' >> $pgpass_path"
    docker_odoo_exec "echo $db_host:$db_port:\"$ODOO_TEST_DATABASE_NAME\":$db_user:$db_password >> $pgpass_path"
}

restart_instance() {
    update_config_file_after_restoration
    docker restart $(get_odoo_container_id)
}

create_empty_db() {
    docker_odoo_exec "psql -h \"$db_host\" -U $db_user postgres -c \"CREATE DATABASE ${ODOO_TEST_DATABASE_NAME} ENCODING 'UNICODE' LC_COLLATE 'C' TEMPLATE template0;\""
}

restore_db() {
    sql_dump_path="${odoo_container_store_backup_folder}/dump.sql"
    docker_odoo_exec "psql -h \"$db_host\" -U $db_user $ODOO_TEST_DATABASE_NAME < $sql_dump_path >/dev/null"
}

restore_filestore() {
    backup_filestore_path="${odoo_container_store_backup_folder}/filestore"
    filestore_path="$data_dir/filestore"
    docker_odoo_exec "mkdir -p $filestore_path;cp -r $backup_filestore_path $filestore_path/$ODOO_TEST_DATABASE_NAME;"
}

restore_backup() {
    copy_backup
    config_psql_without_password
    create_empty_db
    restore_db
    restore_filestore
    restart_instance
}

# ===================== CLEANUP FUNCTIONS ==========================
function cleanup_after_integration_test {
    show_separator "Start cleanup after integration test"

    odoo_container_id=$(get_odoo_container_id)
    if [ -n "$odoo_container_id" ]; then
        echo "[CLEANUP] Removing Odoo container: $odoo_container_id"
        docker rm -f "$odoo_container_id" >/dev/null 2>&1 || true
    fi

    db_container_id=$(docker ps -aq --filter "name=db")
    if [ -n "$db_container_id" ]; then
        echo "[CLEANUP] Removing DB container: $db_container_id"
        docker rm -f $db_container_id >/dev/null 2>&1 || true
    fi

    echo "[CLEANUP] Pruning exited/dangling containers"
    docker container prune -f >/dev/null 2>&1 || true

    echo "[CLEANUP] Removing unused Docker images"
    docker image prune -a -f >/dev/null 2>&1 || true

    DANGLING_VOLUMES=$(docker volume ls -f "dangling=true" -q)
    if [ -n "$DANGLING_VOLUMES" ]; then
        echo "[CLEANUP] Removing dangling volumes"
        docker volume rm $DANGLING_VOLUMES >/dev/null 2>&1 || true
    fi

    TEST_NETWORKS=$(docker network ls --filter "dangling=true" -q)
    if [ -n "$TEST_NETWORKS" ]; then
        echo "[CLEANUP] Removing dangling networks"
        docker network rm $TEST_NETWORKS >/dev/null 2>&1 || true
    fi

    if [ -n "$received_backup_file_path" ] && [ -f "$received_backup_file_path" ]; then
        echo "[CLEANUP] Removing temporary backup file: $received_backup_file_path"
        sudo rm -f "$received_backup_file_path"
    fi

    if [ -n "$ODOO_LOG_FILE_HOST" ] && [ -f "$ODOO_LOG_FILE_HOST" ]; then
        echo "[CLEANUP] Removing Odoo log file: $ODOO_LOG_FILE_HOST"
        sudo rm -f "$ODOO_LOG_FILE_HOST"
    fi

    if [ -d "/tmp/odoo/restore" ] && [ -w "/tmp/odoo/restore" ]; then
        echo "[CLEANUP] Removing /tmp/odoo/restore"
        sudo rm -rf /tmp/odoo/restore
    else
        echo "[CLEANUP] Skip /tmp/odoo/restore (no permission)"
    fi

    if [ -d "/tmp/odoo/backup" ] && [ -w "/tmp/odoo/backup" ]; then
        echo "[CLEANUP] Removing /tmp/odoo/backup"
        sudo rm -rf /tmp/odoo/backup
    else
        echo "[CLEANUP] Skip /tmp/odoo/backup (no permission)"
    fi

    if [ -n "$GITHUB_WORKSPACE" ] && [ -d "$GITHUB_WORKSPACE" ]; then
        echo "[CLEANUP] Removing all files in workspace: $GITHUB_WORKSPACE"
        sudo rm -rf "$GITHUB_WORKSPACE"/* || echo "[CLEANUP] Skip workspace (no permission)"
    fi

    show_separator "Cleanup finished"
}

function main() {
    populate_variables "$@"
    trap cleanup_after_integration_test EXIT

    update_config_file
    start_containers
    restore_backup
    wait_until_odoo_shutdown

    failed_message=$(
        cat <<EOF
❌🐞❌ Integration Test: The <${PR_URL}|PR #${PR_NUMBER}> was merged but the database test failed!
Please take a look at the attached log file🔬
EOF
    )
#     telegram_failed_message=$(
#         cat <<EOF
# ❌🐞❌ Integration Test: The [PR \\#$PR_NUMBER]($PR_URL) was merged but the database test failed\\!🐞
# Please take a look at the attached log file🔬
# EOF
#     )

    telegram_failed_message=$(create_telegram_failed_message "Integration Test" "$PR_NUMBER" "$PR_URL" "$commit_author" "$sad_emojis")

    analyze_log_file "$failed_message" "$telegram_failed_message"
}

main "$@"
