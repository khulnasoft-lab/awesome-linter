#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# shellcheck source=/dev/null
source "test/testUtils.sh"

AWESOME_LINTER_TEST_CONTAINER_URL="${1}"
TEST_FUNCTION_NAME="${2}"
AWESOME_LINTER_CONTAINER_IMAGE_TYPE="${3}"
debug "Awesome-linter container image type: ${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}"

DEFAULT_BRANCH="main"

COMMAND_TO_RUN=(docker run --rm -t -e DEFAULT_BRANCH="${DEFAULT_BRANCH}" -e ENABLE_GITHUB_ACTIONS_GROUP_TITLE="true")

ignore_test_cases() {
  COMMAND_TO_RUN+=(-e FILTER_REGEX_EXCLUDE=".*(/test/linters/|CHANGELOG.md).*")
}

configure_typescript_for_test_cases() {
  COMMAND_TO_RUN+=(--env TYPESCRIPT_STANDARD_TSCONFIG_FILE=".github/linters/tsconfig.json")
}

configure_git_commitlint_test_cases() {
  debug "Initializing commitlint test case"
  local GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY="test/linters/git_commitlint/good"
  rm -rfv "${GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY}"
  initialize_git_repository "${GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY}"
  touch "${GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY}/test-file.txt"
  git -C "${GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY}" add .
  git -C "${GIT_COMMITLINT_GOOD_TEST_CASE_REPOSITORY}" commit -m "feat: initial commit"

  local GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY="test/linters/git_commitlint/bad"
  rm -rfv "${GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY}"
  initialize_git_repository "${GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY}"
  touch "${GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY}/test-file.txt"
  git -C "${GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY}" add .
  git -C "${GIT_COMMITLINT_BAD_TEST_CASE_REPOSITORY}" commit -m "Bad commit message"
}

configure_linters_for_test_cases() {
  COMMAND_TO_RUN+=(-e TEST_CASE_RUN="true" -e JSCPD_CONFIG_FILE=".jscpd-test-linters.json" -e RENOVATE_SHAREABLE_CONFIG_PRESET_FILE_NAMES="default.json,hoge.json")
  configure_typescript_for_test_cases
  configure_git_commitlint_test_cases
}

run_test_cases_expect_failure() {
  configure_linters_for_test_cases
  COMMAND_TO_RUN+=(-e ANSIBLE_DIRECTORY="/test/linters/ansible/bad" -e CHECKOV_FILE_NAME=".checkov-test-linters-failure.yaml" -e FILTER_REGEX_INCLUDE=".*bad.*")
  EXPECTED_EXIT_CODE=1
  EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH="test/data/awesome-linter-summary/markdown/table/expected-summary-test-linters-expect-failure-${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}.md"
}

run_test_cases_expect_success() {
  configure_linters_for_test_cases
  COMMAND_TO_RUN+=(-e ANSIBLE_DIRECTORY="/test/linters/ansible/good" -e CHECKOV_FILE_NAME=".checkov-test-linters-success.yaml" -e FILTER_REGEX_INCLUDE=".*good.*")
  EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH="test/data/awesome-linter-summary/markdown/table/expected-summary-test-linters-expect-success-${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}.md"
}

run_test_cases_log_level() {
  run_test_cases_expect_success
  LOG_LEVEL="NOTICE"
}

run_test_cases_expect_failure_notice_log() {
  run_test_cases_expect_failure
  LOG_LEVEL="NOTICE"
}

run_test_cases_non_default_home() {
  run_test_cases_expect_success
  COMMAND_TO_RUN+=(-e HOME=/tmp)
}

run_test_case_bash_exec_library_expect_failure() {
  run_test_cases_expect_failure
  COMMAND_TO_RUN+=(-e BASH_EXEC_IGNORE_LIBRARIES="true")
}

run_test_case_bash_exec_library_expect_success() {
  run_test_cases_expect_success
  COMMAND_TO_RUN+=(-e BASH_EXEC_IGNORE_LIBRARIES="true")
}

