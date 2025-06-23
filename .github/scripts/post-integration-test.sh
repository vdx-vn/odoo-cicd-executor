#!/bin/bash
source "${CICD_UTILS_SCRIPTS_PATH}"

function main {
    status=$1
    prefix_url=$2
    gh_token=$3
    run_id=$4
    job_name=$5
    if [[ $status == "failure" ]]; then
        job_url=$(get_github_job_url "$prefix_url" "$gh_token" "$run_id" "$job_name")
        sad_emojis=$(random_sad_emojis)
        message=$(
            cat <<EOF
❌🐞❌🐞❌🐞 The <${PR_URL}|PR #${PR_NUMBER}> was merged but the integration test failed! $sad_emojis
Please take a look into the <${job_url}|CICD Log 🔬>
EOF
        )
        telegram_message=$(
            cat <<EOF
❌🐞❌🐞❌🐞 The [PR \\#$PR_NUMBER]($PR_URL) was merged but the integration test failed\\! $sad_emojis
Please take a look into the [CICD Log 🔬]($job_url)>
EOF
        )
        send_message_notification "$message" "$telegram_message"
    fi
}

main "$@"
