#!/usr/bin/env bash

WriteSummaryHeader() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"

  {
    echo "# Awesome-linter summary"
    echo ""
    echo "| Language | Validation result |"
    echo "| -------- | ----------------- |"
  } >>"${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}"
}

WriteSummaryLineSuccess() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"
  local LANGUAGE_NAME="${2}"
  echo "| ${LANGUAGE_NAME} | Pass ✅ |" >>"${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}"
}

WriteSummaryLineFailure() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"
  local LANGUAGE_NAME="${2}"
  echo "| ${LANGUAGE_NAME} | Fail ❌ |" >>"${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}"
}

WriteSummaryFooterSuccess() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"
  {
    echo ""
    echo "All files and directories linted successfully"
  } >>"${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}"
}

WriteSummaryFooterFailure() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"
  {
    echo ""
    echo "Awesome-linter detected linting errors"
  } >>"${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}"
}

FormatAwesomeLinterSummaryFile() {
  local AWESOME_LINTER_SUMMARY_OUTPUT_PATH="${1}"
  local AWESOME_LINTER_SUMMARY_FORMAT_COMMAND=(prettier --write)
  # Override the default prettier ignore paths (.gitignore, .prettierignore) to
  # avoid considering their defaults because prettier will skip formatting
  # the summary report file if the summary report file is ignored in those
  # ignore files, which is usually the case for generated files.
  # Ref: https://prettier.io/docs/en/cli#--ignore-path
  AWESOME_LINTER_SUMMARY_FORMAT_COMMAND+=(--ignore-path /dev/null)
  AWESOME_LINTER_SUMMARY_FORMAT_COMMAND+=("${AWESOME_LINTER_SUMMARY_OUTPUT_PATH}")
  debug "Formatting the Awesome-linter summary file by running: ${AWESOME_LINTER_SUMMARY_FORMAT_COMMAND[*]}"
  if ! "${AWESOME_LINTER_SUMMARY_FORMAT_COMMAND[@]}"; then
    error "Error while formatting the Awesome-linter summary file."
    return 1
  fi
}

# 0x1B (= ^[) is the control code that starts all ANSI color codes escape sequences
# Ref: https://en.wikipedia.org/wiki/ANSI_escape_code#C0_control_codes
ANSI_COLOR_CODES_SEARCH_PATTERN='\x1b\[[0-9;]*m'
export ANSI_COLOR_CODES_SEARCH_PATTERN
RemoveAnsiColorCodesFromFile() {
  local FILE_PATH="${1}"
  debug "Removing ANSI color codes from ${FILE_PATH}"
  if ! sed -i "s/${ANSI_COLOR_CODES_SEARCH_PATTERN}//g" "${FILE_PATH}"; then
    error "Error while removing ANSI color codes from ${FILE_PATH}"
    return 1
  fi
}
