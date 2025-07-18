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

function get_changed_files_and_folders_addons_name {
    # Retrieve the names of files and folders that have been changed in the specified commit
    addons_path=$1
    commit_hash=$2
    cd $addons_path
    changed_files=$(git show --name-only --pretty="" "$commit_hash")
    changed_folders_and_files=$(echo "$changed_files" | awk -F/ '{if ($1 !~ /^\./) print $1}' | sort -u | paste -sd ',' -)
    echo $changed_folders_and_files
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

function get_list_changed_addons {
    addons_path=$1
    commit_hash=$2
    changed_files_folders=$(get_changed_files_and_folders_addons_name ${addons_path} ${commit_hash})
    list_addons_name=$(get_list_addons ${addons_path})

    IFS=',' read -r -a array1 <<<"$changed_files_folders"
    IFS=',' read -r -a array2 <<<"$list_addons_name"

    # Find common folder name and join them by commas
    common_folders=""

    for folder1 in "${array1[@]}"; do
        for folder2 in "${array2[@]}"; do
            if [[ "$folder1" == "$folder2" ]]; then
                if [[ -z "$common_folders" ]]; then
                    common_folders="$folder1"
                else
                    common_folders="$common_folders,$folder1"
                fi
            fi
        done
    done

    echo $common_folders
}

function get_list_changed_addons_should_run_test {
    addons_path=$1
    commit_hash=$2
    ignore_test=$3
    list_changed_addons=$(get_list_changed_addons $addons_path $commit_hash)
    if [ -z "${list_changed_addons:-}" ]; then
        echo $(get_list_addons_should_run_test $addons_path $ignore_test)
        return 0
    fi
    # Convert strings to arrays
    IFS=',' read -r -a a_array <<<"$list_changed_addons"
    IFS=',' read -r -a b_array <<<"$ignore_test"

    # Create output variable
    result=()

    # Loop through elements of a and check if they're in b
    for item in "${a_array[@]}"; do
        found=false
        for b_item in "${b_array[@]}"; do
            if [[ "$item" == "$b_item" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            result+=("$item")
        fi
    done

    # Join result with commas
    IFS=','
    echo "${result[*]}"

}

function get_list_addons_should_run_test {
    addons_path=$1
    ignore_test=$2
    addons=
    full_list_addons=$(get_list_addons $addons_path)
    if [ -z "${ignore_test:-}" ]; then
        echo $full_list_addons
        return 0
    fi

    backup_IFS=$IFS
    IFS=","
    for addon_name in $full_list_addons; do
        if [[ ! "$ignore_test" =~ "$addon_name" ]]; then
            if [[ -z $addons ]]; then
                addons=$addon_name
            else
                addons="$addons;$addon_name"
            fi
        fi
    done
    IFS=$backup_IFS

    addons=$(echo $addons | sed "s/;/,/g")
    echo $addons
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

function get_github_job_url {
    local gh_url="$1"
    local gh_token="$2"
    local regex_value="$3"
    response=$(curl -s -H "Authorization: token $gh_token" "${gh_url}")
    job_url=$(echo "$response" | jq -r --arg pattern "$regex_value" '.jobs[] | select(.name | test($pattern)) | .html_url')
    echo "$job_url"
}

# ====== Pylint =======
function get_ignore_file_command_pylint {
    ignore_addons=$1
    if [ -z "${ignore_addons:-}" ]; then
        echo "ignore-paths = []"
        return 0
    fi
    command=
    if [[ -n $ignore_addons ]]; then
        backup_IFS=$IFS
        IFS=","
        for addon_name in $ignore_addons; do
            if [[ -z $command ]]; then
                command="\"$addon_name/.*\\.py\""
            else
                command+=";\"$addon_name/.*\\.py\""
            fi
        done
        IFS=$backup_IFS
    fi
    command=$(echo $command | sed "s/;/,/g")
    command="ignore-paths = [$command]"
    echo $command
}

function update_ignore_file_config_pylint {
    ignore_addons=$1
    config_file=$2
    ignore_commands=$(get_ignore_file_command_pylint "$ignore_addons")
    sed -i "/ignore-paths/c\\${ignore_commands}" "$config_file"
}

# ===== Ruff ======
function get_ignore_file_command_ruff {
    ignore_addons=$1
    if [ -z "${ignore_addons:-}" ]; then
        echo 'extend-exclude = ["__manifest__.py", "__init__.py"]'
        return 0
    fi
    command=
    if [[ -n $ignore_addons ]]; then
        backup_IFS=$IFS
        IFS=","
        for addon_name in $ignore_addons; do
            if [[ -z $command ]]; then
                command="\"*/*/$addon_name/**/*\\.py\""
            else
                command+=";\"*/*/$addon_name/**/*\\.py\""
            fi
        done
        IFS=$backup_IFS
    fi
    command=$(echo $command | sed "s/;/,/g")
    command="extend-exclude = [$command,\"__manifest__.py\", \"__init__.py\"]"
    echo $command
}

function update_ignore_file_config_ruff {
    ignore_addons=$1
    config_file=$2
    if [ -z "${ignore_addons:-}" ]; then
        return 0
    fi
    ignore_commands=$(get_ignore_file_command_ruff "$ignore_addons")
    sed -i "/extend-exclude/c\\${ignore_commands}" "$config_file"
}

# ====== SAST Functions =======
function get_ignore_file_command_bandit {
    ignore_addons=$1
    if [ -z "${ignore_addons:-}" ]; then
        echo "exclude_dirs: []"
        return 0
    fi
    command=
    if [[ -n $ignore_addons ]]; then
        backup_IFS=$IFS
        IFS=","
        for addon_name in $ignore_addons; do
            if [[ -z $command ]]; then
                command="- \"$addon_name\""
            else
                command+="\n  - \"$addon_name\""
            fi
        done
        IFS=$backup_IFS
    fi
    command="exclude_dirs:\n  $command"
    echo -e $command
}

function update_ignore_file_config_bandit {
    ignore_addons=$1
    config_file=$2
    ignore_commands=$(get_ignore_file_command_bandit "$ignore_addons")
    sed -i "/exclude_dirs:/,/^[^ ]/c\\${ignore_commands}" "$config_file"
}

function generate_bandit_summary_report {
    bandit_output=$1
    report_file=$2

    echo "# SAST Security Scan Report (Bandit)" > "$report_file"
    echo "" >> "$report_file"
    echo "**Scan Date:** $(date)" >> "$report_file"
    echo "**Repository:** $REPOSITORY" >> "$report_file"
    echo "**Branch:** $TARGET_BRANCH" >> "$report_file"
    echo "" >> "$report_file"

    # Bandit results
    if [[ -f "$bandit_output" ]]; then
        bandit_issues=$(jq '.results | length' "$bandit_output" 2>/dev/null || echo "0")
        echo "## 🔍 Security Issues Found: $bandit_issues" >> "$report_file"
        echo "" >> "$report_file"

        if [[ "$bandit_issues" -gt 0 ]]; then
            echo "### Detailed Issues:" >> "$report_file"
            echo "" >> "$report_file"

            # Group by severity
            high_issues=$(jq '.results[] | select(.issue_severity == "HIGH")' "$bandit_output" 2>/dev/null)
            medium_issues=$(jq '.results[] | select(.issue_severity == "MEDIUM")' "$bandit_output" 2>/dev/null)
            low_issues=$(jq '.results[] | select(.issue_severity == "LOW")' "$bandit_output" 2>/dev/null)

            # High severity issues
            if [[ -n "$high_issues" ]]; then
                echo "#### High Severity Issues:" >> "$report_file"
                jq -r '.results[] | select(.issue_severity == "HIGH") | "- **\(.filename):\(.line_number)** - \(.issue_text) (Test: \(.test_name))"' "$bandit_output" >> "$report_file" 2>/dev/null
                echo "" >> "$report_file"
            fi

            # Medium severity issues
            if [[ -n "$medium_issues" ]]; then
                echo "#### Medium Severity Issues:" >> "$report_file"
                jq -r '.results[] | select(.issue_severity == "MEDIUM") | "- **\(.filename):\(.line_number)** - \(.issue_text) (Test: \(.test_name))"' "$bandit_output" >> "$report_file" 2>/dev/null
                echo "" >> "$report_file"
            fi

            # Low severity issues
            if [[ -n "$low_issues" ]]; then
                echo "#### Low Severity Issues:" >> "$report_file"
                jq -r '.results[] | select(.issue_severity == "LOW") | "- **\(.filename):\(.line_number)** - \(.issue_text) (Test: \(.test_name))"' "$bandit_output" >> "$report_file" 2>/dev/null
                echo "" >> "$report_file"
            fi

            # Summary by severity
            high_count=$(echo "$high_issues" | jq -s 'length' 2>/dev/null || echo "0")
            medium_count=$(echo "$medium_issues" | jq -s 'length' 2>/dev/null || echo "0")
            low_count=$(echo "$low_issues" | jq -s 'length' 2>/dev/null || echo "0")

            echo "### 📊 Summary:" >> "$report_file"
            echo "- High: $high_count" >> "$report_file"
            echo "- Medium: $medium_count" >> "$report_file"
            echo "- Low: $low_count" >> "$report_file"
            echo "- **Total: $bandit_issues**" >> "$report_file"
            echo "" >> "$report_file"

            # Check against threshold
            severity_threshold="${SAST_SEVERITY_THRESHOLD:-medium}"
            if [[ "$severity_threshold" == "high" && "$high_count" -gt 0 ]]; then
                echo "## ⚠️ Security scan failed: High severity issues found!" >> "$report_file"
                exit 1
            elif [[ "$severity_threshold" == "medium" && ($high_count -gt 0 || $medium_count -gt 0) ]]; then
                echo "## ⚠️ Security scan failed: Medium or higher severity issues found!" >> "$report_file"
                exit 1
            else
                echo "## ✅ Security scan passed: No issues above threshold ($severity_threshold)!" >> "$report_file"
                exit 0
            fi
        else
            echo "## ✅ No security issues found!" >> "$report_file"
            echo "" >> "$report_file"
            echo "Your code passed all security checks! 🎉" >> "$report_file"
            exit 0
        fi
    else
        echo "## ❌ Error: Could not read Bandit output file" >> "$report_file"
        exit 1
    fi
}

# declare all useful functions here
function sad_emojis() {
    echo "😢 😭 😞 😔 😟 😩 😫 😓 😥 😰 😨 😧 😦 🙁 ☹️ 😣 😖 😱 😡 🤬 😠 😤 😪 😒 😌 😕 😬 🙄 👾 🧟 💔 💩 🐛 🦗 🦟 🐜 🐝 🐞 🪲 🪳 🦂 🕷️ 🕸️ 🦠 🦂 🧠 🙀 🤢 🤮 🤧 🥺 😵 🤯 🥴 🤕 🤒 😷 🤐 🤫 🤥 🤔 💀 ☠️ 👹 👿 👻 😬 😮‍💨 😓 🤨 😔 🫥 🫠 🙃 🥹 😶 😶‍🌫️ 😐 😑 🫤 🫡 🥱 🫨 🤐 🤢 🤮 💔 💦 🫧 🧊 🧯 🛑 ⛔ 📛 🚫 ❌ ⭕ 🔄 🔙 🔚 ⚠️ ⛔ 🚫 🚳 🚭 🚯 🚱 🚷 📵 🔞 ‼️ ⁉️ ❓ ❔ ❕ ❗ 〽️ ⚠️ 🔅 🔆 💢"
}

function happy_emojis() {
    echo "🎉 🎈 🎊 🥳 ✨ 🌟 💫 ⭐ 🌠 🎇 🎆 🧨 🪅 🎀 🎁 💝 🎂 🍰 🧁 🍩 🍪 🍫 🍬 🍭 🍯 🥂 🍾 🍷 🍸 🍺 🍻 🍶 🍵 ☕ 🥤 🍼 🥛 🍽️ 🍴 🥄 🥢 🧂 🍋 🍊 🍎 🍏 🍐 🍑 🍒 🍓 🥭 🥑 🍉 🍇 🍈 🍌 🍍 🥝 🥥 🥕 🌽 🥦 🍄 🥜 🌰 🍞 🥐 🥖 🥨 🥯 🥞 🧇 🍕 🍔 🍟 🌭 🌮 🌯 🥙 🥗 🥘 🍲 🍚 🍛 🍝 🍜 🍣 🍱 🍡 🍢 🍧 🍨 🍦 🍮 🍿 🌍 🌎 🌏 🌐 🗺️ 🗾 🏔️ ⛰️ 🌋 🗻 🏞️ 🏖️ 🏜️ 🏝️ 🏟️ 🎡 🎠 🎢 🎪 🎭 🎨 🎤 🎧 🎼 🎵 🎶 🎹 🥁 🎷 🎺 🎸 🎻 💃 🕺 👯‍♀️ 👯‍♂️ 🕴️ 🧘 🙌 👏 🤝 🙏 🤳 💪 🏆 🥇 🥈 🥉 🏅 🎗️ 🎫 🎟️ 🏷️ 💯 🔥 💥 😀 😁 😊 👍 🌈 🎯 🏄 🌺 🌸 🌼 🌷 🌹 🌻 💖 💗 💓 💘 💕 💞 💌 🔆 🌞 🍀 🙂 😃 😄 😆 😉 😋 😎 😍 🤩 🤗 🤭 🥰 🦸 🧚 👑 🌅 🌄 🌝 🎮 🎬 📯 🚀 🎄 🎅 👸 🤸 🤹 👼 🦋 😇 🏵️"
}

function show_separator {
    x="==============================================="
    separator=($x $x "$1" $x $x)
    printf "%s\n" "${separator[@]}"
}

function random_emojis() {
    local EMOJIS=($1)
    local COUNT=${2:-3} # Default to 3 if no argument is provided
    local TOTAL_EMOJIS=${#EMOJIS[@]}
    local RESULT=""

    for ((i = 1; i <= COUNT; i++)); do
        local RANDOM_INDEX=$((RANDOM % TOTAL_EMOJIS))
        RESULT+="${EMOJIS[$RANDOM_INDEX]} "
    done

    echo "$RESULT"
}

function random_happy_emojis() {
    echo $(random_emojis "$(happy_emojis)")
}

function random_sad_emojis() {
    echo $(random_emojis "$(sad_emojis)")
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
    telegram_failed_message=$2
    success_message=$3
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
        send_file_notification "$ODOO_LOG_FILE_HOST" "$failed_message" "$telegram_failed_message"
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
function send_telegram_file {
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

function send_telegram_message {
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

function send_telegram_file_default {
    file_path=$1
    caption=$2
    if [ -s $file_path ]; then
        send_telegram_file "$TELEGRAM_TOKEN" "$TELEGRAM_CHANNEL_ID" "$file_path" "$caption"
    fi
}

function send_telegram_message_default {
    message=$1
    send_telegram_message "$TELEGRAM_TOKEN" "$TELEGRAM_CHANNEL_ID" "$message"
}
# ------------------ Telegram functions -------------------------

# ------------------ Slack functions -------------------------

function send_slack_message {
    slack_token=$1
    channel_id=$2
    message=$3

    response=$(
        curl -s -X POST https://slack.com/api/chat.postMessage \
            -H "Authorization: Bearer ${slack_token}" \
            -H 'Content-type: application/json' \
            --data "$(jq -n --arg channel "$channel_id" --arg text "$message" '{channel: $channel, text: $text}')"
    )

    ok=$(echo "$response" | jq -r '.ok')
    if [[ "$ok" != "true" ]]; then
        error_msg=$(echo "$response" | jq -r '.error')
        echo "Slack API error: $error_msg"
        return 1
    fi
    return 0
}

function send_slack_message_default {
    message=$1
    send_slack_message "$SLACK_TOKEN" "$SLACK_CHANNEL_ID" "$message"
}

function send_slack_file() {
    local file_path="$1"
    local caption="${2:-File uploaded via script}"
    local slack_token="$3"
    local channel_id="$4"
    # Check if file exists
    if [ ! -f "$file_path" ]; then
        echo "Error: File '$file_path' does not exist"
        return 1
    fi

    # Check if curl and jq are installed
    command -v curl >/dev/null 2>&1 || {
        echo "Error: curl is required but not installed."
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        echo "Error: jq is required but not installed."
        return 1
    }

    # Get file details
    local file_name=$(basename "$file_path")
    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null)

    # Step 1: Get upload URL
    echo "Requesting upload URL..."
    local upload_response=$(curl -s -X POST "https://slack.com/api/files.getUploadURLExternal" \
        -H "Authorization: Bearer $slack_token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "filename=$file_name" \
        -d "length=$file_size")

    # Check if upload URL request was successful
    local upload_url=$(echo "$upload_response" | jq -r '.upload_url')
    local file_id=$(echo "$upload_response" | jq -r '.file_id')
    if [ "$(echo "$upload_response" | jq -r '.ok')" != "true" ]; then
        echo "Error getting upload URL: $(echo "$upload_response" | jq -r '.error')"
        return 1
    fi

    # Step 2: Upload file to the provided URL
    echo "Uploading file to Slack..."
    local upload_result=$(curl -s -X POST "$upload_url" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$file_path")

    # Check if the upload was successful (HTTP 200)
    if [ $? -ne 0 ]; then
        echo "Error uploading file"
        return 1
    fi

    # Step 3: Complete the upload
    echo "Completing upload..."
    local complete_response=$(
        curl -s -X POST "https://slack.com/api/files.completeUploadExternal" \
            -H "Authorization: Bearer $slack_token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "files=[{\"id\":\"$file_id\",\"title\":\"$file_name\"}]" \
            -d "channel_id=$channel_id" \
            -d "initial_comment=$caption"
    )

    # Check if completion was successful
    if [ "$(echo "$complete_response" | jq -r '.ok')" != "true" ]; then
        echo "Error completing upload: $(echo "$complete_response" | jq -r '.error')"
        return 1
    fi

    echo "File '$file_name' uploaded successfully to Slack channel $channel_id"
    return 0
}

function send_slack_file_default {
    file_path="$1"
    caption="$2"
    if [ -s $file_path ]; then
        send_slack_file "$file_path" "$caption" "$SLACK_TOKEN" "$SLACK_CHANNEL_ID"
    fi
}
# ------------------ Slack functions -------------------------

# ------------------- General notofication -------------------
function send_message_notification {
    local message="$1"
    local telegram_message="$2"
    send_slack_message_default "$message" || true
    send_telegram_message_default "$telegram_message" || true
}

function send_file_notification {
    local file_path="$1"
    local caption="$2"
    local telegram_caption="$3"
    send_slack_file_default "$file_path" "$caption" || true
    send_telegram_file_default "$file_path" "$telegram_caption" || true
}
# ------------------- General notification -------------------
