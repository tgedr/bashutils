#!/usr/bin/env bash

# ===> HEADER SECTION START  ===>

# http://bash.cumulonim.biz/NullGlob.html
shopt -s nullglob
# -------------------------------
this_folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -z "$this_folder" ]; then
  this_folder=$(dirname "$(readlink -f "$0")")
fi

# -------------------------------
# --- required functions
debug(){
    local __msg="$1"
    echo " [DEBUG] $(date) ... $__msg "
}

info(){
    local __msg="$1"
    echo " [INFO]  $(date) ->>> $__msg "
}

warn(){
    local __msg="$1"
    echo " [WARN]  $(date) *** $__msg "
}

err(){
    local __msg="$1"
    echo " [ERR]   $(date) !!! $__msg "
}

source_if_exists() {
  local file="$1"
  if [ ! -f "$file" ]; then
    warn "we DON'T have a $(basename "$file") file - creating it"
    touch "$file"
    chmod 600 "$file"
  else
    . "$file"
  fi
}

# ---------- CONSTANTS ----------
export FILE_VARIABLES=${FILE_VARIABLES:-".variables"}
export FILE_LOCAL_VARIABLES=${FILE_LOCAL_VARIABLES:-".local_variables"}
export FILE_SECRETS=${FILE_SECRETS:-".secrets"}
export INCLUDE_FILE=${INCLUDE_FILE:-"bashutils"}
export BASHUTILS_URL=${BASHUTILS_URL:-"https://api.github.com/repos/tgedr/bashutils/contents/bashutils"}
export BASHUTILS_CHECKSUM_URL=${BASHUTILS_CHECKSUM_URL:-"https://api.github.com/repos/tgedr/bashutils/contents/bashutils.checksum"}
export BASHUTILS_CHECK_INTERVAL_SECONDS=${BASHUTILS_CHECK_INTERVAL_SECONDS:-"86400"}
export REPO="tgedr/bashutils"

get_file_mtime_epoch() {
  local file="$1"
  local mtime
  mtime="$(stat -c %Y "$file" 2>/dev/null)" && {
    echo "$mtime"
    return 0
  }
  mtime="$(stat -f %m "$file" 2>/dev/null)" && {
    echo "$mtime"
    return 0
  }
  return 1
}

download_bashutils_if_newer() {
  local bashutils="$this_folder/$INCLUDE_FILE"
  local bashutils_last_check="$this_folder/${INCLUDE_FILE}.last_check"
  local bashutils_checksum="$this_folder/${INCLUDE_FILE}.checksum"
  local just_fetch="0"
  local now_epoch
  local last_check_epoch
  local elapsed
  local did_remote_check=0
  local bashutils_tmp
  local checksum_tmp
  local actual_sha256
  local expected_sha256

  
  if [ -f "$bashutils" ] && [ -f "$bashutils_last_check" ]; then
    now_epoch=$(date +%s)
    if last_check_epoch="$(get_file_mtime_epoch "$bashutils_last_check")"; then
      case "$last_check_epoch" in
        ''|*[!0-9]*)
          warn "[download_bashutils_if_newer] invalid last check marker timestamp, forcing a remote check"
          ;;
        *)
          elapsed=$((now_epoch - last_check_epoch))
          if [ "$elapsed" -lt "$BASHUTILS_CHECK_INTERVAL_SECONDS" ]; then
            info "[download_bashutils_if_newer] no need to update $INCLUDE_FILE (last checked $elapsed seconds ago)"
            return 0
          fi
          ;;
      esac
    fi
  else
    info "[download_bashutils_if_newer] no $INCLUDE_FILE or ${INCLUDE_FILE}.last_check found - we will fetch it"
    just_fetch="1"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    err "[download_bashutils_if_newer] please install curl"
    return 1
  fi

  if ! command -v sha256sum >/dev/null 2>&1; then
    err "[download_bashutils_if_newer] please install sha256sum to verify $INCLUDE_FILE"
    return 1
  fi

  checksum_tmp="$(mktemp)"
  if ! curl -fsSL "$BASHUTILS_CHECKSUM_URL" \
    | python3 -c "import sys,json,base64; sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)['content']))" \
    > "$checksum_tmp"; then
    err "[download_bashutils_if_newer] failed to download $(basename "$BASHUTILS_CHECKSUM_URL")"
    rm -f "$checksum_tmp"
    return 1
  fi
  expected_sha256=$(cat "$checksum_tmp" | awk '{print $1}')
  info "[download_bashutils_if_newer] expected_sha256: $expected_sha256"
  rm -f "$checksum_tmp"

  if [ "$just_fetch" -ne "1" ]; then
      info "[download_bashutils_if_newer] checking existing $INCLUDE_FILE"

      actual_sha256=$(cat "$bashutils_checksum" | awk '{print $1}')
      info "[download_bashutils_if_newer] actual_sha256: $actual_sha256"
      
      if [ "$actual_sha256" != "$expected_sha256" ]; then
        info "[download_bashutils_if_newer] $INCLUDE_FILE is outdated (actual: $actual_sha256, expected: $expected_sha256), updating it"
        just_fetch="1"
      else
        info "[download_bashutils_if_newer] $INCLUDE_FILE is up to date"
      fi
  fi


  if [ "$just_fetch" -eq "1" ]; then
    bashutils_tmp="$(mktemp)"
    curl -fsSL "$BASHUTILS_URL" \
      | python3 -c "import sys,json,base64; sys.stdout.buffer.write(base64.b64decode(json.load(sys.stdin)['content']))" \
      > "$bashutils_tmp"
    if [ ! "$?" -eq "0" ]; then
      err "[download_bashutils_if_newer] failed to download $INCLUDE_FILE"
      rm -f "$bashutils_tmp"
      return 1
    fi
    info "[download_bashutils_if_newer] downloaded $INCLUDE_FILE to $bashutils_tmp"
    actual_sha256="$(sha256sum "$bashutils_tmp" | awk '{print $1}')"
    info "[download_bashutils_if_newer] actual_sha256: $actual_sha256"

    if [ "$actual_sha256" != "$expected_sha256" ]; then
      info "[download_bashutils_if_newer] $INCLUDE_FILE checksum is not equal to the expected one (actual: $actual_sha256, expected: $expected_sha256), aborting update"
      return 1
    fi

    mv "$bashutils_tmp" "$bashutils"
    rm -f "$bashutils_tmp"
    touch "$bashutils_last_check" || warn "[download_bashutils_if_newer] failed to update last check marker; next run will perform a remote check"
    info "[download_bashutils_if_newer] updated $INCLUDE_FILE or ${INCLUDE_FILE}.last_check "
  fi

}

