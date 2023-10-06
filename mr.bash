#!/usr/bin/env bash
# https://github.com/vbem/multi-runners

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# common configurations

set -o pipefail

# directory and filename of this script
DIR_THIS="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
FILE_THIS="$(basename "${BASH_SOURCE[0]}")"
declare -rg DIR_THIS FILE_THIS

# only for local debug if .env file exists
[[ -f "$DIR_THIS/.env" ]] && source "$DIR_THIS/.env"

# environment variables for customization
# Github personal access token
declare -rg MR_GITHUB_PAT
# download URL of actions runner release, defaults to latest release on GitHub.com
declare -rg MR_RELEASE_URL
# baseurl of GitHub API, defaults to https://api.github.com
declare -rg MR_GIHUB_API_BASEURL="${MR_GIHUB_API_BASEURL:-https://api.github.com}"
# baseurl of GitHub service, defaults to https://github.com
declare -rg MR_GIHUB_BASEURL="${MR_GIHUB_BASEURL:-https://github.com}"
# runners' local username prefix, defaults to `runner-`
declare -rg MR_USER_PREFIX="${MR_USER_PREFIX:-runner-}"
# URL of this application
declare -rg MR_URL='https://github.com/vbem/multi-runners'

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# stdlib

# Log to stderr
#   $1: level string
#   $2: message string
#   stderr: logging message
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

# Check dependency of this application
#   $?: 0 if successful and non-zero otherwise
function mr::pretest {
    command -v jq > /dev/null || log::ifFailed 'Please intsall `jq`!' || return $?
    str::isVarNotEmpty MR_GIHUB_API_BASEURL MR_GIHUB_BASEURL || return $?
}

# Add a local user for runner
#   $1: username, defaults to self-increasing username
#   $?: 0 if successful and non-zero otherwise
#   stdout: username
function mr::addUser {
    local user="$1"
    if [[ -z "$user" ]]; then
        local -i index=0
        while :; do
            user="${MR_USER_PREFIX}$((index++))"
            id -u "$user" &> /dev/null || break
        done
    fi
    run::logIfFailed sudo tee /etc/sudoers.d/runners <<< '%runners ALL=(ALL) NOPASSWD:ALL' > /dev/null \
    && run::logIfFailed sudo groupadd -f 'runners' >&2 \
    && run::logIfFailed sudo groupadd -f 'docker' >&2 \
    && run::logIfFailed sudo useradd -m -s /bin/bash -G 'runners,docker' "$user" >&2 || return $?
    echo "$user"
}

# Print the number of processing units available to the current process
#   stdout: number, defaults to 2
function mr::nproc {
    local -i num=0;
    num="$(run::logIfFailed nproc)"
    (( num > 0 )) && echo "$num" || echo 2
}

