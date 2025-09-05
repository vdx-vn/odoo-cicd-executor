#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    gh_url=$2
    gh_token=$3
    prefix_job_name=$4
    if [[ $status == "failure" ]]; then
        job_url=$(get_github_job_url "$gh_url" "$gh_token" "$prefix_job_name")
        sad_emojis=$(random_sad_emojis)
        message=$(
            cat <<EOF
❌🐞❌ The <${PR_URL}|PR #${PR_NUMBER}> was merged but the integration test failed! $sad_emojis
Please take a look into the <${job_url}|CICD Log 🔬>
EOF
        )
         telegram_message=$(
             cat <<EOF
 ❌🐞❌ The [PR \\#$PR_NUMBER]($PR_URL) was merged but the integration test failed\\! $sad_emojis
 Please take a look into the [CICD Log 🔬]($job_url)
 EOF
         )
#        telegram_message=$(create_telegram_failed_message "Integration Test" "$PR_NUMBER" "$PR_URL" "$COMMIT_AUTHOR" "😞")

        send_message_notification "$message" "$telegram_message"
    fi
}

main "$@"
