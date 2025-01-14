#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function lint() {
    docker run \
        -e LOG_LEVEL=INFO \
        -e FILTER_REGEX_EXCLUDE=__manifest__\.py \
        -e FILTER_REGEX_INCLUDE= \.py -e RUN_LOCAL=true \
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

    cd $REPO_PATH/super-linter-output
    tar -cf linter-log.tar.gz .

    send_file_telegram_default "$REPO_PATH/super-linter-output/linter-log.tar.gz" "Linter result"
}

lint "$@"