run_test_case_dont_save_super_linter_log_file() {
  run_test_cases_expect_success
  CREATE_LOG_FILE="false"
}

run_test_case_dont_save_super_linter_output() {
  run_test_cases_expect_success
  SAVE_AWESOME_LINTER_OUTPUT="false"
}

initialize_git_repository_and_test_args() {
  local GIT_REPOSITORY_PATH="${1}"

  initialize_git_repository "${GIT_REPOSITORY_PATH}"

  local GITHUB_EVENT_FILE_PATH="${2}"

  # Put an arbitrary JSON file in the repository to trigger some validation
  cp -v "${GITHUB_EVENT_FILE_PATH}" "${GIT_REPOSITORY_PATH}/"
  git -C "${GIT_REPOSITORY_PATH}" add .
  git -C "${GIT_REPOSITORY_PATH}" commit -m "feat: initial commit"

  RUN_LOCAL=false
  AWESOME_LINTER_WORKSPACE="${GIT_REPOSITORY_PATH}"
  COMMAND_TO_RUN+=(-e GITHUB_WORKSPACE="/tmp/lint")
  COMMAND_TO_RUN+=(-e GITHUB_EVENT_NAME="push")
  COMMAND_TO_RUN+=(-e GITHUB_EVENT_PATH="/tmp/lint/$(basename "${GITHUB_EVENT_FILE_PATH}")")
  COMMAND_TO_RUN+=(-e MULTI_STATUS=false)
  COMMAND_TO_RUN+=(-e VALIDATE_ALL_CODEBASE=false)
}

initialize_github_sha() {
  local GIT_REPOSITORY_PATH="${1}"
  local TEST_GITHUB_SHA
  TEST_GITHUB_SHA="$(git -C "${GIT_REPOSITORY_PATH}" rev-parse HEAD)"
  COMMAND_TO_RUN+=(-e GITHUB_SHA="${TEST_GITHUB_SHA}")
}

run_test_case_git_initial_commit() {
  local GIT_REPOSITORY_PATH
  GIT_REPOSITORY_PATH="$(mktemp -d)"

  initialize_git_repository_and_test_args "${GIT_REPOSITORY_PATH}" "test/data/github-event/github-event-push.json"
  initialize_github_sha "${GIT_REPOSITORY_PATH}"
  COMMAND_TO_RUN+=(--env VALIDATE_JSON="true")

  # Validate commits using commitlint so we can check that we have a default
  # commitlint configuration file
  COMMAND_TO_RUN+=(--env VALIDATE_GIT_COMMITLINT="true")
}

run_test_case_merge_commit_push() {
  local GIT_REPOSITORY_PATH
  GIT_REPOSITORY_PATH="$(mktemp -d)"

  initialize_git_repository_and_test_args "${GIT_REPOSITORY_PATH}" "test/data/github-event/github-event-push-merge-commit.json"

  local NEW_BRANCH_NAME="branch-1"
  git -C "${GIT_REPOSITORY_PATH}" switch --create "${NEW_BRANCH_NAME}"
  cp -v "test/data/github-event/github-event-push-merge-commit.json" "${GIT_REPOSITORY_PATH}/new-file-1.json"
  git -C "${GIT_REPOSITORY_PATH}" add .
  git -C "${GIT_REPOSITORY_PATH}" commit -m "feat: add new file 1"
  cp -v "test/data/github-event/github-event-push-merge-commit.json" "${GIT_REPOSITORY_PATH}/new-file-2.json"
  git -C "${GIT_REPOSITORY_PATH}" add .
  git -C "${GIT_REPOSITORY_PATH}" commit -m "feat: add new file 2"
  cp -v "test/data/github-event/github-event-push-merge-commit.json" "${GIT_REPOSITORY_PATH}/new-file-3.json"
  git -C "${GIT_REPOSITORY_PATH}" add .
  git -C "${GIT_REPOSITORY_PATH}" commit -m "feat: add new file 3"
  git -C "${GIT_REPOSITORY_PATH}" switch "${DEFAULT_BRANCH}"
  # Force the creation of a merge commit
  git -C "${GIT_REPOSITORY_PATH}" merge \
    -m "Merge commit" \
    --no-ff \
    "${NEW_BRANCH_NAME}"
  git -C "${GIT_REPOSITORY_PATH}" branch -d "${NEW_BRANCH_NAME}"

  git -C "${GIT_REPOSITORY_PATH}" log --all --graph --abbrev-commit --decorate --format=oneline

  initialize_github_sha "${GIT_REPOSITORY_PATH}"
  COMMAND_TO_RUN+=(-e VALIDATE_JSON="true")
}

