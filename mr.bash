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
# shellcheck disable=SC1091
[[ -r "$DIR_THIS/.env" ]] && source "$DIR_THIS/.env"

# environment variables for customization
# Github personal access token
declare -rg MR_GITHUB_PAT
# download URL of actions runner release, defaults to latest release on GitHub.com
declare -rg MR_RELEASE_URL
# baseurl of GitHub API, defaults to https://api.github.com
declare -rg MR_GITHUB_API_BASEURL="${MR_GITHUB_API_BASEURL:-https://api.github.com}"
# baseurl of GitHub service, defaults to https://github.com
declare -rg MR_GITHUB_BASEURL="${MR_GITHUB_BASEURL:-https://github.com}"
# runners' local username prefix, defaults to `runner-`
declare -rg MR_USER_PREFIX="${MR_USER_PREFIX:-runner-}"
# runners' local users base directory, overrides the `HOME` setting in `/etc/default/useradd`
declare -rg MR_USER_BASE
# URL of this application
declare -rg MR_URL='https://github.com/vbem/multi-runners'

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# stdlib

# Log to stderr
# https://misc.flogisoft.com/bash/tip_colors_and_formatting
#   $1: level string
#   $2: message string
#   $?: always 0
#   stderr: log message
function log::_ {
    local each pos color level datetime
    for each in "${FUNCNAME[@]}"; do
        [[ "$each" != log::_ ]] \
            && [[ "$each" != log::failed ]] \
            && [[ "$each" != run::logFailed ]] \
            && [[ "$each" != run::log ]] \
            && [[ "$each" != main ]] \
            && [[ "$each" != *::main ]] \
            && [[ "$each" != *::_* ]] \
            && pos="/$each$pos"
    done
    case "$1" in
        FATAL) color="5;1;91" ;;
        ERR*) color="1;91" ;;
        WARN*) color="95" ;;
        INFO* | NOTICE) color="92" ;;
        DEBUG) color="94" ;;
        *) color="96" ;;
    esac
    datetime="\e[3;2;90m$(date -Isecond)\e[0m"
    pos="\e[3;90m${pos:1}\e[0m"
    level="\e[1;3;${color}m$1\e[0m"
    echo -e "\e[2;97m[\e[0m$datetime ${pos} $level\e[2;97m]\e[0m \e[${color}m$2\e[0m" >&2
}

# Log if previous return code is none-zero
#   $1: previous return code
#   $2: message string
#   $?: previous return code
#   stderr: message string
function log::failed {
    (("$1" != 0)) && log::_ ERROR "$2"
    return "$1"
}

# Run command and log if return code is none-zero
#   $@: command line
#   $?: return code of command
#   stdout: stdout of command
#   stderr: message string
function run::logFailed {
    local -i ret
    "$@"
    ret=$?
    log::failed "$ret" "Return $ret from command: $*"
}

# Run command with log and log if return code is none-zero
#   $@: command line
#   $?: return code of command
#   stdout: stdout of command
#   stderr: message string
function run::log {
    log::_ DEBUG "Running: $*"
    run::logFailed "$@"
}

# Test commands exists
#   $@: commands
#   $?: 0 if successful and none-zero otherwise
#   stderr: message string
function run::exists {
    local each=''
    for each in "$@"; do
        command -v "$each" &>/dev/null
        log::failed $? "Not found command '$each'!" || return $?
    done
}

# Check if any variable value of given variable names is not empty
#   $@: variable names
#   $?: 0 if non-empty and non-zero otherwise
function str::anyVarNotEmpty {
    local each=''
    for each in "$@"; do
        [[ -n "${!each}" ]]
        log::failed $? "Var '$each' is empty!" || return $?
    done
}

# Check if any variable value of given variable names are not empty
#   $@: variable names
#   $?: 0 if non-empty and non-zero otherwise
function str::allVarsNotEmpty {
    local each=''
    for each in "$@"; do
        [[ -n "${!each}" ]] && return
    done
    log::failed 1 "Vars $* are all empty!" || return $?
}

# Check if variable value of given variable name is IN subsequent arguments
#   $1: variable name
#   $N: arguments as candidate set
#   $?: 0 if it's in and non-zero otherwise
function str::varIn {
    local varName="$1" varVal="${!1}" each=''
    shift
    str::anyVarNotEmpty varName || return $?
    for each in "$@"; do
        [[ "$each" == "$varVal" ]] && return
    done
    log::_ ERROR "Invalid value '$varVal' for variable '$varName'!"
    return 1
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# functions

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
            id -u "$user" &>/dev/null || break
        done
    fi
    useraddArgs=(-m -s /bin/bash -G 'runners,docker')
    [[ -n "$MR_USER_BASE" ]] && useraddArgs+=('-b' "$MR_USER_BASE")
    run::logFailed sudo tee /etc/sudoers.d/runners <<<'%runners ALL=(ALL) NOPASSWD:ALL' >/dev/null \
        && run::logFailed sudo groupadd -f 'runners' >&2 \
        && run::logFailed sudo groupadd -f 'docker' >&2 \
        && run::log sudo useradd "${useraddArgs[@]}" "$user" >&2 || return $?
    echo "$user"
}

