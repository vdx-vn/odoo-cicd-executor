#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function lint() {
    docker run \
        -e LOG_LEVEL=WARN \
        -e FILTER_REGEX_EXCLUDE=__manifest__\.py \
        -e RUN_LOCAL=true \
        -e USE_FIND_ALGORITHM=true \
        -e SAVE_SUPER_LINTER_SUMMARY=true \
        -v $REPO_PATH:/tmp/lint \
        ghcr.io/super-linter/super-linter:latest

    summary=$REPO_PATH/super-linter-output/super-linter-summary.md

    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    cat $summary
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="

    send_file_telegram_default $summary "Linter result"
}

lint "$@"
