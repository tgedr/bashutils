#!/usr/bin/env bats

setup() {
  ROOT_DIR="$BATS_TEST_DIRNAME/.."
  TEST_DIR="$(mktemp -d)"
  COMMAND_LOG="$TEST_DIR/commands.log"
  ZIP_ARGS_LOG="$TEST_DIR/zip-args.log"
  ORIGINAL_PWD="$PWD"
  export ROOT_DIR TEST_DIR COMMAND_LOG ZIP_ARGS_LOG

  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/lambda" "$TEST_DIR/bundle" "$TEST_DIR/infrastructure"
  : > "$COMMAND_LOG"
  : > "$ZIP_ARGS_LOG"

  for command_name in aws az npm jest cdk databricks terraform; do
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'printf "%s\n" "$0 $*" >> "$COMMAND_LOG"' \
      'exit "${STUB_EXIT_CODE:-0}"' > "$TEST_DIR/bin/$command_name"
  done
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "[%s]\n" "$@" >> "$ZIP_ARGS_LOG"' \
    'exit "${STUB_EXIT_CODE:-0}"' > "$TEST_DIR/bin/zip"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "${COVERAGE_REPORT:-TOTAL 10 0 90%}"' \
    'exit "${STUB_EXIT_CODE:-0}"' > "$TEST_DIR/bin/coverage"
  chmod +x "$TEST_DIR/bin/"*
  PATH="$TEST_DIR/bin:$PATH"
  export PATH

  info() { printf '%s\n' "$*"; }
  warn() { printf '%s\n' "$*" >&2; }
  err() { printf '%s\n' "$*" >&2; }
  debug() { :; }
  this_folder="$TEST_DIR"
  FILE_SECRETS=".secrets"
  FILE_VARIABLES=".variables"
  FILE_LOCAL_VARIABLES=".local_variables"
  export this_folder FILE_SECRETS FILE_VARIABLES FILE_LOCAL_VARIABLES
}

teardown() {
  rm -rf "$TEST_DIR"
}

load_section() {
  source "$ROOT_DIR/sections/$1.sh"
}

