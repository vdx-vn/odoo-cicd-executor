#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    if [[ $status == "success" ]]; then
        happy_emojis=$(random_happy_emojis)
        message="The [PR \\#$PR_NUMBER]($PR_URL) was merged and deployed to server $happy_emojis"
        send_message_telegram_default "$message"
    else
        sad_emojis=$(random_sad_emojis)
        message=$(
            cat <<EOF
🐞 The [PR \\#$PR_NUMBER]($PR_URL) was merged but the deployment to the server failed\\! $sad_emojis 
Please take a look into the actions log🔬
EOF
        )
        send_message_telegram_default "$message"
    fi
}

main "$@"
