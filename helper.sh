#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1090,SC2181,SC2164,SC2086,SC2002,SC1091,SC2038,SC2155

# ===> HEADER SECTION START  ===>

# http://bash.cumulonim.biz/NullGlob.html
shopt -s nullglob

this_folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -z "$this_folder" ]; then
  this_folder=$(dirname "$(readlink -f "$0")")
fi
parent_folder=$(dirname "$this_folder")

# ------- CONSTANTS -------
export FILE_VARIABLES=${FILE_VARIABLES:-".variables"}
export FILE_LOCAL_VARIABLES=${FILE_LOCAL_VARIABLES:-".local_variables"}
export FILE_SECRETS=${FILE_SECRETS:-".secrets"}
export INCLUDE_FILE=${INCLUDE_FILE:-".bashutils"}

export BASHUTILS_URL=${BASHUTILS_URL:-"https://novonordisk.ghe.com/api/v3/repos/novonordisk/lib-dataops/contents/.bashutils"}
export BASHUTILS_CHECKSUM_URL=${BASHUTILS_CHECKSUM_URL:-"https://novonordisk.ghe.com/api/v3/repos/novonordisk/lib-dataops/contents/.bashutils.checksum"}
export BASHUTILS_CHECK_INTERVAL_SECONDS=${BASHUTILS_CHECK_INTERVAL_SECONDS:-"86400"}

# ------- header functions -------

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
    -H "Authorization: Bearer $GITHUB_TOKEN" \
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
      -H "Authorization: Bearer $GITHUB_TOKEN" \
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

# ------- source variables files
source_if_exists "$this_folder/$FILE_VARIABLES"
source_if_exists "$this_folder/$FILE_LOCAL_VARIABLES"
source_if_exists "$this_folder/$FILE_SECRETS"

# ------- include bashutils -------
BASHUTILS_UPDATE="${BASHUTILS_UPDATE:-0}"
[ "$BASHUTILS_UPDATE" -eq "1" ] && download_bashutils_if_newer
. "$this_folder/$INCLUDE_FILE"

# <=== HEADER SECTION END  <===

# =======>    MAIN SECTION    =======>

# ------- CONSTANTS -------
export SRC_DIR=${SRC_DIR:-"${this_folder}/src"}
export TEST_DIR=${TEST_DIR:-"${this_folder}/tests"}

# ------- main functions -------

OSTYPE=$(uname)