# Print the number of processing units available to the current process
#   stdout: number, defaults to 2
function mr::nproc {
    local -i num=0
    num="$(run::logFailed nproc)"
    ((num > 0)) && echo "$num" || echo 2
}

# Get time-limited registration token from PAT
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners#checking-self-hosted-runner-network-connectivity
# https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners#authentication-requirements
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
#   $1: enterprise
#   $2: organization
#   $3: repository, registration on organization if empty
#   $?: 0 if successful and non-zero otherwise
#   stdout: registration token
function mr::pat2token {
    run::exists jq || return $?
    local enterprise="$1" org="$2" repo="$3" api='' middle='' res=''
    str::anyVarNotEmpty MR_GITHUB_PAT || return $?
    str::allVarsNotEmpty org enterprise || return $?

    if [[ -n "$enterprise" ]]; then
        middle="enterprises/$enterprise"
    elif [[ -z "$repo" ]]; then
        middle="orgs/$org"
    else
        middle="repos/$org/$repo"
    fi
    api="$MR_GITHUB_API_BASEURL/$middle/actions/runners/registration-token"

    log::_ DEBUG "Calling API: $api"
    res="$(curl -Lsm 3 --retry 1 \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${MR_GITHUB_PAT}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$api")" || log::failed $? "Call API failed: $api" || return $?

    jq -Mcre .token <<<"$res" || log::failed $? "Parse registration-token failed! response: $res" || return $?
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
        run::exists jq || return $?
        curlArgs=(-Lsm 3 --retry 1)
        # https://github.com/vbem/multi-runners/pull/16
        [[ -n "$MR_GITHUB_PAT" ]] && curlArgs+=('-H' "Authorization: Bearer ${MR_GITHUB_PAT}")
        url="$(
            curl "${curlArgs[@]}" https://api.github.com/repos/actions/runner/releases/latest \
                | jq -Mcre '.assets[].browser_download_url|select(test("linux-x64-[^-]+\\.tar\\.gz"))'
        )" || log::failed $? "Fetching latest version number failed, check PAT or rate limit!" || return $?
    fi

    tarpath="/tmp/$(run::logFailed basename "$url")" || return $?
    if [[ ! -r "$tarpath" ]]; then
        log::_ INFO "Downloading from $url to $tarpath"
        run::logFailed curl -Lm 600 --retry 1 "$url" -o "$tarpath.tmp" \
            && run::logFailed mv -f "$tarpath.tmp" "$tarpath" \
            && run::logFailed chmod a+r "$tarpath" || return $?
        log::_ INFO "Checking runner dependencies"
        run::logFailed tar -Oxzf "$tarpath" './bin/installdependencies.sh' | sudo bash >&2 || return $?
    fi
    echo "$tarpath"
}

