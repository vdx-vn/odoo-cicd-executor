#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    if [[ $status == "success" ]]; then
        happy_emojis=$(random_happy_emojis)
        message=$(
            cat <<EOF
🎉🎉🎉 The <${PR_URL}|PR #${PR_NUMBER}> was merged and deployed to server successfully! $happy_emojis
EOF
        )
        send_message_notification "$message"
    else
        sad_emojis=$(random_sad_emojis)
        message=$(
            cat <<EOF
🐞🐞🐞 The <${PR_URL}|PR #${PR_NUMBER}> was merged but the deployment to the server failed! $sad_emojis
Please take a look into the actions log🔬
EOF
        )
        send_message_notification "$message"
    fi
}

main "$@"