dev_reqs(){
  info "[dev_reqs|in]"
  _pwd=$(pwd)
  cd "$this_folder" || exit 1

  which gh > /dev/null 2>&1
  if [ "$?" -ne "0" ]; then
    info "[dev_reqs] gh cli is not found, installing it..."

    if [ "$OSTYPE" == "Darwin" ]; then
      brew install gh
      [ "$?" -ne "0" ] && err "[dev_reqs] could not install gh" && exit 1
    elif [[ "$OSTYPE" == "Linux"* ]]; then
      (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
      && sudo mkdir -p -m 755 /etc/apt/keyrings \
      && out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
      && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
      && sudo mkdir -p -m 755 /etc/apt/sources.list.d \
      && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
      && sudo apt update \
      && sudo apt install gh -y
      [ "$?" -ne "0" ] && err "[dev_reqs] could not install gh" && exit 1
    else
    	err "[dev_reqs|out] not supporting this OS: ${OSTYPE}" && exit 1
    fi
  fi

  cd "$_pwd" || exit 1
  info "[dev_reqs|out]"
}

check_approval(){
  info "[check_approval|in] ($1, $2, $3, $4)"
  
  [ -z "$1" ] && err "[check_approval] missing argument: REPO" && exit 1
  local REPO="$1"
  [ -z "$2" ] && err "[check_approval] missing argument: GH_ENV" && exit 1
  local GH_ENV="$2"
  [ -z "$3" ] && err "[check_approval] missing argument: COMMIT_SHA" && exit 1
  local COMMIT_SHA="$3"
  [ -z "$4" ] && err "[check_approval] missing argument: GITHUB_RUN_ID" && exit 1
  local GITHUB_RUN_ID="$4"
  [ -z "$5" ] && err "[check_approval] missing argument: APPROVAL_DOC" && exit 1
  local APPROVAL_DOC="$5"
  [ -z "$6" ] && err "[check_approval] missing argument: APPROVAL_HEADER" && exit 1
  local APPROVAL_HEADER="$6"


        #   {
        #     "role": "${{ needs.resolve-config.outputs.approval-role-validation-lead }}",
        #     "gateName": "validation_lead_approval_validation_report",
        #     "approvers": "MHCG RVEE",
        #     "approvalText": "I (Validation Lead / Delegate) approve that the validation report lives up to the requirements and that the report is transferred to QualityDocs and approved to a major version"
        #   },
        #   {
        #     "role": "${{ needs.resolve-config.outputs.approval-role-peer }}",
        #     "gateName": "NextGenSafety_peer_validation_report_prd",
        #     "approvers": "PSMW MSCX SDZL",
        #     "approvalText": "I (System Owner / Delegate / Data Product Owner) approve that the validation report lives up to the requirements."
        #   }
  # Get the latest deployment for this sha+environment
  local deployment_id=$(gh api \
    "/repos/${REPO}/deployments?environment=${GH_ENV}&sha=${COMMIT_SHA}&per_page=1" \
    --jq '.[0].id')
  [ -z "$deployment_id" ] && err "[check_approval] no deployment found for environment '${GH_ENV}' and commit '${COMMIT_SHA}'" && exit 1
  info "[check_approval] deployment id: $deployment_id"

  # Get the deployment success timestamp
  local approval_ts=$(gh api "/repos/${REPO}/deployments/${deployment_id}/statuses" --jq '.[] | select(.state=="success") | .updated_at')
  [ -z "$approval_ts" ] && err "[check_approval] no successful deployment status found for deployment id '${deployment_id}'" && exit 1
  info "[check_approval] approval timestamp: $approval_ts"

  local approval=$(gh api "/repos/${REPO}/actions/runs/${GITHUB_RUN_ID}/approvals" --jq '.[] | select(.state=="approved") | select(any(.environments[]; .name=="'"${GH_ENV}"'")  )')
  [ -z "$approval" ] && err "[check_approval] no approval found for environment '${GH_ENV}' and commit '${COMMIT_SHA}'" && exit 1
  info "[check_approval] approval: $approval"

  echo "$approval" | jq -r '.user.login'
  
  local approver=$(echo "$approval" | jq -r '.user.login' | tr -d '"')
  [ -z "$approver" ] && err "[check_approval] no approver found for environment '${GH_ENV}' and commit '${COMMIT_SHA}'" && exit 1
  info "[check_approval] approver: $approver"

  local approver_comment=$(echo "$approval" | jq -r '.comment' | tr -d '"')
  [ -z "$approver_comment" ] && err "[check_approval] no approver comment found for environment '${GH_ENV}' and commit '${COMMIT_SHA}'" && exit 1
  info "[check_approval] approver comment: $approver_comment"


  echo "$APPROVAL_HEADER" > "$APPROVAL_DOC"
  echo "Approval timestamp: $approval_ts" >> "$APPROVAL_DOC"
  echo "Approver: $approver" >> "$APPROVAL_DOC"
  echo "Comment: $approver_comment" >> "$APPROVAL_DOC"
  cat "$APPROVAL_DOC" >> "$GITHUB_STEP_SUMMARY"

  info "[check_approval|out]"
}


# -------------------------------------
usage() {
  cat <<EOM
  usage:
  $(basename "$0") { option }
    options:

      - reqs                    installs development requirements
      - check_approval <REPO> <GH_ENV> <COMMIT_SHA> <GITHUB_RUN_ID> <APPROVAL_DOC> <APPROVAL_HEADER>
                                checks if the deployment has been approved for a given repo, environment, commit sha, and GitHub run ID

EOM
  exit 1
}


case "$1" in
  reqs)
    dev_reqs
    ;;
  check_approval)
    check_approval "$2" "$3" "$4" "$5" "$6" "$7"
    ;;
  *)
    usage
    ;;
esac