# -------------------------------
# --- source variables files
source_if_exists "$this_folder/$FILE_VARIABLES"
source_if_exists "$this_folder/$FILE_LOCAL_VARIABLES"
source_if_exists "$this_folder/$FILE_SECRETS"

# <=== HEADER SECTION END  <===

# ===> MAIN SECTION START  ===>

reqs(){
  info "[reqs|in]"
  local _pwd
  local result
  _pwd=$(pwd)
  cd "$this_folder" || exit 1

  case "$(uname -s)" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        brew install bats-core
        result="$?"
      else
        err "[reqs] Homebrew is required to install bats on macOS"
        result=1
      fi
      ;;
    Linux)
      sudo apt-get update && sudo apt-get install -y bats
      result="$?"
      ;;
    *)
      err "[reqs] unsupported operating system: $(uname -s)"
      result=1
      ;;
  esac

  cd "$_pwd" || exit 1
  local msg="[reqs|out] => ${result}"
  [[ ! "$result" -eq "0" ]] && info "$msg" && exit 1
  info "$msg"
}

test(){
  info "[test|in]"
  _pwd=`pwd`
  cd "$this_folder" || exit 1

  bats test
  local result="$?"

  cd "$_pwd"
  local msg="[test|out] => ${result}"
  [[ ! "$result" -eq "0" ]] && info "$msg" && exit 1
  info "$msg"
}