run_test_case_use_find_and_ignore_gitignored_files() {
  ignore_test_cases
  COMMAND_TO_RUN+=(-e IGNORE_GITIGNORED_FILES="true")
  COMMAND_TO_RUN+=(-e USE_FIND_ALGORITHM="true")
  COMMAND_TO_RUN+=(--env VALIDATE_JAVASCRIPT_STANDARD="false")
}

run_test_cases_save_super_linter_output() {
  run_test_cases_expect_success
}

run_test_cases_save_super_linter_output_custom_path() {
  run_test_cases_save_super_linter_output
  AWESOME_LINTER_OUTPUT_DIRECTORY_NAME="custom-awesome-linter-output-directory-name"
}

run_test_case_custom_summary() {
  run_test_cases_expect_success
  AWESOME_LINTER_SUMMARY_FILE_NAME="custom-github-step-summary.md"
}

run_test_case_gitleaks_custom_log_level() {
  run_test_cases_expect_success
  COMMAND_TO_RUN+=(--env GITLEAKS_LOG_LEVEL="warn")
}

run_test_case_fix_mode() {
  VERIFY_FIX_MODE="true"

  GIT_REPOSITORY_PATH="$(mktemp -d)"
  initialize_git_repository_and_test_args "${GIT_REPOSITORY_PATH}" "test/data/github-event/github-event-push.json"

  # Remove leftovers before copying test files because other tests might have
  # created temporary files and caches as the root user, so commands that
  # need access to those files might fail if they run as a non-root user.
  RemoveTestLeftovers

  local LINTERS_TEST_CASES_FIX_MODE_DESTINATION_PATH="${GIT_REPOSITORY_PATH}/${LINTERS_TEST_CASE_DIRECTORY}"
  mkdir -p "${LINTERS_TEST_CASES_FIX_MODE_DESTINATION_PATH}"

  for LANGUAGE in "${LANGUAGES_WITH_FIX_MODE[@]}"; do
    if [[ "${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}" == "slim" ]] &&
      ! IsLanguageInSlimImage "${LANGUAGE}"; then
      debug "Skip ${LANGUAGE} because it's not available in the Awesome-linter ${AWESOME_LINTER_CONTAINER_IMAGE_TYPE} image"
      continue
    fi
    local -l LOWERCASE_LANGUAGE="${LANGUAGE}"
    cp -rv "${LINTERS_TEST_CASE_DIRECTORY}/${LOWERCASE_LANGUAGE}" "${LINTERS_TEST_CASES_FIX_MODE_DESTINATION_PATH}/"
    eval "COMMAND_TO_RUN+=(--env FIX_${LANGUAGE}=\"true\")"
    eval "COMMAND_TO_RUN+=(--env VALIDATE_${LANGUAGE}=\"true\")"
  done

  # Copy gitignore so we don't commit eventual leftovers from previous runs
  cp -v ".gitignore" "${GIT_REPOSITORY_PATH}/"

  # Copy fix mode linter configuration files because default ones are not always
  # suitable for fix mode
  local FIX_MODE_LINTERS_CONFIG_DIR="${GIT_REPOSITORY_PATH}/.github/linters"
  mkdir -p "${FIX_MODE_LINTERS_CONFIG_DIR}"
  cp -rv "test/linters-config/fix-mode/." "${FIX_MODE_LINTERS_CONFIG_DIR}/"
  cp -rv ".github/linters/tsconfig.json" "${FIX_MODE_LINTERS_CONFIG_DIR}/"
  git -C "${GIT_REPOSITORY_PATH}" add .
  git -C "${GIT_REPOSITORY_PATH}" commit --no-verify -m "feat: add fix mode test cases"
  initialize_github_sha "${GIT_REPOSITORY_PATH}"

  # Enable test mode so we run linters and formatters only against their test
  # cases
  COMMAND_TO_RUN+=(--env FIX_MODE_TEST_CASE_RUN="true")
  COMMAND_TO_RUN+=(--env TEST_CASE_RUN="true")
  COMMAND_TO_RUN+=(--env ANSIBLE_DIRECTORY="/test/linters/ansible/bad")
  configure_typescript_for_test_cases

  # Some linters report a non-zero exit code even if they fix all the issues
  EXPECTED_EXIT_CODE=2

  EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH="test/data/awesome-linter-summary/markdown/table/expected-summary-test-linters-fix-mode-${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}.md"
}