# Add GitHub Actions Runner by local username
#   $1:  username, optional
#   $2:  enterprise
#   $3:  organization
#   $4:  repository, optional
#   $5:  runner registration token, optional
#   $6:  extra labels, optional
#   $7:  group, defaults to `default`
#   $8:  lines to set in runner's '.env' files, optional
#   $9:  count of runners, optional, defaults to 1
#   $10: extra options for `config.sh`, optional, such as `--no-default-labels`
#   $?: 0 if successful and non-zero otherwise
function mr::addRunner {
    local username="$1" enterprise="$2" org="$3" repo="$4" token="$5" extraLabels="$6" group="${7:-default}" dotenv="$8" opts="${10}" tarpath=''
    local -i count="${9:-1}"
    str::allVarsNotEmpty enterprise org || return $?

    [[ -n "$username" ]] && ((count > 1)) && {
        log::_ ERROR "Count must be 1 when username is given!"
        return 1
    }

    [[ -z "$token" ]] && { token="$(mr::pat2token "$enterprise" "$org" "$repo")" || return $?; }
    tarpath="$(mr::downloadRunner)" || return $?

    local commonLabels="controller:${MR_URL#https://},hostname:$HOSTNAME"
    commonLabels+=",createdtime:$(date --iso-8601=sec)"
    [[ -r /etc/os-release ]] && commonLabels+=",os:$(source /etc/os-release && echo "$ID-$VERSION_ID")"
    [[ -n "$extraLabels" ]] && commonLabels+=",$extraLabels"

    for i in $(seq 1 "$count"); do
        user="$(mr::addUser "$username")" || return $?
        local name="$user@$HOSTNAME"
        local labels="$commonLabels,username:$user"
        local url=''
        if [[ -n "$enterprise" ]]; then
            url="$MR_GITHUB_BASEURL/enterprises/$enterprise"
            labels+=",$enterprise"
        elif [[ -z "$repo" ]]; then
            url="$MR_GITHUB_BASEURL/$org"
            labels+=",$org"
        else
            url="$MR_GITHUB_BASEURL/$org/$repo"
            labels+=",$org/$repo"
        fi

        log::_ INFO "Installing runner $i in local user '$user' for $url"
        run::logFailed sudo su --login "$user" -- -eo pipefail <<-__
            mkdir -p runner/mr.d && cd runner/mr.d
            echo -n '$enterprise' > enterprise && echo -n '$org' > org && echo -n '$repo' > repo && echo -n '$url' > url
            echo -n '$name' > name && echo -n '$labels' > labels && echo -n '$tarpath' > tarpath
            cd .. && tar -xzf "$tarpath"
            echo "$dotenv" >> .env
            ./config.sh --unattended --replace --url '$url' --token '$token' --name '$name' --labels '$labels' --runnergroup '$group' $opts
            sudo ./svc.sh install '$user'
            if [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
                chcon -t bin_t ./runsvc.sh # https://github.com/vbem/multi-runners/issues/9
            fi
            sudo ./svc.sh start
__
        log::failed $? "Failed installing runner $i in local user '$user' for $url!" || return $?
    done
}

# Delete GitHub Actions Runner by local username
#   $1: username, option
#   $2: enterprise, optional
#   $3: organization, optional
#   $4: repository, optional
#   $5: runner registration token, optional
#   $6: count of runners, optional, defaults to 0 (all)
#   $7: extra options for `config.sh`, optional, such as `--local`
#   $?: 0 if successful and non-zero otherwise
function mr::delRunner {
    local user="$1" enterprise="$2" org="$3" repo="$4" token="$5" opts="$7"
    local -i count="${6:-0}"

    local -a removals=()
    if [[ -n "$user" ]]; then
        removals+=("$user")
    else
        existing="$(run::logFailed getent group 'runners' | cut -d: -f4 | tr ',' '\n' | sort -g)" || return $?
        while read -r each; do
            [[ -z "$each" ]] && continue
            ((count != 0)) && ((${#removals[@]} >= count)) && break
            each_enterprise="$(run::logFailed sudo -Hiu "$each" -- cat runner/mr.d/enterprise)"
            each_org="$(run::logFailed sudo -Hiu "$each" -- cat runner/mr.d/org)"
            each_repo="$(run::logFailed sudo -Hiu "$each" -- cat runner/mr.d/repo)"
            each_url="$(run::logFailed sudo -Hiu "$each" -- cat runner/mr.d/url)"
            if [[ "$enterprise" == "$each_enterprise" && "$org" == "$each_org" && "$repo" == "$each_repo" ]]; then
                log::_ DEBUG "Found local user '$each' to delete for $each_url"
                removals+=("$each")
            fi
        done <<<"$existing"
    fi

    for user in "${removals[@]}"; do
        log::_ INFO "Deleting runner in local user '$user'"
        if [[ -z "$token" ]]; then
            enterprise="$(run::logFailed sudo -Hiu "$user" -- cat runner/mr.d/enterprise)"
            org="$(run::logFailed sudo -Hiu "$user" -- cat runner/mr.d/org)"
            repo="$(run::logFailed sudo -Hiu "$user" -- cat runner/mr.d/repo)"
            token="$(mr::pat2token "$enterprise" "$org" "$repo")"
        fi
        run::logFailed sudo su --login "$user" -- <<-__
            cd runner
            sudo ./svc.sh stop && sudo ./svc.sh uninstall
            ./config.sh remove --token '$token' $opts
__
        run::log sudo userdel -rf "$user"
    done
}

# List all existing runners
#   $?: 0 if successful and non-zero otherwise
#   stdout: all runners
function mr::listRunners {
    log::_ INFO "Listing localhost all existing runners"
    run::exists jq || return $?
    local users=''
    users="$(run::logFailed getent group 'runners' | cut -d: -f4 | tr ',' '\n' | sort -g)" || return $?
    while read -r user; do
        [[ -z "$user" ]] && continue
        echo -n "$user"
        echo -n " $(sudo -Hiu "$user" -- du -h --summarize | cut -f1)"
        echo -n " $(sudo -Hiu "$user" -- jq -Mcre .gitHubUrl runner/.runner)"
        echo
    done <<<"$users" # user
    run::log systemctl list-units -al --no-pager 'actions.runner.*' >&2 || return $?
}

# Temporary test
function mr::test {
    log::_ INFO "Self testing ..."
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# main

HELP="$FILE_THIS - $MR_URL

Environment variables:
  MR_GITHUB_BASEURL=$MR_GITHUB_BASEURL
  MR_GITHUB_API_BASEURL=$MR_GITHUB_API_BASEURL
  MR_RELEASE_URL=${MR_RELEASE_URL:-<latest on github.com/actions/runner/releases>}
  MR_USER_BASE=${MR_USER_BASE:-<default in /etc/default/useradd>}
  MR_GITHUB_PAT=${MR_GITHUB_PAT::11}${MR_GITHUB_PAT:+***}

Sub-commands:
  add       Add one self-hosted runner on this host
            e.g. ${BASH_SOURCE[0]} add --org ORG --repo REPO --labels cloud:ali,region:cn-shanghai
            e.g. ${BASH_SOURCE[0]} add --org ORG --count 3
  del       Delete one self-hosted runner on this host
            e.g. ${BASH_SOURCE[0]} del --user runner-1
            e.g. ${BASH_SOURCE[0]} del --org ORG --count 3
  list      List all runners on this host
            e.g. ${BASH_SOURCE[0]} list
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on github.com/actions/runner/releases if MR_RELEASE_URL empty
            e.g. ${BASH_SOURCE[0]} download
  pat2token Get runner registration token from GitHub PAT (MR_GITHUB_PAT)
            e.g. ${BASH_SOURCE[0]} pat2token --org SOME_OWNER --repo SOME_REPO

Options:
  --enterprise  GitHub Cloud Enterprise name, optional
  --org         GitHub organization name
  --repo        GitHub repository name, registration on organization-level if empty
  --user        Linux local username of runner
  --labels      Extra labels for the runner
  --group       Runner group for the runner
  --token       Runner registration token, takes precedence over MR_GITHUB_PAT
  --dotenv      The lines to set in runner's '.env' files
  --count       The number to add or del, optional, defaults to 1 for add and all for del
  --opts        Extra options for 'config.sh', optional, such as '--no-default-labels'
  -h --help     Show this help.
"
declare -rg HELP

# CLI arguments parser.
#   $?: 0 if successful and non-zero otherwise
function mr::main {
    local getopt_output='' subCmd=''
    local org='' repo='' user='' labels='' token='' group='' dotenv='' count='' opts=''

    # parse options into variables
    getopt_output="$(getopt -o h -l help,enterprise:,org:,repo:,user:,labels:,token:,group:,dotenv:,count: -n "$FILE_THIS" -- "$@")"
    log::failed $? "getopt failed!" || return $?
    eval set -- "$getopt_output"

    while true; do
        case "$1" in
            -h | --help) echo -n "$HELP" && return ;;
            --enterprise)
                enterprise="$2"
                shift 2
                ;;
            --org)
                org="$2"
                shift 2
                ;;
            --repo)
                repo="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --labels)
                labels="$2"
                shift 2
                ;;
            --token)
                token="$2"
                shift 2
                ;;
            --group)
                group="$2"
                shift 2
                ;;
            --dotenv)
                dotenv+="$2"$'\n'
                shift 2
                ;;
            --count)
                count="$2"
                shift 2
                ;;
            --opts)
                opts="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                log::_ ERROR "Invalid option '$1'! See '$FILE_THIS help'."
                return 255
                ;;
        esac
    done

    # parse sub-commands into functions
    subCmd="$1"
    shift
    case "$subCmd" in
        add) mr::addRunner "$user" "$enterprise" "$org" "$repo" "$token" "$labels" "$group" "$dotenv" "$count" "$opts" ;;
        del) mr::delRunner "$user" "$enterprise" "$org" "$repo" "$token" "$count" "$opts" ;;
        list) mr::listRunners ;;
        status) mr::statusRunner "$user" ;;
        download) mr::downloadRunner ;;
        pat2token) mr::pat2token "$enterprise" "$org" "$repo" ;;
        help | '') echo -n "$HELP" >&2 ;;
        test) mr::test "$@" ;;
        *)
            log::_ ERROR "Invalid command '$1'! See '$FILE_THIS help'."
            return 255
            ;;
    esac
}

mr::main "$@"
