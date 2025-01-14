#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function lint() {
    docker run \
        -e LOG_LEVEL=INFO \
        -e FILTER_REGEX_EXCLUDE=__manifest__\.py \
        -e RUN_LOCAL=true \
        -e USE_FIND_ALGORITHM=true \
        -e SAVE_SUPER_LINTER_SUMMARY=true \
        -e SAVE_SUPER_LINTER_OUTPUT=true \
        -v $REPO_PATH:/tmp/lint \
        ghcr.io/super-linter/super-linter:latest

    summary=$REPO_PATH/super-linter-output/super-linter-summary.md
    output=$REPO_PATH/super-linter-output/super-linter

    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    ls -lah $output
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="

    # send_file_telegram_default "$output" "Linter result"
}

lint "$@"