# Run the test setup function
${TEST_FUNCTION_NAME}

CREATE_LOG_FILE="${CREATE_LOG_FILE:-"true"}"
debug "CREATE_LOG_FILE: ${CREATE_LOG_FILE}"
SAVE_AWESOME_LINTER_OUTPUT="${SAVE_AWESOME_LINTER_OUTPUT:-true}"

AWESOME_LINTER_WORKSPACE="${AWESOME_LINTER_WORKSPACE:-$(pwd)}"
COMMAND_TO_RUN+=(-v "${AWESOME_LINTER_WORKSPACE}":"/tmp/lint")

if [ -n "${AWESOME_LINTER_OUTPUT_DIRECTORY_NAME:-}" ]; then
  COMMAND_TO_RUN+=(-e AWESOME_LINTER_OUTPUT_DIRECTORY_NAME="${AWESOME_LINTER_OUTPUT_DIRECTORY_NAME}")
fi
AWESOME_LINTER_OUTPUT_DIRECTORY_NAME="${AWESOME_LINTER_OUTPUT_DIRECTORY_NAME:-"awesome-linter-output"}"
AWESOME_LINTER_MAIN_OUTPUT_PATH="${AWESOME_LINTER_WORKSPACE}/${AWESOME_LINTER_OUTPUT_DIRECTORY_NAME}"
debug "Awesome-linter main output path: ${AWESOME_LINTER_MAIN_OUTPUT_PATH}"
AWESOME_LINTER_OUTPUT_PATH="${AWESOME_LINTER_MAIN_OUTPUT_PATH}/awesome-linter"
debug "Awesome-linter output path: ${AWESOME_LINTER_OUTPUT_PATH}"

# Remove color codes from output by default
REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT="${REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT:-"true"}"
COMMAND_TO_RUN+=(--env REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT="${REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT}")

COMMAND_TO_RUN+=(-e CREATE_LOG_FILE="${CREATE_LOG_FILE}")
COMMAND_TO_RUN+=(-e LOG_LEVEL="${LOG_LEVEL:-"DEBUG"}")
COMMAND_TO_RUN+=(-e RUN_LOCAL="${RUN_LOCAL:-true}")
COMMAND_TO_RUN+=(-e SAVE_AWESOME_LINTER_OUTPUT="${SAVE_AWESOME_LINTER_OUTPUT}")

AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH="${AWESOME_LINTER_WORKSPACE}/github-step-summary.md"
# We can't put this inside AWESOME_LINTER_MAIN_OUTPUT_PATH because it doesn't exist
# before Awesome-linter creates it, and we want to verify that as well.
debug "AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH: ${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}"

