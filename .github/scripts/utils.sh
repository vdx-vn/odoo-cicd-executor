#!/bin/bash

function get_cicd_config_for_odoo_addon {
    addon_name=$1
    option=$2
    echo $(jq ".addons.${addon_name}.${option}" $CICD_ODOO_OPTIONS)
}

function get_config_value {
    param=$1
    grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_CONFIG_FILE"
    if [[ $? == 0 ]]; then
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_CONFIG_FILE" | cut -d " " -f3 | sed 's/["\n\r]//g')
    fi
    echo "$value"
}

function get_list_addons {
    addons_path=$1
    addons=
    res=$(find "$addons_path" -maxdepth 2 -mindepth 2 -type f -name "__manifest__.py" -exec dirname {} \;)
    for dr in $res; do
        addon_name=$(basename $dr)
        if [[ -z $addons ]]; then
            addons="$addon_name"
        else
            addons="$addons,$addon_name"
        fi
    done

    echo $addons
}

function get_effect_addons_name {
    # get addons name from changed files to update only these addons
    # instead of update all addons
    addons_path=$1
    commit_hash=$2
    cd $addons_path
    changed_files=$(git show --name-only --pretty="" "$commit_hash")
    addons_name=$(echo "$changed_files" | awk -F/ '{if ($1 !~ /^\./) print $1}' | sort -u | paste -sd ',' -)
    echo $addons_name
}

function get_list_addons_filtered_by_config_option {
    addons_path=$1
    option_name=$2
    option_value=$3
    addons=
    full_list_addons=$(get_list_addons $addons_path)
    if [[ -n $full_list_addons ]]; then
        backup_IFS=$IFS
        IFS=","
        for addon_name in $full_list_addons; do
            origin_option_value=$(get_cicd_config_for_odoo_addon "$addon_name" "$option_name")
            if [[ "$origin_option_value" == "$option_value" ]]; then
                if [[ -z $addons ]]; then
                    addons=$addon_name
                else
                    addons="$addons;$addon_name"
                fi
            fi
        done
        IFS=$backup_IFS
    fi
    addons=$(echo $addons | sed "s/;/,/g")
    echo $addons
}

function get_list_addons_should_run_test {
    addons_path=$1
    echo $(get_list_addons_filtered_by_config_option $addons_path "ignore_test" "null")
}

function get_list_addons_ignore_demo_data {
    addons_path=$1
    echo $(get_list_addons_filtered_by_config_option $addons_path "ignore_demo" "true")
}

function get_list_addons_ignored_test {
    addons_ignored_test=
    addons=$(get_list_addons $1)
    if [[ -n $addons ]]; then
        IFS=','
        read -ra elements <<<"$addons"
        for addon_name in "${elements[@]}"; do
            ignore_test=$(get_cicd_config_for_odoo_addon "$addon_name" "ignore_test")
            if [[ $ignore_test == "null" ]]; then
                addons_ignored_test="$addons_ignored_test,$addon_name"
            fi
        done
    fi
    echo $addons_ignored_test
}

function wait_until_odoo_shutdown {
    # because we put --stop-after-init option to odoo command
    # so after Odoo has finished installing and runing test cases
    # It will shutdown automatically
    # we just need to wait until odoo container is stopped (status=exited)
    # and we can start analyze the log file
    maximum_waiting_time=3600 # maximum wait time is 60', in case if there is an unexpected problem
    odoo_container_id=$(get_odoo_container_id)
    if [ -z $odoo_container_id ]; then
        echo "Can't find the Odoo container, stop pipeline immediately!"
        exit 1
    fi
    sleep_block=5
    total_waited_time=0
    while (($total_waited_time <= $maximum_waiting_time)); do
        container_exited_id=$(docker ps -q --filter "id=$odoo_container_id" --filter "status=exited")
        if [[ -n $container_exited_id ]]; then break; fi
        total_waited_time=$((total_waited_time + sleep_block))
        sleep $sleep_block
    done
}

# declare all useful functions here
function show_separator {
    x="==============================================="
    separator=($x $x "$1" $x $x)
    printf "%s\n" "${separator[@]}"
}

function get_odoo_container_id {
    docker ps -q -a | xargs docker inspect --format '{{.Id}} {{.Config.Image}}' | awk -v img="${ODOO_IMAGE_TAG}" '$2 == img {print $1}'
}

