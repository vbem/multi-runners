#!/usr/bin/env bash
# https://github.com/vbem/rctl

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# common configurations

set -o pipefail

# directory and filename of this script
DIR_THIS="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
FILE_THIS="$(basename "${BASH_SOURCE[0]}")"
declare -rg DIR_THIS FILE_THIS

# only for local debug if .env file exists
[[ -f "$DIR_THIS/.env" ]] && source "$DIR_THIS/.env"

# enviroment variables for customization
# Github personal access token
declare -rg RCTL_GITHUB_PAT
# download url of actions runner release, defaults to latest release on GitHub.com
declare -rg RCTL_RELEASE_URL
# baseurl of GitHub API, defaults to https://api.github.com
declare -rg RCTL_GIHUB_API_BASEURL="${RCTL_GIHUB_API_BASEURL:-https://api.github.com}"
# baseurl of GitHub service, defaults to https://github.com
declare -rg RCTL_GIHUB_BASEURL="${RCTL_GIHUB_BASEURL:-https://github.com}"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# stdlib

# Log to stderr
#   $1: level string
#   $2: message string
#   stderr: loggin message
#   $?: always 0
function log::stderr {
    local each pos level datetime
    for each in "${FUNCNAME[@]}"; do \
        [[ "$each" != log::stderr ]] && \
        [[ "$each" != log::ifFailed ]] && \
        [[ "$each" != run::logDebug ]] && \
        [[ "$each" != run::logIfFailed ]] && \
        [[ "$each" != main ]] && \
        [[ "$each" != *::main ]] && \
        [[ "$each" != *::_* ]] && \
        pos="/$each$pos"
    done
    case "$1" in
        FATAL|ERR*)     level="\e[1;91m$1\e[0m" ;;
        WARN*)          level="\e[1;95m$1\e[0m" ;;
        INFO*|NOTICE)   level="\e[1;92m$1\e[0m" ;;
        DEBUG)          level="\e[1;96m$1\e[0m" ;;
        *)              level="\e[1;94m$1\e[0m" ;;
    esac
    datetime="\e[2;90m$(date -Isecond)\e[0m"
    echo -e "\e[2;97m[\e[0m$datetime $level \e[90m${pos:1}\e[0m\e[2;97m]\e[0m \e[93m$2\e[0m" >&2
    #echo "[$(date -Isecond) $1 ${pos:1}] $2" >&2
}

# Log if previous return code is none-zero
#   $1: previous return code
#   $2: message string
#   stderr: message string
#   $?: previous return code
function log::ifFailed {
    (( "$1" != 0 )) && log::stderr ERROR "$2"
    return "$1"
}

# Run command and log
#   $@: command line
#   stdout: stdout of command
#   stderr: message string
#   $?: return code of command
function run::logDebug {
    local level
    local -i ret
    log::stderr DEBUG "Running command: $*"
    "$@"
    ret=$?; (( ret == 0 )) && level='DEBUG' || level='WARN'
    log::stderr "$level" "Return $ret from command: $*"
    return $ret
}

# Run command and log if return code is none-zero
#   $@: command line
#   stdout: stdout of command
#   stderr: message string
#   $?: return code of command
function run::logIfFailed {
    local -i ret
    "$@"
    ret=$?; (( ret != 0 )) && log::stderr WARN "Return $ret from command: $*"
    return $ret
}

# Check if varible values of given varible names are not empty
#   $@: varible names
#   $?: 0 if non-empty and non-zero otherwise
function str::isVarNotEmpty {
    local eachVarName=''
    for eachVarName in "$@"; do
        [[ -n "${!eachVarName}" ]]
        log::ifFailed $? "Var '$eachVarName' is empty!" || return $?
    done
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# functions

# Setup the rctl local group
# https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user
#   $?: 0 if successful and non-zero otherwise
function rctl::setupGroup {
    run::logIfFailed sudo groupadd -f 'rctl' || return $?
    run::logIfFailed sudo groupadd -f 'docker' || return $?
    run::logIfFailed sudo tee /etc/sudoers.d/rctl <<< '%rctl ALL=(ALL) NOPASSWD:ALL' > /dev/null || return $?
}

# List all local users in group `rctl`
#   $?: 0 if successful and non-zero otherwise
#   stdout: line separated users
function rctl::listUsers {
    run::logIfFailed getent group 'rctl' | cut -d: -f4 | tr ',' '\n' || return $?
}

# Add local username
#   $1: username
#   $?: 0 if successful and non-zero otherwise
function rctl::addUser {
    local usr="$1"
    str::isVarNotEmpty usr || return $?
    rctl::setupGroup && run::logIfFailed sudo useradd -m -s /bin/bash -G 'rctl,docker' "$usr" || return $?
}

# Delete local username
#   $1: username
#   $?: 0 if successful and non-zero otherwise
function rctl::delUser {
    local usr="$1"
    str::isVarNotEmpty usr || return $?
    run::logIfFailed sudo userdel -rf "$usr" || return $?
}

# Get time-limited registration token from PAT
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners#checking-self-hosted-runner-network-connectivity
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners#authentication-requirements
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
#   $1: organization
#   $2: repository, registration on organization if empty
function rctl::pat2token {
    local org="$1" repo="$2" api='' middle='' res=''
    str::isVarNotEmpty RCTL_GITHUB_PAT org || return $?

    [[ -z "$repo" ]] && middle="orgs/$org" || middle="repos/$org/$repo"
    api="$RCTL_GIHUB_API_BASEURL/$middle/actions/runners/registration-token"

    log::stderr DEBUG "Calling $api for registration token"
    res="$(curl -Lsm 3 --retry 1 \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${RCTL_GITHUB_PAT}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api" )" || log::ifFailed $? "Call API failed: $api" || return $?
    jq -Mcre .token <<< "$res" || log::ifFailed $? "Parse registration-token failed! response: $res" || return $?
}

