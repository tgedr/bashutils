##########################################
#######  ------- assorted -------  #######
##########################################

############################
#   name: test_js_lambda
#   purpose: installs npm dependencies and runs Jest tests for a JavaScript Lambda function
#   parameters: $1 (path to the Lambda function directory containing package.json)
#   returns: 0 if install and tests succeed, nonzero otherwise
#   requires: npm, jest
############################
test_js_lambda(){
  info "[test_js_lambda|in] ({$1})"

  [ -z $1 ] && err "[test_js_lambda] missing argument FUNCTION_DIR" && return 1
  local FUNCTION_DIR="$1"
  local _pwd=$(pwd)
  local result
  cd "$FUNCTION_DIR" || return 1

  npm install || { result=$?; cd "$_pwd"; return "$result"; }
  jest
  result=$?
  cd "$_pwd" || return 1
  [ "$result" -ne "0" ] && err "[test_js_lambda|out]  => ${result}" && return "$result"
  info "[test_js_lambda|out] => ${result}"
}

############################
#   name: zip_js_lambda_function
#   purpose: packages a JavaScript Lambda function into a zip archive;
#            installs npm dependencies if package.json is present and excludes the bundled aws-sdk
#            (provided by the Lambda runtime) from the archive without deleting it from source
#   parameters: $1 (source directory), $2 (output zip file path), $3+ (files/folders to include in the zip)
#   returns: 0 on success, nonzero if installation or packaging fails
#   side-effects: runs npm install in the source directory; excludes aws-sdk only from the archive
#   requires: npm, zip
############################

zip_js_lambda_function(){
  info "[zip_js_lambda_function] ...( $@ )"
  local usage_msg=$'zip_js_lambda_function: zips a js lambda function:\nusage:\n    zip_js_lambda_function SRC_DIR ZIP_FILE { FILES FOLDERS ... }'

  verify_prereqs npm
  if [ ! "$?" -eq "0" ] ; then return 1; fi

  if [ -z "$3" ] ; then echo "$usage_msg" && return 1; fi

  local src_dir="$1"
  local zip_file="$2"
  local -a files=("${@:3}")

  local _pwd=$(pwd)
  cd "$src_dir" || return 1

  if [ -f "package.json" ]; then
    npm install &>/dev/null
    if [ ! "$?" -eq "0" ] ; then err "[zip_js_lambda_function] could not install dependencies" && cd "$_pwd" && return 1; fi
  fi

  rm -f "$zip_file"
  zip -9 -q -r "$zip_file" "${files[@]}" -x 'node_modules/aws-sdk/*' &>/dev/null
  if [ ! "$?" -eq "0" ] ; then err "[zip_js_lambda_function] could not zip it" && cd "$_pwd" && return 1; fi

  cd "$_pwd"
  info "[zip_js_lambda_function] ...done."
}

############################
#   name: get_function_release
#   purpose: downloads a named artifact from the latest GitHub release of a repository into this_folder
#   parameters: $1 (GitHub repository in 'owner/repo' format), $2 (artifact filename to match)
#   returns: 0 after the download pipeline completes
#   requires: curl, wget, this_folder
############################

get_function_release(){
  info "[get_function_release] ...( $@ )"
  local usage_msg=$'get_function_release: retrieves a function release artifact from github:\nusage:\n    get_function_release REPO ARTIFACT'

  if [ -z "$2" ] ; then echo "$usage_msg" && return 1; fi
  local repo="$1"
  local artifact="$2"

  local _pwd=$(pwd)
  cd "$this_folder"

  curl -s "https://api.github.com/repos/${repo}/releases/latest" \
  | grep "browser_download_url.*${artifact}" \
  | cut -d '"' -f 4 | wget -qi -

  cd "$_pwd"
  info "[get_function_release] ...done."
}

############################
#   name: download_function
#   purpose: downloads a named artifact from the latest GitHub release of a repository and saves it to a specific local file
#   parameters: $1 (GitHub repository in 'owner/repo' format), $2 (artifact filename to match), $3 (local destination file path)
#   returns: 0 on successful download, 1 if required arguments or the download are invalid
#   requires: curl, wget
############################

