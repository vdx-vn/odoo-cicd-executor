#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function update_config_file {
    sed -i "s/^\s*command\s*.*//g" $ODOO_CONFIG_FILE
    sed -i "s/^\s*without_demo\s*.*//g" $ODOO_CONFIG_FILE

    echo -en "\ncommand = \
    --stop-after-init \
    --workers 0 \
    --database $ODOO_TEST_DATABASE_NAME \
    --logfile "$ODOO_LOG_FILE_CONTAINER" \
    --load base,web \
    --init test_lint \
    --test-tags /test_lint \
    --log-level error" >>$ODOO_CONFIG_FILE
    echo " " >>$ODOO_CONFIG_FILE
}

function main() {
    show_separator "Start analyzing log file"
    update_config_file
    start_containers
    wait_until_odoo_shutdown

    failed_message=$(
        cat <<EOF
🐞 A few pylint test cases of the [PR \\#$PR_NUMBER]($PR_URL) did not pass\\! 🐞
Please take a look at the attached log file🔬
EOF
    )
    analyze_log_file "$failed_message"
}

main