if [ -n "${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH:-}" ]; then
  debug "Expected Awesome-linter step summary file path: ${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH}"
  ENABLE_GITHUB_ACTIONS_STEP_SUMMARY="true"
  SAVE_AWESOME_LINTER_SUMMARY="true"

  COMMAND_TO_RUN+=(-e GITHUB_STEP_SUMMARY="${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}")
  COMMAND_TO_RUN+=(-v "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}":"${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}")
fi

ENABLE_GITHUB_ACTIONS_STEP_SUMMARY="${ENABLE_GITHUB_ACTIONS_STEP_SUMMARY:-"false"}"
COMMAND_TO_RUN+=(-e ENABLE_GITHUB_ACTIONS_STEP_SUMMARY="${ENABLE_GITHUB_ACTIONS_STEP_SUMMARY}")
COMMAND_TO_RUN+=(-e SAVE_AWESOME_LINTER_SUMMARY="${SAVE_AWESOME_LINTER_SUMMARY:-"false"}")

if [ -n "${AWESOME_LINTER_SUMMARY_FILE_NAME:-}" ]; then
  COMMAND_TO_RUN+=(-e AWESOME_LINTER_SUMMARY_FILE_NAME="${AWESOME_LINTER_SUMMARY_FILE_NAME}")
fi
AWESOME_LINTER_SUMMARY_FILE_NAME="${AWESOME_LINTER_SUMMARY_FILE_NAME:-"awesome-linter-summary.md"}"
debug "AWESOME_LINTER_SUMMARY_FILE_NAME: ${AWESOME_LINTER_SUMMARY_FILE_NAME}"

AWESOME_LINTER_SUMMARY_FILE_PATH="${AWESOME_LINTER_MAIN_OUTPUT_PATH}/${AWESOME_LINTER_SUMMARY_FILE_NAME}"
debug "Awesome-linter summary output path: ${AWESOME_LINTER_SUMMARY_FILE_PATH}"

LOG_FILE_PATH="${AWESOME_LINTER_WORKSPACE}/awesome-linter.log"
debug "Awesome-linter log file path: ${LOG_FILE_PATH}"

COMMAND_TO_RUN+=("${AWESOME_LINTER_TEST_CONTAINER_URL}")

declare -i EXPECTED_EXIT_CODE
EXPECTED_EXIT_CODE=${EXPECTED_EXIT_CODE:-0}

# Remove leftovers before instrumenting the test because other tests might have
# created temporary files and caches
RemoveTestLeftovers
RemoveTestLogsAndSuperLinterOutputs

if [[ "${ENABLE_GITHUB_ACTIONS_STEP_SUMMARY}" == "true" ]]; then
  debug "Creating GitHub Actions step summary file: ${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}"
  touch "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}"
fi

debug "Command to run: ${COMMAND_TO_RUN[*]}"

# Disable failures on error so we can continue with tests regardless
# of the Awesome-linter exit code
set +o errexit
"${COMMAND_TO_RUN[@]}"
AWESOME_LINTER_EXIT_CODE=$?
# Enable the errexit option that we check later
set -o errexit

# Remove leftovers after runnint tests because we don't want other tests
# to consider them
RemoveTestLeftovers

debug "Awesome-linter workspace: ${AWESOME_LINTER_WORKSPACE}"
debug "Awesome-linter exit code: ${AWESOME_LINTER_EXIT_CODE}"

if [[ "${CREATE_LOG_FILE}" == true ]]; then
  if [ ! -e "${LOG_FILE_PATH}" ]; then
    debug "Log file was requested but it's not available at ${LOG_FILE_PATH}"
    exit 1
  else
    sudo chown -R "$(id -u)":"$(id -g)" "${LOG_FILE_PATH}"
    debug "Log file path: ${LOG_FILE_PATH}"
    if [[ "${CI:-}" == "true" ]]; then
      debug "Log file contents:"
      cat "${LOG_FILE_PATH}"
    else
      debug "Not in CI environment, skip emitting log file (${LOG_FILE_PATH}) contents"
    fi

    if [[ "${AWESOME_LINTER_WORKSPACE}" != "$(pwd)" ]]; then
      debug "Copying Awesome-linter log from the workspace (${AWESOME_LINTER_WORKSPACE}) to the current working directory for easier inspection"
      cp -v "${LOG_FILE_PATH}" "$(pwd)/"
    fi

    if [[ "${REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT}" == "true" ]]; then
      if AreAnsiColorCodesInFile "${LOG_FILE_PATH}"; then
        fatal "${LOG_FILE_PATH} contains unexpected ANSI color codes"
      fi
    fi
  fi