# Download and cache GitHub Actions Runner to local /tmp/
# https://github.com/actions/runner/releases
# https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
# https://github.com/actions/runner/blob/main/docs/start/envlinux.md#install-net-core-3x-linux-dependencies
#   $?: 0 if successful and non-zero otherwise
#   stdout: local path of downloaded file
function rctl::downloadRunner {
    local url="$RCTL_RELEASE_URL" tarpath=''

    if [[ -z "$url" ]]; then
        url="$(
            run::logIfFailed curl -Lsm 3 --retry 1 https://api.github.com/repos/actions/runner/releases/latest \
            | jq -Mcre '.assets[].browser_download_url|select(test("linux-x64-[^-]+\\.tar\\.gz"))'
        )" || return $?
    fi

    tarpath="/tmp/$(run::logIfFailed basename "$url")" || return $?
    if [[ ! -r "$tarpath" ]]; then
        log::stderr DEBUG "Downloading release $url"
        run::logIfFailed curl -Lm 600 --retry 1 "$url" -o "$tarpath.tmp" \
        && run::logIfFailed mv -f "$tarpath.tmp" "$tarpath" \
        && run::logIfFailed chmod a+r "$tarpath" \
        && run::logIfFailed tar -Oxzf "$tarpath" './bin/installdependencies.sh' | sudo bash >&2 \
        || return $?
    fi
    echo "$tarpath"
}

# Add GitHub Actions Runner by local username
#   $1: username
#   $2: organization
#   $3: repository, optional
#   $4: runner registration token, optional
#   $5: extra labels, optional
#   $6: group, defaults to `default`
#   $?: 0 if successful and non-zero otherwise
function rctl::addRunner {
    local usr="$1" org="$2" repo="$3" token="$4" extraLabels="$5" group="${6:-default}" \
          labels="controller:rctl,username:$usr,hostname:$HOSTNAME,org:$org" name="$usr@$HOSTNAME" url='' tarpath=''
    str::isVarNotEmpty usr org || return $?

    tarpath="$(rctl::downloadRunner)" || return $?

    [[ -z "$token" ]] && { token="$(rctl::pat2token "$org" "$repo")" || return $?; }

    rctl::addUser "$usr" || return $?

    [[ -n "$repo" ]] && url="$RCTL_GIHUB_BASEURL/$org/$repo" || url="$RCTL_GIHUB_BASEURL/$org"
    [[ -n "$repo" ]] && labels="$labels,repo:$repo"
    [[ -r /etc/os-release ]] && labels="$labels,os:$(source /etc/os-release && echo $ID-$VERSION_ID)"
    [[ -n "$extraLabels" ]] && labels="$labels,$extraLabels"

    log::stderr DEBUG "Adding runner in local user '$usr' for $url"
    run::logIfFailed sudo -Hiu "$usr" -- bash -eo pipefail <<- __
        mkdir -p runner/rctl.d && cd runner
        echo -n '$org' > rctl.d/org && echo -n '$repo' > rctl.d/repo
        tar -xzf "$tarpath"
        ./config.sh --unattended --replace --url '$url' --token '$token' --name '$name' --labels '$labels' --runnergroup '$group'
        sudo ./svc.sh install '$usr' && sudo ./svc.sh start
__
}

# Delete GitHub Actions Runner by local username
#   $1: username
#   $2: organization, optional
#   $3: repository, optional
#   $4: runner registration token, optional
#   $?: 0 if successful and non-zero otherwise
function rctl::delRunner {
    local usr="$1" org="$2" repo="$3" token="$4"
    str::isVarNotEmpty usr || return $?

    if [[ -z "$token" ]]; then
        if [[ -z "$org" ]]; then
            org="$(run::logIfFailed sudo -Hiu "$usr" -- cat runner/rctl.d/org)" \
            && repo="$(run::logIfFailed sudo -Hiu "$usr" -- cat runner/rctl.d/repo)" \
            || return $?
        fi
        token="$(rctl::pat2token "$org" "$repo")" || return $?
    fi

    log::stderr DEBUG "Deleting runner in local user '$usr'"
    run::logIfFailed sudo -Hiu "$usr" -- bash <<- __
        cd runner
        sudo ./svc.sh stop && sudo ./svc.sh uninstall
        ./config.sh remove --token '$token'
__
    rctl::delUser "$usr" || return $?
}