build_bashutils(){
  info "[build_bashutils|in]"
  local sections_dir="$this_folder/sections"
  local dist_dir="$this_folder/dist"
  local out_file="$this_folder/$INCLUDE_FILE"
  local _pwd
  local checksum_result
  _pwd=$(pwd)

  [ ! -d "$sections_dir" ] && err "[build_bashutils] sections folder not found: $sections_dir" && exit 1

  local files
  files=("$sections_dir"/*.sh)
  [ ${#files[@]} -eq 0 ] && err "[build_bashutils] no .sh files found in $sections_dir" && exit 1

  > "$out_file"
  for f in "${files[@]}"; do
    cat "$f" >> "$out_file" || { err "[build_bashutils] failed to append $f to $out_file"; exit 1; }
    echo >> "$out_file" || { err "[build_bashutils] failed to append newline to $out_file"; exit 1; }
  done

  if command -v sha256sum >/dev/null 2>&1; then
    cd "$this_folder" || exit 1
    sha256sum "$INCLUDE_FILE" > "${INCLUDE_FILE}.checksum"
    checksum_result="$?"
    cd "$_pwd" || exit 1
    if [ "$checksum_result" -ne 0 ]; then
      exit 1
    fi
  else
    err "[build_bashutils] please install sha256sum to generate checksum file"
    exit 1
  fi

  info "[build_bashutils|out] => 0"
}

create_release_artifacts(){
  info "[create_release_artifacts|in]"
  local dist_dir="$this_folder/dist"
  local out_file="$this_folder/$INCLUDE_FILE"
  local version
  local version_file="$this_folder/.version"

  rm -rf "$dist_dir"
  mkdir -p "$dist_dir"
  cp "$out_file" "$dist_dir/" || { err "[create_release_artifacts] failed to move $INCLUDE_FILE to $dist_dir"; exit 1; }
  cp "${out_file}.checksum" "$dist_dir/" || { err "[create_release_artifacts] failed to move ${out_file}.checksum to $dist_dir"; exit 1; }

  read -r value < "$version_file"
  value=$((10#$value + 1))
  info "[create_release_artifacts] incremented version to $value"
  printf '%s\n' "$value" > "$version_file"

  info "[create_release_artifacts|out] => 0"
}

create_github_release(){
  info "[create_github_release|in]"

  local dist_dir="$this_folder/dist"
  local version_file="$this_folder/.version"
  local -a release_assets=()
  local asset
  read -r version < "$version_file"

  for asset in "$dist_dir"/.[!.]* "$dist_dir"/*; do
    [ -f "$asset" ] && release_assets+=("$asset")
  done

  if [ "${#release_assets[@]}" -eq 0 ]; then
    err "[create_github_release] no release assets found in $dist_dir"
    return 1
  fi

  local is_draft="false"
  if [ "$RELEASE_DRAFT" = "true" ]; then
    is_draft="true"
  fi
  
  gh release create "$version" "${release_assets[@]}" --title "Release $version" --draft="$is_draft" --notes "check release content for more details"
  [ "$?" -ne "0" ] && err "[create_github_release] failed to create release" && return 1
  
  info "[create_github_release|out]"
}
############################
#   name: download_github_release_files
#   purpose: downloads all release assets from a GitHub release by version tag using the assets API (avoids proxy-blocked redirects); supports optional token authentication
#   parameters: $1 (repository in owner/repo format), $2 (version tag), $3 (target download directory), $4 (optional GitHub API token)
#   requires: curl, python3, this_folder
############################
download_github_release_files(){
  info "[download_github_release_files|in] ($1, $2, $3, ${4:0:7})"

  [ -z "$1" ] && err "[download_github_release_files] missing argument REPO" && return 1
  local REPO="$1"
  [ -z "$2" ] && err "[download_github_release_files] missing argument VERSION" && return 1
  local VERSION="$2"
  [ -z "$3" ] && err "[download_github_release_files] missing argument TARGET_DIR" && return 1
  local TARGET_DIR="$3"
  
  _pwd=$(pwd)
  cd "$TARGET_DIR"

  local AUTH_HEADER=""
  [ -n "$GITHUB_TOKEN" ] && AUTH_HEADER="-H \"Authorization: token $GITHUB_TOKEN\""

  # Use assets API with Accept: application/octet-stream to avoid redirect to
  # objects.githubusercontent.com (which may be blocked by proxies like Zscaler)
  local release_json
  release_json=$(eval curl -fsSL "$AUTH_HEADER" "\"https://api.github.com/repos/$REPO/releases/tags/$VERSION\"")
  result="$?"
  if [ "$result" -ne "0" ]; then
    err "[download_github_release_files] failed to fetch release metadata"
    cd "$_pwd"
    return 1
  fi

  echo "$release_json" | python3 -c "
import sys, json
assets = json.load(sys.stdin).get('assets', [])
for a in assets:
    print(a['id'], a['name'])
" | while read -r asset_id asset_name; do
    info "[download_github_release_files] downloading asset: $asset_name (id: $asset_id)"
    eval curl -fsSL "$AUTH_HEADER" \
      -H "\"Accept: application/octet-stream\"" \
      -o "\"$asset_name\"" \
      "\"https://api.github.com/repos/$REPO/releases/assets/$asset_id\""
    if [ "$?" -ne "0" ]; then
      err "[download_github_release_files] failed to download asset: $asset_name"
      cd "$_pwd"
      return 1
    fi
  done
  result="$?"
  cd "$_pwd"

  [ "$result" -ne "0" ] && err "[download_github_release_files|out] => ${result}" && return 1
  info "[download_github_release_files|out] => ${result}"
}

# add your custom bash functions above this line

# <=== MAIN SECTION END  <====

# ===> FOOTER SECTION START  ===>

usage() {
  cat <<EOM
  usage:
  $(basename "$0") { option }
    options:
      - reqs                        installs required tools and dependencies
      - test                        runs tests
      - build                       rebuild bashutils by concatenating all files in sections/
      - create_release_artifacts    create release artifacts in the dist directory
      - get_github_release <VERSION> [TARGET_DIR=this_folder] downloads bashutils from a specific GitHub release (assumes GITHUB_TOKEN is set)
EOM
  exit 1
}

# -------------------------------------


case "$1" in
  reqs)
    reqs
    ;;
  test)
    test
    ;;
  build)
    build_bashutils
    ;;
  download_bashutils_if_newer)
    download_bashutils_if_newer
    ;;
  create_release_artifacts)
    create_release_artifacts
    ;;
  create_github_release)
    create_github_release
    ;;
  get_github_release)
    download_github_release_files "$REPO" "$2" "${3:-$this_folder}"
    ;;
  *)
    usage
    ;;
esac

# <=== FOOTER SECTION END  <===