else
  debug "Log file was not requested. CREATE_LOG_FILE: ${CREATE_LOG_FILE}"
fi

if [[ "${SAVE_AWESOME_LINTER_OUTPUT}" == true ]]; then
  if [ ! -d "${AWESOME_LINTER_OUTPUT_PATH}" ]; then
    debug "Awesome-linter output was requested but it's not available at ${AWESOME_LINTER_OUTPUT_PATH}"
    exit 1
  else
    sudo chown -R "$(id -u)":"$(id -g)" "${AWESOME_LINTER_OUTPUT_PATH}"
    if [[ "${CI:-}" == "true" ]]; then
      debug "Awesome-linter output path (${AWESOME_LINTER_OUTPUT_PATH}) contents:"
      ls -alhR "${AWESOME_LINTER_OUTPUT_PATH}"
    else
      debug "Not in CI environment, skip emitting ${AWESOME_LINTER_OUTPUT_PATH} contents"
    fi

    if [[ "${AWESOME_LINTER_WORKSPACE}" != "$(pwd)" ]]; then
      debug "Copying Awesome-linter output from the workspace (${AWESOME_LINTER_WORKSPACE}) to the current working directory for easier inspection"
      AWESOME_LINTER_MAIN_OUTPUT_PATH_PWD="$(pwd)/${AWESOME_LINTER_OUTPUT_DIRECTORY_NAME}"
      AWESOME_LINTER_OUTPUT_PATH_PWD="${AWESOME_LINTER_MAIN_OUTPUT_PATH_PWD}/awesome-linter"
      mkdir -p "${AWESOME_LINTER_MAIN_OUTPUT_PATH_PWD}"
      cp -r "${AWESOME_LINTER_OUTPUT_PATH}" "${AWESOME_LINTER_MAIN_OUTPUT_PATH_PWD}/"
    fi

    for LANGUAGE in "${LANGUAGE_ARRAY[@]}"; do
      LANGUAGE_STDERR_FILE_PATH="${AWESOME_LINTER_OUTPUT_PATH_PWD:-"${AWESOME_LINTER_OUTPUT_PATH}"}/awesome-linter-parallel-stderr-${LANGUAGE}"
      LANGUAGE_STDOUT_FILE_PATH="${AWESOME_LINTER_OUTPUT_PATH_PWD:-"${AWESOME_LINTER_OUTPUT_PATH}"}/awesome-linter-parallel-stdout-${LANGUAGE}"

      if [[ "${REMOVE_ANSI_COLOR_CODES_FROM_OUTPUT}" == "true" ]]; then
        if [[ -e "${LANGUAGE_STDERR_FILE_PATH}" ]]; then
          if AreAnsiColorCodesInFile "${LANGUAGE_STDERR_FILE_PATH}"; then
            fatal "${LANGUAGE_STDERR_FILE_PATH} contains unexpected ANSI color codes"
          fi
        fi

        if [[ -e "${LANGUAGE_STDOUT_FILE_PATH}" ]]; then
          if AreAnsiColorCodesInFile "${LANGUAGE_STDOUT_FILE_PATH}"; then
            fatal "${LANGUAGE_STDOUT_FILE_PATH} contains unexpected ANSI color codes"
          fi
        fi
      fi

      unset LANGUAGE_STDERR_FILE_PATH
      unset LANGUAGE_STDOUT_FILE_PATH
    done
  fi
