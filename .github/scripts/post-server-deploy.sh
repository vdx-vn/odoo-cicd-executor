#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    if [[ $status == "success" ]]; then
        message="The [PR \\#$PR_NUMBER]($PR_URL) was merged and deployed to server 💫🤩💫"
        send_message_telegram_default "$message"
    else
        message=$(
            cat <<EOF
🐞 The [PR \\#$PR_NUMBER]($PR_URL) was merged but the deployment to the server failed\\! 🐞
Please take a look into the actions log🔬
EOF
        )
        send_message_telegram_default "$message"
    fi
}

main "$@"
