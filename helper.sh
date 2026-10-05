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
export REPO="tgedr/bashutils"

find_local_release(){
  local local_file="$this_folder/$INCLUDE_FILE"
  local local_version=0
  if [ -f "$local_file" ]; then
    IFS= read -r version_line < "$local_file"
    local_version=${version_line##*: }
    # info "[find_local_release] local version: $local_version"
    if [[ ! $local_version =~ ^[0-9]+$ ]]; then
      err "[find_local_release] version is not a valid integer: $local_version"
      return 1
    fi
  fi
  echo "$local_version"
}

find_latest_release(){
  [ -z $1 ] && err "[find_latest_release] missing argument REPO" && return 1
  local REPO="$1"
  local latest_release
  latest_release=$(gh release view --repo "$REPO" --json tagName --jq .tagName) || return 1
  echo "$latest_release"
}

define_release_to_update(){
  local local_release
  local latest_release
  local_release=$(find_local_release)
  [ "$?" -ne "0" ] && err "[update_bashutils] failed to find local release" && return 1
  latest_release=$(find_latest_release "$REPO")
  [ "$?" -ne "0" ] && err "[update_bashutils] failed to find latest release" && return 1
  local result
  if (( local_release < latest_release )); then
    read -r -p "proceed to update? [y/N] " answer
    case "$answer" in
      [Yy])
        result="$latest_release"
        ;;
      *)
        result=-1 # cancelled
        ;;
    esac
  else
    result=-2 # local release is up-to-date
  fi
  echo "$result"
}

update_bashutils(){
  info "[update_bashutils|in] ($1)"

  [ -z "$BASHUTILS_AUTO_UPDATE" ] || [ "$BASHUTILS_AUTO_UPDATE" -ne "1" ] && warn "[update_bashutils] auto update is disabled" && return 1

  local _pwd=$(pwd)
  local release
  local result

  release=$(define_release_to_update)
  [ "$?" -ne "0" ] && err "[update_bashutils] failed to define the release to update" && return 1
  [ "$release" -eq "-1" ] && info "[update_bashutils] no update performed, update cancelled" && return 0
  [ "$release" -eq "-2" ] && info "[update_bashutils] no update performed, local release is up-to-date" && return 0

  # Use assets API with Accept: application/octet-stream to avoid redirect to
  # objects.githubusercontent.com (which may be blocked by proxies like Zscaler)
  local release_json
  release_json=$(eval curl -fsSL "\"https://api.github.com/repos/$REPO/releases/tags/$release\"")
  result="$?"
  if [ "$result" -ne "0" ]; then
    err "[update_bashutils] failed to fetch release metadata"
    cd "$_pwd"
    return 1
  fi

  cd "$this_folder" || exit 1

  echo "$release_json" | python3 -c "
  import sys, json
  assets = json.load(sys.stdin).get('assets', [])
  for a in assets:
      print(a['id'], a['name'])
  " | while read -r asset_id asset_name; do
    info "[get_updated_release] downloading asset: $asset_name (id: $asset_id)"
    eval curl -fsSL -H "\"Accept: application/octet-stream\"" \
      -o "\"$asset_name\"" \
      "\"https://api.github.com/repos/$REPO/releases/assets/$asset_id\""
    if [ "$?" -ne "0" ]; then
      err "[get_updated_release] failed to download asset: $asset_name"
      cd "$_pwd"
      return 1
    fi
  done
  result="$?"
  cd "$_pwd"

  [ "$result" -ne "0" ] && err "[get_updated_release|out] => ${result}" && return 1
  info "[get_updated_release|out] => ${result}"
}

# -------------------------------
# --- source variables files
source_if_exists "$this_folder/$FILE_VARIABLES"
source_if_exists "$this_folder/$FILE_LOCAL_VARIABLES"
source_if_exists "$this_folder/$FILE_SECRETS"

# ---------- include bashutils ----------
BASHUTILS_AUTO_UPDATE="${BASHUTILS_AUTO_UPDATE:-0}"
update_bashutils
. "$this_folder/$INCLUDE_FILE"

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

bump_up_version(){
  info "[bump_up_version|in]"
  local version_file="$this_folder/.version"
  local version

  read -r value < "$version_file"
  version=$((10#$value + 1))
  info "[bump_up_version] incrementing version to $version"
  echo "$version" > "$version_file"
  info "[bump_up_version|out]"
}

build_bashutils(){
  info "[build_bashutils|in]"
  local sections_dir="$this_folder/sections"
  local dist_dir="$this_folder/dist"
  local out_file="$this_folder/$INCLUDE_FILE"
  local _pwd
  local checksum_result
  local version
  local version_file="$this_folder/.version"
  _pwd=$(pwd)

  [ ! -d "$sections_dir" ] && err "[build_bashutils] sections folder not found: $sections_dir" && exit 1

  local files
  files=("$sections_dir"/*.sh)
  [ ${#files[@]} -eq 0 ] && err "[build_bashutils] no .sh files found in $sections_dir" && exit 1

  read -r version < "$version_file"
  printf '%s\n' "# BASHUTILS VERSION: $version" > "$out_file"

  >> "$out_file"
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

  rm -rf "$dist_dir"
  mkdir -p "$dist_dir"
  cp "$out_file" "$dist_dir/" || { err "[create_release_artifacts] failed to move $INCLUDE_FILE to $dist_dir"; exit 1; }
  cp "${out_file}.checksum" "$dist_dir/" || { err "[create_release_artifacts] failed to move ${out_file}.checksum to $dist_dir"; exit 1; }
  info "[create_release_artifacts|out] => 0"
}

create_github_release(){
  info "[create_github_release|in]"

  local dist_dir="$this_folder/dist"
  local include_file="$dist_dir/$INCLUDE_FILE"
  local -a release_assets=()
  local asset

  IFS= read -r version_line < "$include_file"
  version=${version_line##*: }
  info "[create_github_release] creating release version: $version"

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



# add your custom bash functions above this line

# <=== MAIN SECTION END  <====

# ===> FOOTER SECTION START  ===>

usage() {
  cat <<EOM
  usage:
  $(basename "$0") { option }
    options:
      - update_bashutils [VERSION]  updates bashutils to the latest or a specific GitHub release
      - reqs                        installs required tools and dependencies
      - test                        runs tests
      - build                       rebuild bashutils by concatenating all files in sections/
      - create_release_artifacts    create release artifacts in the dist directory
      - create_release              create a new GitHub release for bashutils
EOM
  exit 1
}

# -------------------------------------

case "$1" in
  update_bashutils)
    BASHUTILS_AUTO_UPDATE=1 update_bashutils "$2"
    ;;
  reqs)
    reqs
    ;;
  test)
    test
    ;;
  bump_up_version)
    bump_up_version
    ;;
  build)
    build_bashutils
    ;;
  create_release_artifacts)
    create_release_artifacts
    ;;
  create_release)
    create_github_release
    ;;
  *)
    usage
    ;;
esac

# <=== FOOTER SECTION END  <===