function docker_odoo_exec {
    odoo_container_id=$(get_odoo_container_id)
    docker exec $odoo_container_id sh -c "$@"
}

function analyze_log_file {
    failed_message=$1
    success_message=$2
    [ -z $success_message ] && success_message="We passed all test cases, well done!"

    [ -f ${ODOO_LOG_FILE_HOST} ]
    if [ $? -ne 0 ]; then
        show_separator "$success_message"
        return 0
    fi

    grep -m 1 -P '^[0-9-\s:,]+(ERROR|CRITICAL)' $ODOO_LOG_FILE_HOST >/dev/null 2>&1
    error_exist=$?
    if [ $error_exist -eq 0 ]; then
        cat $ODOO_LOG_FILE_HOST
        send_file_telegram_default "$ODOO_LOG_FILE_HOST" "$failed_message"
        exit 1
    fi
    show_separator "$success_message"
}

function start_db_container() {
    docker run -d \
        -p 5432:5432 \
        --mount type=bind,source=$DOCKER_FOLDER/postgresql,target=/etc/postgresql \
        -e POSTGRES_PASSWORD=odoo -e POSTGRES_USER=odoo -e POSTGRES_DB=postgres \
        --name db \
        $DB_IMAGE_TAG \
        -c 'config_file=/etc/postgresql/postgresql.conf'
}

function start_odoo_container() {
    docker run -d \
        --mount type=bind,source=$ODOO_ADDONS_PATH,target=/mnt/custom-addons \
        --mount type=bind,source=$DOCKER_FOLDER/etc,target=/etc/odoo \
        --mount type=bind,source=$DOCKER_FOLDER/logs,target=/var/log/odoo \
        --link db:db \
        $ODOO_IMAGE_TAG
}

function start_containers() {
    start_db_container
    start_odoo_container
}

function create_private_keyfile_from_content() {
    content="$1"
    key_file_path="$2"
    mkdir -p $(dirname $key_file_path)
    touch $key_file_path && chmod 600 $key_file_path
    >$key_file_path
    echo "$content" >>$key_file_path
    echo $key_file_path
}

# ------------------ Telegram functions -------------------------
function send_file_telegram {
    bot_token=$1
    chat_id=$2
    file_path=$3
    caption=$4
    parse_mode=$5
    [ -z $parse_mode ] && parse_mode="MarkdownV2"

    response=$(curl --write-out '%{http_code}\n' -s -X POST "https://api.telegram.org/bot$bot_token/sendDocument" \
        -F "chat_id=$chat_id" \
        -F "document=@$file_path" \
        -F "caption=$caption" \
        -F "parse_mode=$parse_mode" \
        -F "disable_notification=true")
    status_code=$(echo $response | grep -oE "[0-9]+$")
    if [[ $status_code != "200" ]]; then
        echo "Can't send file to Telegram!"
        echo $response
    fi
}

function send_message_telegram {
    bot_token=$1
    chat_id=$2
    message=$3
    parse_mode=$4
    [ -z $parse_mode ] && parse_mode="MarkdownV2"

    response=$(curl --write-out '%{http_code}\n' -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
        -d "chat_id=$chat_id" \
        -d "text=$message" \
        -d "parse_mode=$parse_mode" \
        -d "disable_notification=true")
    status_code=$(echo $response | grep -oE "[0-9]+$")
    if [[ $status_code != "200" ]]; then
        echo "Can't send message to Telegram!"
        echo $response
    fi
}

function send_file_telegram_default {
    file_path=$1
    caption=$2
    send_file_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHANNEL_ID" "$file_path" "$caption"
}

function send_message_telegram_default {
    message=$1
    send_message_telegram "$TELEGRAM_TOKEN" "$TELEGRAM_CHANNEL_ID" "$message"
}
# ------------------ Telegram functions -------------------------

# fixme
# echo "params at utils ...???" "$@"

# if [ $# -gt 0 ]; then
#     is_exec_command=$1
#     function_name=$2
#     shift 2
#     if declare -f "$function_name" >/dev/null; then
#         if [ $is_exec_command == "exec" ]; then
#             "$function_name" "$@"
#         fi
#     fi
# fi