@test "all section sources parse and load" {
  for section in "$ROOT_DIR"/sections/*.sh; do
    run bash -n "$section"
    [ "$status" -eq 0 ]
    source "$section" || return 1
  done
}

@test "bash helpers check values and redact secret logs" {
  load_section bash

  contains "alpha beta" beta
  [ "$?" -eq 0 ]
  if contains "alpha beta" gamma; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi

  TEST_REQUIRED_VALUE="present"
  export TEST_REQUIRED_VALUE
  verify_env TEST_REQUIRED_VALUE
  unset TEST_REQUIRED_VALUE
  if verify_env TEST_REQUIRED_VALUE; then
    return 1
  fi

  if output="$(add_entry_to_secrets API_TOKEN sensitive-token)"; then
    :
  else
    return 1
  fi
  [[ "$output" == *"[add_entry_to_file|in]"* ]]
  [[ "$output" != *"sensi"* ]]
  grep -F 'export API_TOKEN=sensitive-token' "$TEST_DIR/.secrets"
}

@test "assorted JavaScript helpers preserve status, cwd, and ZIP arguments" {
  load_section bash
  load_section assorted
  touch "$TEST_DIR/lambda/package.json"

  STUB_EXIT_CODE=0
  export STUB_EXIT_CODE
  test_js_lambda "$TEST_DIR/lambda" >/dev/null
  [ "$?" -eq 0 ]
  [ "$PWD" = "$ORIGINAL_PWD" ]

  STUB_EXIT_CODE=17
  if test_js_lambda "$TEST_DIR/lambda" >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 17 ]
  fi
  [ "$PWD" = "$ORIGINAL_PWD" ]

  STUB_EXIT_CODE=0
  zip_js_lambda_function "$TEST_DIR/lambda" "$TEST_DIR/lambda.zip" "src file.js" node_modules
  [ "$?" -eq 0 ]
  [ "$PWD" = "$ORIGINAL_PWD" ]
  grep -F '[src file.js]' "$ZIP_ARGS_LOG"
  grep -F '[node_modules/aws-sdk/*]' "$ZIP_ARGS_LOG"
}

@test "AWS profile setup forwards configuration to the CLI" {
  load_section aws
  STUB_EXIT_CODE=0
  export STUB_EXIT_CODE

  aws_set_profile test-profile access-key secret-key us-west-2 >/dev/null
  [ "$?" -eq 0 ]
  grep -F 'aws configure --profile test-profile set region us-west-2' "$COMMAND_LOG"
  grep -F 'aws configure --profile test-profile set aws_access_key_id access-key' "$COMMAND_LOG"
}

@test "Azure login returns the CLI failure status" {
  load_section azure
  APP_ID="application-id"
  ARM_CLIENT_SECRET="client-secret"
  ARM_TENANT_ID="tenant-id"
  export APP_ID ARM_CLIENT_SECRET ARM_TENANT_ID
  STUB_EXIT_CODE=23
  export STUB_EXIT_CODE

  if az_sp_login >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 23 ]
  fi
  grep -F 'az login --service-principal -u application-id -p client-secret --tenant tenant-id' "$COMMAND_LOG"
}

@test "CDK scaffolding restores cwd and reports command failure" {
  load_section cdk
  STUB_EXIT_CODE=19
  export STUB_EXIT_CODE

  if cdk_scaffolding "$TEST_DIR/infrastructure" >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
  [ "$PWD" = "$ORIGINAL_PWD" ]
  grep -F 'cdk init app --language typescript' "$COMMAND_LOG"
}

@test "commons command reference includes expected sections" {
  load_section commons
  JTV_GITHUB_EMAIL="test@example.com"
  export JTV_GITHUB_EMAIL

  run commands
  [ "$status" -eq 0 ]
  [[ "$output" == *"python -m venv .venv"* ]]
  [[ "$output" == *"aws sts get-caller-identity"* ]]
}

@test "Databricks deployment validates target and stops on validation failure" {
  load_section databricks
  STUB_EXIT_CODE=31
  export STUB_EXIT_CODE

  if databricks_bundle_deploy "$TEST_DIR/bundle" invalid >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
  [ ! -s "$COMMAND_LOG" ]

  if databricks_bundle_deploy "$TEST_DIR/bundle" local >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
  [ "$PWD" = "$ORIGINAL_PWD" ]
  grep -F 'databricks bundle validate --target local --debug' "$COMMAND_LOG"
  [[ "$(cat "$COMMAND_LOG")" != *"databricks bundle deploy"* ]]
}

@test "JavaScript dependency helper restores cwd and returns failure" {
  load_section js
  STUB_EXIT_CODE=29
  export STUB_EXIT_CODE

  if npm_deps "$TEST_DIR/lambda" >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
  [ "$PWD" = "$ORIGINAL_PWD" ]
  grep -F 'npm install' "$COMMAND_LOG"
}

@test "Python coverage helper enforces the threshold" {
  load_section python
  STUB_EXIT_CODE=0
  COVERAGE_REPORT='TOTAL 10 0 90%'
  export STUB_EXIT_CODE COVERAGE_REPORT

  python_check_coverage 80 >/dev/null
  [ "$?" -eq 0 ]
  if python_check_coverage 95 >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
}

@test "Terraform deployment stops on init failure and restores cwd" {
  load_section bash
  load_section terraform
  STUB_EXIT_CODE=37
  export STUB_EXIT_CODE

  if terraform_autodeploy "$TEST_DIR/infrastructure" >/dev/null 2>&1; then
    return 1
  else
    [ "$?" -eq 1 ]
  fi
  [ "$PWD" = "$ORIGINAL_PWD" ]
  grep -F 'terraform init' "$COMMAND_LOG"
  [[ "$(cat "$COMMAND_LOG")" != *"terraform plan"* ]]
  [[ "$(cat "$COMMAND_LOG")" != *"terraform apply"* ]]
}