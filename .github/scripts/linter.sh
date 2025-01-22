#!/bin/bash

source "${CICD_UTILS_SCRIPTS_PATH}"

function run_lint() {
    echo "=============================="
    docker run \
        -e LINTER_RULES_PATH=/tmp/lint/linter-rules \
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
        -v $WORKSPACE/.github/linters:/tmp/lint/linter-rules \
        ghcr.io/super-linter/super-linter:latest

}

function get_exit_code() {
    file_name=$1
    code=$(awk '{printf "%s", $0}' $file_name | tr -d ' ')
    echo $code
}

function extract_lint_result() {
    output_dir=$REPO_PATH/super-linter-output/super-linter
    python_ruff_exit_code=$(get_exit_code "$output_dir/super-linter-parallel-command-exit-code-PYTHON_RUFF")
    python_pylint_exit_code=$(get_exit_code "$output_dir/super-linter-parallel-command-exit-code-PYTHON_PYLINT")
    python_ruff_output=$output_dir/super-linter-parallel-stdout-PYTHON_RUFF
    python_pylint_output=$output_dir/super-linter-parallel-stdout-PYTHON_PYLINT

    linter_summary=$output_dir/linter-summary
    sudo touch $linter_summary
    sudo chmod 777 $linter_summary
    if [ $python_ruff_exit_code = "1" ]; then
        echo -e "================================================================================\n" >>$linter_summary
        echo -e "===========================Python Ruff Linter ===========================\n" >>$linter_summary
        echo -e "================================================================================\n" >>$linter_summary
        cat $python_ruff_output >>$linter_summary
    fi
    if [ $python_pylint_exit_code = "1" ]; then
        echo -e "\n================================================================================\n" >>$linter_summary
        echo -e "===========================Python Pylint Linter ===========================\n" >>$linter_summary
        echo -e "================================================================================\n" >>$linter_summary
        cat $python_pylint_output >>$linter_summary
    fi

    send_file_telegram_default "$linter_summary" "Linter error"
}

function main() {
    run_lint
    # extract_lint_result
}

main "$@"