download_function(){
  info "[download_function|in] ...( $@ )"
  local usage_msg=$'download_function: downloads a function release artifact from github:\nusage:\n    download_function REPO ARTIFACT DESTINATION_FILE'

  if [ -z "$3" ] ; then echo "$usage_msg" && return 1; fi
  local repo="$1"
  local artifact="$2"
  local file="$3"

  curl -s "https://api.github.com/repos/${repo}/releases/latest" \
  | grep "browser_download_url.*${artifact}" \
  | cut -d '"' -f 4 | wget -O "$file" -qi  -
  if [ ! "$?" -eq "0" ]; then err "[download_function] curl command was not successful" && return 1; fi

  info "[download_function|out] ...done."
}

############################
#   name: call_grafana_api
#   purpose: makes an authenticated GET request to a Grafana API endpoint through a proxy/gateway,
#            passing both an Azure bearer token and a Grafana service account token
#   parameters: $1 (Azure OAuth2 access token), $2 (Grafana service account API token), $3 (Grafana API URL)
#   returns: 0 if the request succeeds, 1 if a required argument is missing or curl fails
#   requires: curl
############################

call_grafana_api(){
  info "[call_grafana_api|in] (${1:0:3}, ${2:0:3})"

  [ -z $1 ] && err "[call_grafana_api] missing argument AZURE_ACCESS_TOKEN" && return 1
  AZURE_ACCESS_TOKEN="$1"
  [ -z $2 ] && err "[call_grafana_api] missing argument GRAFANA_API_TOKEN" && return 1
  GRAFANA_API_TOKEN="$2"
  [ -z $3 ] && err "[call_grafana_api] missing argument GRAFANA_API_URL" && return 1
  GRAFANA_API_URL="$3"

  local response=$(curl -s -X GET "$GRAFANA_API_URL"  \
      -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
      -H "X-Bifrost-Grafana-SA: Bearer ${GRAFANA_API_TOKEN}" )
  result="$?"

  [ "$result" -ne "0" ] && err "[call_grafana_api|out]  => ${result}" && return 1
  info "[call_grafana_api|out] => ${response}"
}

############################
#   name: find_local_release
#   purpose: reads and prints the integer version from the first line of the local bashutils file
#   parameters: none
#   returns: 0 and prints the version (or 0 if the file is absent), 1 if the version is not an integer
#   requires: this_folder, INCLUDE_FILE
############################
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

############################
#   name: find_latest_release
#   purpose: retrieves and prints the latest published release tag for a GitHub repository
#   parameters: $1 (repository in 'owner/repo' format)
#   returns: 0 and prints the tag, or 1 if the repository is missing or gh fails
#   requires: gh
############################
find_latest_release(){
  [ -z $1 ] && err "[find_latest_release] missing argument REPO" && return 1
  local REPO="$1"
  local latest_release
  latest_release=$(gh release view --repo "$REPO" --json tagName --jq .tagName) || return 1
  echo "$latest_release"
}

############################
#   name: define_release_to_update
#   purpose: compares the local integer version with the latest release and prompts before selecting an update
#   parameters: none
#   returns: 0 and prints the selected release, -1 if the user cancels, -2 if up-to-date; nonzero on lookup failure
#   requires: BASHUTILS_REPO, find_local_release, find_latest_release, interactive stdin
############################
define_release_to_update(){
  local local_release
  local latest_release
  local_release=$(find_local_release)
  [ "$?" -ne "0" ] && err "[update_bashutils] failed to find local release" && return 1
  latest_release=$(find_latest_release "$BASHUTILS_REPO")
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

############################
#   name: update_bashutils
#   purpose: prompts to update the local bashutils file from the latest release and downloads its release assets
#   parameters: none
#   returns: 0 if updated, cancelled, or already current; 1 if updates are disabled or an operation fails
#   requires: BASHUTILS_AUTO_UPDATE, BASHUTILS_REPO, this_folder, define_release_to_update, curl, python3
#   side-effects: downloads release assets into this_folder
############################
update_bashutils(){
  info "[update_bashutils|in] ($1)"

  [ -z "$BASHUTILS_AUTO_UPDATE" ] || [ "$BASHUTILS_AUTO_UPDATE" -ne "1" ] && err "[update_bashutils] auto update is disabled" && return 1

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
  release_json=$(eval curl -fsSL "\"https://api.github.com/repos/$BASHUTILS_REPO/releases/tags/$release\"")
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
      "\"https://api.github.com/repos/$BASHUTILS_REPO/releases/assets/$asset_id\""
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