else
  debug "Awesome-linter output was not requested. SAVE_AWESOME_LINTER_OUTPUT: ${SAVE_AWESOME_LINTER_OUTPUT}"

  if [ -e "${AWESOME_LINTER_OUTPUT_PATH}" ]; then
    debug "Awesome-linter output was not requested but it's available at ${AWESOME_LINTER_OUTPUT_PATH}"
    exit 1
  fi
fi

if [ -n "${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH:-}" ]; then
  if ! AssertFileContentsMatchIgnoreHtmlComments "${AWESOME_LINTER_SUMMARY_FILE_PATH}" "${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH}"; then
    debug "Awesome-linter summary (${AWESOME_LINTER_SUMMARY_FILE_PATH}) contents don't match with the expected contents (${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH})"
    exit 1
  else
    debug "Awesome-linter summary (${AWESOME_LINTER_SUMMARY_FILE_PATH}) contents match with the expected contents (${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH})"
  fi

  if ! AssertFileContentsMatchIgnoreHtmlComments "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}" "${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH}"; then
    debug "Awesome-linter GitHub step summary (${AWESOME_LINTER_SUMMARY_FILE_PATH}) contents don't match with the expected contents (${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH})"
    exit 1
  else
    debug "Awesome-linter GitHub step summary (${AWESOME_LINTER_SUMMARY_FILE_PATH}) contents match with the expected contents (${EXPECTED_AWESOME_LINTER_SUMMARY_FILE_PATH})"
  fi

  if [[ "${AWESOME_LINTER_WORKSPACE}" != "$(pwd)" ]]; then
    debug "Copying Awesome-linter summary from the workspace (${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}) to the current working directory for easier inspection"
    cp "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}" "$(pwd)/"
  fi
  if [[ "${AWESOME_LINTER_WORKSPACE}" != "$(pwd)" ]]; then
    debug "Copying Awesome-linter GitHub step summary from the workspace (${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}) to the current working directory for easier inspection"
    cp "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}" "$(pwd)/"
  fi
else
  debug "Awesome-linter summary output was not requested."

  if [ -e "${AWESOME_LINTER_SUMMARY_FILE_PATH}" ]; then
    debug "Awesome-linter summary was not requested but it's available at ${AWESOME_LINTER_SUMMARY_FILE_PATH}"
    exit 1
  fi

  if [ -e "${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}" ]; then
    debug "Awesome-linter GitHub step summary was not requested but it's available at ${AWESOME_LINTER_GITHUB_STEP_SUMMARY_FILE_PATH}"
    exit 1
  fi
fi

if [ ${AWESOME_LINTER_EXIT_CODE} -ne ${EXPECTED_EXIT_CODE} ]; then
  debug "Awesome-linter exited with an unexpected code: ${AWESOME_LINTER_EXIT_CODE}"
  exit 1
else
  debug "Awesome-linter exited with the expected code: ${AWESOME_LINTER_EXIT_CODE}"
fi

