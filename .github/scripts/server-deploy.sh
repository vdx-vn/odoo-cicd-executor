#!/bin/bash
server_docker_compose_path=$1 # the path to folder container Odoo docker-compose.yml file
server_custom_addons_path=$2  # the absolute path to source code, also the git repository
server_config_file=$3         # the path to Odoo config file
server_odoo_url=$4            # odoo service url, to check service is up or not
server_odoo_db_name=$5
commit_sha=$6

original_repo_remote_name="origin"
CUSTOM_ADDONS=

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

check_git_repo_folder() {
    cd $server_custom_addons_path
    git status >/dev/null 2>&1
    if [[ $? -gt 0 ]]; then
        echo "Can't execute git commands because \"$PWD\" folder is not a git repository!"
        exit 1
    fi
}

get_original_remote_url() {
    remote_url=$(git remote get-url $original_repo_remote_name 2>/dev/null)
    if [ -z "$remote_url" ]; then
        other_repo_remote_name=$(git remote show | head -n 1)
        if [ -z "$other_repo_remote_name" ]; then
            exit 1
        fi
        remote_url=$(git remote get-url $other_repo_remote_name)
    fi
    echo "$remote_url"
}

pull_latest_code() {
    git pull
    pull_success=$?

    if [[ $pull_success -ne 0 ]]; then
        echo "Can't pull the latest code on the server, please setup correct git authorization with SSH key."
        exit 1
    fi
}

set_list_addons() {
    declare -g CUSTOM_ADDONS
    CUSTOM_ADDONS=$(get_list_changed_addons "$server_custom_addons_path" "$commit_sha")
}

update_config_file() {
    sed -i "s/^[ #]*command\s*=.*//g" $server_config_file
    sed '/^$/N;/^\n$/D' $server_config_file >temp && mv temp $server_config_file
    if [[ -z $CUSTOM_ADDONS ]]; then
        echo "there is no addons need to update"
        echo -e "\ncommand = -d ${server_odoo_db_name}" >>"${server_config_file}"
    else
        # fixme: we should get list addons need to install ( -i ) from db instead re-install all changed addons
        echo -e "\ncommand = -d ${server_odoo_db_name} -i ${CUSTOM_ADDONS} -u ${CUSTOM_ADDONS}" >>"${server_config_file}"
    fi
}

reset_config_file() {
    sed -i "s/^[ #]*command\s*=.*//g" $server_config_file
    sed '/^$/N;/^\n$/D' $server_config_file >temp && mv temp $server_config_file
    cd "${server_docker_compose_path}"
    docker compose restart
    docker volume prune -f
}

update_odoo_services() {
    cd "${server_docker_compose_path}"
    docker compose restart
}

function get_odoo_login_url() {
    url=$1
    scheme=$(echo $url | awk -F:// '{print $1}')
    domain_port=$(echo $url | sed -n 's~^https\?://\([^/]\+\).*~\1~p')
    echo "${scheme}://${domain_port}/web/login"
}

function wait_until_odoo_available {
    echo "Hang on, Modules are being updated ..."
    # Assuming each addon needs 60s to be updated
    # -> we can calculate maximum total sec we have to wait until Odoo is up and running
    server_odoo_login_url=$(get_odoo_login_url $server_odoo_url)
    ESITATE_TIME_EACH_ADDON=30
    IFS=',' read -ra separate_addons_list <<<$CUSTOM_ADDONS
    total_addons=${#separate_addons_list[@]}
    # each block wait 5s
    maximum_count=$(((total_addons * ESITATE_TIME_EACH_ADDON) / 5))
    count=1
    if [[ $maximum_count -le $count ]]; then
        return
    fi
    while (($count <= $maximum_count)); do
        http_status=$(echo "foo|bar" | { wget --connect-timeout=5 --server-response --spider --quiet "${server_odoo_login_url}" 2>&1 | awk 'NR==1{print $2}' || true; })
        if [[ $http_status = '200' ]]; then
            return # Odoo service is fully up and running
        fi
        ((count++))
        sleep 5
    done
    exit 1 # Odoo service is not running
}

main() {
    check_git_repo_folder
    pull_latest_code
    set_list_addons
    update_config_file
    update_odoo_services
    wait_until_odoo_available
    reset_config_file
}

main
