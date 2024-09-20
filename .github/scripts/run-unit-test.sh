#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function populate_variables() {
    declare -g test_type=$1
    declare -g type_message
    if [[ $test_type == 'at_install' ]]; then
        type_message="At Install"
    else
        type_message="Post Install"
    fi
}

function set_list_addons {
    custom_addons=$(get_list_addons_should_run_test "$ODOO_ADDONS_PATH")
    declare -g custom_addons
    if [ -z $custom_addons ]; then
        show_separator "Can't find any Odoo custom modules, please recheck your config!"
        exit 1
    fi

    ignore_demo_data_addons=$(get_list_addons_ignore_demo_data "$ODOO_ADDONS_PATH")
    declare -g without_demo_addons=
    if [[ -n $ignore_demo_data_addons ]]; then
        without_demo_addons=$ignore_demo_data_addons
    fi
}

function update_config_file {
    sed -i "s/^\s*command\s*.*//g" $ODOO_CONFIG_FILE
    sed -i "s/^\s*without_demo\s*.*//g" $ODOO_CONFIG_FILE

    test_tags=
    echo -en "\ncommand = \
    --stop-after-init \
    --workers 0 \
    --database $ODOO_TEST_DATABASE_NAME \
    --logfile "$ODOO_LOG_FILE_CONTAINER" \
    --log-level error " >>$ODOO_CONFIG_FILE

    tagged_custom_addons=$(echo $custom_addons | sed "s/,/,\//g" | sed "s/^/\//")
    if [[ $test_type == 'at_install' ]]; then
        test_tags="${tagged_custom_addons},-post_install"
    else
        test_tags="${tagged_custom_addons}"
    fi

    echo -en " --init ${custom_addons} \
        --without-demo all \
        --test-tags $test_tags\n" >>$ODOO_CONFIG_FILE
}

function main() {
    show_separator "Start analyzing log file"
    populate_variables "$@"
    set_list_addons
    update_config_file
    start_containers
    wait_until_odoo_shutdown

    failed_message=$(
        cat <<EOF
🐞 $type_message: A few unit test cases for the [PR \\#$PR_NUMBER]($PR_URL) did not pass\\! 🐞
Please take a look at the attached log file🔬
EOF
    )
    analyze_log_file "$failed_message"
}

main "$@"
