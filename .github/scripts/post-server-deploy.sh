#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    gh_url=$2
    gh_token=$3
    prefix_job_name=$4
    local commit_author="${COMMIT_AUTHOR:-$GITHUB_ACTOR}"

    if [[ $status == "success" ]]; then
        happy_emojis=$(random_happy_emojis)
        message=$(
            cat <<EOF
🍻🎉🍻🎉🍻🎉 The <${PR_URL}|PR #${PR_NUMBER}> was merged and deployed to server successfully! $happy_emojis
EOF
        )
        telegram_message="🍻🎉🍻🎉🍻🎉 The [PR \\#$PR_NUMBER]($PR_URL) was merged and deployed to server $happy_emojis"
        send_message_notification "$message" "$telegram_message"
    else
        job_url=$(get_github_job_url "$gh_url" "$gh_token" "$prefix_job_name")
        sad_emojis=$(random_sad_emojis)
        message=$(
            cat <<EOF
❌🐞❌ The <${PR_URL}|PR #${PR_NUMBER}> was merged but the deployment to the server failed! $sad_emojis
Please take a look into the <${job_url}|CICD Log 🔬>
EOF
        )
#         telegram_message=$(
#             cat <<EOF
# ❌🐞❌ The [PR \\#$PR_NUMBER]($PR_URL) was merged but the deployment to the server failed\\! $sad_emojis
# Please take a look into the [CICD Log 🔬]($job_url)
# EOF
#         )
        telegram_message=$(create_telegram_failed_message "Deploy Server" "$PR_NUMBER" "$PR_URL" "$commit_author" "😞")

        send_message_notification "$message" "$telegram_message"
    fi
}

main "$@"
