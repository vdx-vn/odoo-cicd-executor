#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function lint() {
    # -e FIX_PYTHON_ISORT=true \

    docker run \
        -e LOG_LEVEL=ERROR \
        -e FILTER_REGEX_INCLUDE=\.py \
        -e FILTER_REGEX_EXCLUDE=__manifest__\.py\|__init__\.py \
        -e RUN_LOCAL=true \
        -e USE_FIND_ALGORITHM=true \
        -e SAVE_SUPER_LINTER_OUTPUT=true \
        -e VALIDATE_JSCPD=false \
        -e VALIDATE_JSON=false \
        -e VALIDATE_PYTHON_FLAKE8=false \
        -e VALIDATE_PYTHON_BLACK=false \
        -e VALIDATE_PYTHON_MYPY=false \
        -e VALIDATE_PYTHON_PYINK=false \
        -e VALIDATE_PYTHON_ISORT=false \
        -e VALIDATE_GIT_MERGE_CONFLICT_MARKERS=false \
        -e VALIDATE_GITHUB_ACTIONS=false \
        -e VALIDATE_GITLEAKS=false \
        -e VALIDATE_CHECKOV=false \
        -v $REPO_PATH:/tmp/lint \
        ghcr.io/super-linter/super-linter:latest

    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    echo "==============================="
    cd $REPO_PATH/super-linter-output
    sudo tar -cf linter-log.tar.gz super-linter

    send_file_telegram_default "$REPO_PATH/super-linter-output/linter-log.tar.gz" "Linter result"

}

lint "$@"