# Get time-limited registration token from PAT
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners#checking-self-hosted-runner-network-connectivity
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners#authentication-requirements
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
#   $1: organization
#   $2: repository, registration on organization if empty
function mr::pat2token {
    local org="$1" repo="$2" api='' middle='' res=''
    str::isVarNotEmpty MR_GITHUB_PAT org || return $?
    mr::pretest || return $?

    [[ -z "$repo" ]] && middle="orgs/$org" || middle="repos/$org/$repo"
    api="$MR_GIHUB_API_BASEURL/$middle/actions/runners/registration-token"

    log::stderr DEBUG "Calling API: $api"
    res="$(curl -Lsm 3 --retry 1 \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${MR_GITHUB_PAT}" \
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
function mr::downloadRunner {
    local url="$MR_RELEASE_URL" tarpath=''

    if [[ -z "$url" ]]; then
        mr::pretest || return $?
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
#   $1: username, optional
#   $2: organization
#   $3: repository, optional
#   $4: runner registration token, optional
#   $5: extra labels, optional
#   $6: group, defaults to `default`
#   $7: lines to set in runner's '.env' files, optional
#   $?: 0 if successful and non-zero otherwise
function mr::addRunner {
    local user="$1" org="$2" repo="$3" token="$4" extraLabels="$5" group="${6:-default}" dotenv="$7" tarpath=''
    str::isVarNotEmpty org || return $?
    tarpath="$(mr::downloadRunner)" || return $?
    [[ -z "$token" ]] && { token="$(mr::pat2token "$org" "$repo")" || return $?; }
    user="$(mr::addUser "$user")" || return $?

    local name="$user@$HOSTNAME"

    local labels="controller:${MR_URL#https://},username:$user,hostname:$HOSTNAME"
    [[ -r /etc/os-release ]] && labels="$labels,os:$(source /etc/os-release && echo $ID-$VERSION_ID)"
    [[ -n "$repo" ]] && labels="$labels,$org/$repo" || labels="$labels,$org"
    [[ -n "$extraLabels" ]] && labels="$labels,$extraLabels"

    local url=''
    [[ -n "$repo" ]] && url="$MR_GIHUB_BASEURL/$org/$repo" || url="$MR_GIHUB_BASEURL/$org"

    log::stderr DEBUG "Adding runner into local user '$user' for $url"
    run::logIfFailed sudo -Hiu "$user" -- bash -eo pipefail <<- __
        mkdir -p runner/mr.d && cd runner/mr.d
        echo -n '$org' > org && echo -n '$repo' > repo && echo -n '$url' > url
        echo -n '$name' > name && echo -n '$labels' > labels && echo -n '$tarpath' > tarpath
        cd .. && tar -xzf "$tarpath"
        echo "$dotenv" >> .env
        ./config.sh --unattended --replace --url '$url' --token '$token' --name '$name' --labels '$labels' --runnergroup '$group'
        sudo ./svc.sh install '$user' && sudo ./svc.sh start
__
}

# Delete GitHub Actions Runner by local username
#   $1: username
#   $2: organization, optional
#   $3: repository, optional
#   $4: runner registration token, optional
#   $?: 0 if successful and non-zero otherwise
function mr::delRunner {
    local user="$1" org="$2" repo="$3" token="$4"
    str::isVarNotEmpty user || return $?

    if [[ -z "$token" ]]; then
        [[ -z "$org" ]] && org="$(run::logIfFailed sudo -Hiu "$user" -- cat runner/mr.d/org)"
        [[ -z "$repo" ]] && repo="$(run::logIfFailed sudo -Hiu "$user" -- cat runner/mr.d/repo)"
        token="$(mr::pat2token "$org" "$repo")"
    fi

    log::stderr DEBUG "Deleting runner local user '$user'"
    run::logIfFailed sudo -Hiu "$user" -- bash <<- __
        cd runner
        sudo ./svc.sh stop && sudo ./svc.sh uninstall
        ./config.sh remove --token '$token'
__
    run::logIfFailed sudo userdel -rf "$user" || return $?
}

# List all runners
#   $?: 0 if successful and non-zero otherwise
#   stdout: all runners
function mr::listRunners {
    local users=''
    mr::pretest || return $?
    users="$(run::logIfFailed getent group 'runners' | cut -d: -f4 | tr ',' '\n')" || return $?
    while read -r user; do [[ -z "$user" ]] && continue
        echo -n "$user"
        echo -n " $(sudo -Hiu "$user" -- du -h --summarize|cut -f1)"
        echo -n " $(sudo -Hiu "$user" -- jq -Mcre .gitHubUrl runner/.runner)"
        echo
    done <<< "$users" # user
    run::logIfFailed systemctl list-units -al --no-pager 'actions.runner.*' >&2 || return $?
}

# Temporary test
function mr::test {
    :
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main

HELP="$FILE_THIS - $MR_URL

Environment variables:
  MR_GIHUB_BASEURL=$MR_GIHUB_BASEURL
  MR_GIHUB_API_BASEURL=$MR_GIHUB_API_BASEURL
  MR_RELEASE_URL=${MR_RELEASE_URL:-<latest on github.com/actions/runner/releases>}
  MR_GITHUB_PAT=${MR_GITHUB_PAT::11}${MR_GITHUB_PAT:+***}

Sub-commands:
  add       Add one self-hosted runner on this host
            e.g. $FILE_THIS add --org ORG --repo REPO --labels cloud:ali,region:cn-shanghai
  del       Delete one self-hosted runner on this host
            e.g. $FILE_THIS del --user runner-1
  list      List all runners on this host
            e.g. $FILE_THIS list
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on github.com/actions/runner/releases if MR_RELEASE_URL empty
            e.g. $FILE_THIS download
  pat2token Get runner registration token from GitHub PAT (MR_GITHUB_PAT)
            e.g. $FILE_THIS pat2token --org SOME_OWNER --repo SOME_REPO

Options:
  --org     GitHub organization name
  --repo    GitHub repository name, registration on organization-level if empty
  --user    Linux local username of runner
  --labels  Extra labels for the runner
  --token   Runner registration token, takes precedence over MR_GITHUB_PAT
  --dotenv  The lines to set in runner's '.env' files
  -h --help Show this help.
"
declare -rg HELP

# CLI arguments parser.
#   $?: 0 if successful and non-zero otherwise
function mr::main {
    local getopt_output='' subCmd=''
    local org='' repo='' user='' labels='' token='' group='' dotenv=''

    # parse options into variables
    getopt_output="$(getopt -o h -l help,org:,repo:,user:,labels:,token:,group:,dotenv: -n "$FILE_THIS" -- "$@")"
    log::ifFailed $? "getopt failed!" || return $?
    eval set -- "$getopt_output"

    while true; do
        case "$1" in
            -h|--help) echo -n "$HELP" && return ;;
            --org) org="$2"; shift 2 ;;
            --repo) repo="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --labels) labels="$2"; shift 2 ;;
            --token) token="$2"; shift 2 ;;
            --group) group="$2"; shift 2 ;;
            --dotenv) dotenv="$dotenv$2"$'\n'; shift 2 ;;
            --) shift ; break ;;
            *) log::stderr ERROR "Invalid option '$1'! See '$FILE_THIS help'."; return 255;;
        esac
    done

    # parse sub-commands into functions
    subCmd="$1"; shift
    case "$subCmd" in
        add) mr::addRunner "$user" "$org" "$repo" "$token" "$labels" "$group" "$dotenv";;
        del) mr::delRunner "$user" "$org" "$repo" "$token" ;;
        list) mr::listRunners ;;
        status) mr::statusRunner "$user" ;;
        download) mr::downloadRunner ;;
        pat2token) mr::pat2token "$org" "$repo" ;;
        help|'') echo -n "$HELP" >&2 ;;
        test) mr::test "$@" ;;
        *) log::stderr ERROR "Invalid command '$1'! See '$FILE_THIS help'."; return 255 ;;
    esac
}

mr::main "$@"