VERIFY_FIX_MODE="${VERIFY_FIX_MODE:-"false"}"
if [[ "${VERIFY_FIX_MODE:-}" == "true" ]]; then
  debug "Verifying fix mode"
  for LANGUAGE in "${LANGUAGES_WITH_FIX_MODE[@]}"; do
    if [[ "${AWESOME_LINTER_CONTAINER_IMAGE_TYPE}" == "slim" ]] &&
      ! IsLanguageInSlimImage "${LANGUAGE}"; then
      debug "Skip ${LANGUAGE} because it's not available in the Awesome-linter ${AWESOME_LINTER_CONTAINER_IMAGE_TYPE} image"
      continue
    fi

    declare -l LOWERCASE_LANGUAGE="${LANGUAGE}"
    BAD_TEST_CASE_SOURCE_PATH="${LINTERS_TEST_CASE_DIRECTORY}/${LOWERCASE_LANGUAGE}"
    debug "Source path to the ${LANGUAGE} test case expected to fail: ${BAD_TEST_CASE_SOURCE_PATH}"
    BAD_TEST_CASE_DESTINATION_PATH="${AWESOME_LINTER_WORKSPACE}/${LINTERS_TEST_CASE_DIRECTORY}/${LOWERCASE_LANGUAGE}"
    debug "Destination path to ${LANGUAGE} test case expected to fail: ${BAD_TEST_CASE_DESTINATION_PATH}"

    if [[ ! -e "${BAD_TEST_CASE_SOURCE_PATH}" ]]; then
      fatal "${BAD_TEST_CASE_SOURCE_PATH} doesn't exist"
    fi

    if [[ ! -e "${BAD_TEST_CASE_DESTINATION_PATH}" ]]; then
      fatal "${BAD_TEST_CASE_DESTINATION_PATH} doesn't exist"
    fi

    if find "${BAD_TEST_CASE_DESTINATION_PATH}" \( -type f ! -readable -or -type d \( ! -readable -or ! -executable -or ! -writable \) \) -print | grep -q .; then
      if [[ "${LANGUAGE}" == "DOTNET_SLN_FORMAT_ANALYZERS" ]] ||
        [[ "${LANGUAGE}" == "DOTNET_SLN_FORMAT_STYLE" ]] ||
        [[ "${LANGUAGE}" == "DOTNET_SLN_FORMAT_WHITESPACE" ]] ||
        [[ "${LANGUAGE}" == "RUST_CLIPPY" ]] ||
        [[ "${LANGUAGE}" == "SHELL_SHFMT" ]] ||
        [[ "${LANGUAGE}" == "SQLFLUFF" ]]; then
        debug "${LANGUAGE} is a known case of a tool that doesn't preserve the ownership of files or directories in fix mode. Need to recursively change ownership of ${BAD_TEST_CASE_DESTINATION_PATH}"
        sudo chown -R "$(id -u)":"$(id -g)" "${BAD_TEST_CASE_DESTINATION_PATH}"
      else
        ls -alR "${BAD_TEST_CASE_DESTINATION_PATH}"
        fatal "Cannot verify fix mode for ${LANGUAGE}: ${BAD_TEST_CASE_DESTINATION_PATH} is not readable, or contains unreadable files."
      fi
    else
      debug "${BAD_TEST_CASE_DESTINATION_PATH} and its contents are readable"
    fi

    if [[ "${LANGUAGE}" == "RUST_CLIPPY" ]]; then
      rm -rf \
        "${BAD_TEST_CASE_DESTINATION_PATH}"/*/Cargo.lock \
        "${BAD_TEST_CASE_DESTINATION_PATH}"/*/target
    fi

    if AssertFileAndDirContentsMatch "${BAD_TEST_CASE_DESTINATION_PATH}" "${BAD_TEST_CASE_SOURCE_PATH}"; then
      fatal "${BAD_TEST_CASE_DESTINATION_PATH} contents match ${BAD_TEST_CASE_SOURCE_PATH} contents and they should differ because fix mode for ${LANGUAGE} should have fixed linting and formatting issues."
    fi
  done
fi

# Check if awesome-linter leaves leftovers behind
declare -a TEMP_ITEMS_TO_CLEAN
TEMP_ITEMS_TO_CLEAN=()
TEMP_ITEMS_TO_CLEAN+=("$(pwd)/.lintr")
TEMP_ITEMS_TO_CLEAN+=("$(pwd)/.mypy_cache")
TEMP_ITEMS_TO_CLEAN+=("$(pwd)/.ruff_cache")
TEMP_ITEMS_TO_CLEAN+=("$(pwd)/logback.log")

for item in "${TEMP_ITEMS_TO_CLEAN[@]}"; do
  debug "Check if ${item} exists"
  if [[ -e "${item}" ]]; then
    debug "Error: ${item} exists and it should have been deleted"
    exit 1
  else
    debug "${item} does not exist as expected"
  fi
done

if ! CheckUnexpectedGitChanges "$(pwd)"; then
  debug "There are unexpected modifications to the working directory after running tests."
  exit 1
fi