# Reset GitHub Actions Runner by local username
#   $@: see `rctl::addRunner` and `rctl::delRunner`
#   $?: see `rctl::addRunner`
function rctl::rstRunner {
    rctl::delRunner "$@"
    rctl::addRunner "$@"
}

# Display status of specified runner
#   $1: username, optional, list all if empty
#   $?: 0 if successful and non-zero otherwise
function rctl::statusRunner {
    local usr="$1"
    if [[ -z "$usr" ]]; then
        run::logIfFailed systemctl list-units -al --no-pager 'actions.runner.*' || return $?
    else
        run::logIfFailed sudo -Hiu "$usr" -- bash <<< "cd runner && sudo ./svc.sh status" || return $?
    fi
}

# Temporary test
function rctl::test {
    :
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main

HELP="$FILE_THIS - https://github.com/vbem/rctl

Environment variables:
  RCTL_GIHUB_BASEURL=$RCTL_GIHUB_BASEURL
  RCTL_GIHUB_API_BASEURL=$RCTL_GIHUB_API_BASEURL
  RCTL_RELEASE_URL=$RCTL_RELEASE_URL
  RCTL_GITHUB_PAT=${RCTL_GITHUB_PAT::11}${RCTL_GITHUB_PAT:+****}

Sub-commands:
  add       Add a self-hosted runner on this host
            e.g. $FILE_THIS add --usr runner-0 --org org-name --labels cloud:aliyun,region:cn-shanghai
  del       Delete a self-hosted runner on this host
            e.g. $FILE_THIS del --usr runner-1
  rst       Reset via attempt to del and then add
            e.g. $FILE_THIS reset --usr runner-2 --org org-name --repo repo-name
  status    Display status of specified runner
            e.g. $FILE_THIS status
            e.g. $FILE_THIS status --usr runner-3
  users     List all runners' username on this host
            e.g. $FILE_THIS users
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on https://github.com/actions/runner/releases if RCTL_RELEASE_URL empty.
            e.g. $FILE_THIS download
  pat2token Get runner registration token from GitHub PAT (RCTL_GITHUB_PAT)
            e.g. $FILE_THIS pat2token --org SOME_OWNER --repo SOME_REPO

Options:
  --usr     Linux local username of runner
  --org     GitHub organization name
  --repo    GitHub repository name, registration on organization-level if empty
  --labels  Extra labels for the runner
  --token   Runner registration token, takes precedence over RCTL_GITHUB_PAT
  -h --help Show this help.
"
declare -rg HELP

# CLI arguments parser.
#   $?: 0 if successful and non-zero otherwise
function rctl::main {
    local getopt_output='' subCmd=''
    local org='' repo='' usr='' labels='' token='' group=''

    # parse options into variables
    getopt_output="$(getopt -o h -l help,org:,repo:,usr:,labels:,token: -n "$FILE_THIS" -- "$@")"
    log::ifFailed $? "getopt failed!" || return $?
    eval set -- "$getopt_output"

    while true; do
        case "$1" in
            -h|--help) echo -n "$HELP" && return ;;
            --org) org="$2"; shift 2 ;;
            --repo) repo="$2"; shift 2 ;;
            --usr) usr="$2"; shift 2 ;;
            --labels) labels="$2"; shift 2 ;;
            --token) token="$2"; shift 2 ;;
            --group) group="$2"; shift 2 ;;
            --) shift ; break ;;
            *) log::stderr ERROR "Invalid option '$1'! See '$FILE_THIS help'."; return 255;;
        esac
    done

    # parse sub-commands into functions
    subCmd="$1"; shift
    case "$subCmd" in
        add) rctl::addRunner "$usr" "$org" "$repo" "$token" "$labels" "$group";;
        del) rctl::delRunner "$usr" "$org" "$repo" "$token" ;;
        rst) rctl::rstRunner "$usr" "$org" "$repo" "$token" "$labels" "$group";;
        status) rctl::statusRunner "$usr" ;;
        users) rctl::listUsers ;;
        download) rctl::downloadRunner ;;
        pat2token) rctl::pat2token "$org" "$repo" ;;
        help|'') echo -n "$HELP" >&2 ;;
        test) rctl::test "$@" ;;
        *) log::stderr ERROR "Invalid command '$1'! See '$FILE_THIS help'."; return 255 ;;
    esac
}

rctl::main "$@"
