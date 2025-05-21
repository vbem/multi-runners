# multi-runners

[![awesome-runners](https://img.shields.io/badge/listed%20on-awesome--runners-blue.svg)](https://github.com/jonico/awesome-runners)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/vbem/multi-runners?label=Release&logo=github)](https://github.com/vbem/multi-runners/releases)
[![Linter](https://github.com/vbem/multi-runners/actions/workflows/linter.yml/badge.svg)](https://github.com/vbem/multi-runners/actions/workflows/linter.yml)
![GitHub closed issues](https://img.shields.io/github/issues-closed/vbem/multi-runners?logo=github)

🌈🌈🌈 **Multi self-hosted GitHub action runners on single host!** 🌈🌈🌈

## Introduction

This application is designed for controlling multi [self-hosted GitHub Action runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) on single host, when [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller) is not feasible in your engineering environment. This application has following advantages:

- Single Linux host required.
- Single Bash script.
- Lightweight wrapper of [GitHub official self-hosted runner](https://github.com/actions/runner).
- Both *github.com* and *GitHub Enterprise* are support.
- Either *organization* or *repository* or *GitHub Cloud Enterprise* level runners are supported.

## Usage

```plain
mr.bash - https://github.com/vbem/multi-runners

Environment variables:
  MR_GITHUB_BASEURL=https://github.com
  MR_GITHUB_API_BASEURL=https://api.github.com
  MR_RELEASE_URL=<latest on github.com/actions/runner/releases>
  MR_USER_BASE=<default in /etc/default/useradd>
  MR_USER_PREFIX=runner-
  MR_GITHUB_PAT=ghp_***

Sub-commands:
  add       Add one self-hosted runner on this host
            e.g. ./mr.bash add --org ORG --repo REPO --labels cloud:ali,region:cn-shanghai
            e.g. ./mr.bash add --org ORG --count 3
  del       Delete one self-hosted runner on this host
            e.g. ./mr.bash del --user runner-1
            e.g. ./mr.bash del --org ORG --count 3
  list      List all runners on this host
            e.g. ./mr.bash list
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on github.com/actions/runner/releases if MR_RELEASE_URL empty
            e.g. ./mr.bash download
  pat2token Get runner registration token from GitHub PAT (MR_GITHUB_PAT)
            e.g. ./mr.bash pat2token --org SOME_OWNER --repo SOME_REPO

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
```

### Download this application

This application requires to be run under a Linux user with **non-password sudo permission** (e.g., `%runners ALL=(ALL) NOPASSWD:ALL`). It's also fine to run this application by `root`:

```bash
git clone https://github.com/vbem/multi-runners.git
cd multi-runners
./mr.bash --help
```

### Setup PAT

This application requires a [GitHub personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with smallest permissions and shortest expiration time. Only `add`/`del`/`pat2token` sub-commands need this PAT. You can remove it on *GitHub* after multi-runners' setup.

PAT types | Repository level runners | Organization level runners
--- | --- | ---
*Fine-grained PAT* (recommended) | Referring to [repository API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-a-repository), the `administration:write` permission is required. | Referring to [organization policy](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/setting-a-personal-access-token-policy-for-your-organization) & [organization API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-an-organization), the `organization_self_hosted_runners:write` permission is required.
*Classic PAT* | Referring to [repository API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-a-repository), need the `repo` scope | Refer to [organization API](https://docs.github.com/en/rest/actions/self-hosted-runners?apiVersion=2022-11-28#create-a-registration-token-for-an-organization), need the `admin:org` scope; if the repository is private, `repo` scope is also required.

During runtime, you can set your *PAT* in environment variable `MR_GITHUB_PAT`. **To simplify subsequent execution, you can define any environment variable in `.env` file**. For example,

```bash
# .env file under the directory of this application
MR_GITHUB_PAT='github_pat_***********'
ALL_PROXY=socks5h://localhost
```

You can run following command to check whether or not your PAT can generate [GitHub Actions runners' registration-token](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners#authentication-requirements):

```bash
./mr.bash pat2token --org <ORG-NAME> --repo <REPO-NAME>
```

### Download the latest version of GitHub Actions package

If environment variable `MR_RELEASE_URL` is empty, this application will download the [latest version of GitHub Actions runners tar package](https://github.com/actions/runner/releases) to local directory `/tmp/` during runtime.

```bash
./mr.bash download
```

If your Linux host is internet bandwidth limited, you can also manually upload it from laptop to `/tmp/<tar.gz file name>`, and set the `MR_RELEASE_URL` env in `.env` file, e.g. `/tmp/actions-runner-linux-x64-2.345.6.tar.gz`.

### GitHub Enterprise Server editions

*GitHub Enterprise Server* editions usually have different server and API URL prefixes comparing with *github.com*, you can set them in environment variables `MR_GITHUB_BASEURL` and `MR_GITHUB_API_BASEURL`.

### GitHub Enterprise Cloud level registration

For *GitHub Enterprise Cloud* level registration, you can specify the `--enterprise` option to set the *GitHub Enterprise Cloud* name.

### Setup multi-runners on single host

To setup multi-runners, you can simplify run following command multi times:

```bash
# 1 runner for repository `<ORG-NAME-1>/<REPO-NAME-1>`
./mr.bash add --org <ORG-NAME-1> --repo <REPO-NAME-1>

# 2 runners for repository `<ORG-NAME-1>/<REPO-NAME-2>`
./mr.bash add --org <ORG-NAME-1> --repo <REPO-NAME-2> --count 2

# 3 runners for organization `<ORG-NAME-2>`
./mr.bash add --org <ORG-NAME-2> --count 3
```

This application will create one Linux local user for one runner via `useradd` command. The *Base Directory* of these users is read from `HOME` setting in your `/etc/default/useradd` file by default (typically `/home`). You can also set it in environment variable `MR_USER_BASE` to override system-wide default.

### List all runners on current host

This application also integrated status check of runners.

```bash
./mr.bash list
```

Which outputs,

```bash
runner-0 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-1>
runner-1 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-2>
runner-2 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-2>
runner-3 537M running https://github.com/<ORG-NAME-2>
runner-4 537M running https://github.com/<ORG-NAME-2>
runner-5 537M running https://github.com/<ORG-NAME-2>
```

### Delete an existing runner

```bash
# delete an existing runner by its local Linux username.
./mr.bash del --user <runner-?>

# delete all runners for specific repository
./mr.bash del --org <ORG-NAME-1> --repo <REPO-NAME-2>

# delete multi runners by `--count` options.
./mr.bash del --org <ORG-NAME-2> --count 2
```

### Specify runner in workflow file

In [`jobs.<job_id>.runs-on`](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idruns-on), target runners can be based on the labels as follows via [GitHub context](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context):

```yaml
# For organization level self-hosted runners
runs-on: [self-hosted, '${{ github.repository_owner }}']

# For repository level self-hosted runners
runs-on: [self-hosted, '${{ github.repository }}']
```

### Set environment variables into runners process

As described in GitHub official document, there's an approach to [inject environment variables into runners process](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/using-a-proxy-server-with-self-hosted-runners#using-a-env-file-to-set-the-proxy-configuration) via the `.env` file before configuring or starting the self-hosted runners. This can be achieved via the `--dotenv` option, for example:

```bash
./mr.bash add --org <ORG> --repo <REPO> --dotenv 'TZ=Asia/Shanghai' --dotenv 'PATH=\$PATH:/mybin' --dotenv 'all_proxy=socks5h://localhost:1080'
```

Then the following lines will be added to `.env` file located in self-hosted runner's directory before its configuring and starting:

```plain
TZ=Asia/Shanghai
PATH=$PATH:/mybin
all_proxy=socks5h://localhost:1080
```

### Inject hook script before starting the runner service

This application also supports to inject a hook script before starting the [runner service](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/configuring-the-self-hosted-runner-application-as-a-service) via `MR_CMD_SVC_PRE_START` environment variable.

For example, you can limit the CPU and RAM usage of the runner service by modifying the unit file of the runner service. Add the following lines to the `.env` file under the directory of this application. Then this script will be executed just before starting the runner service - `./svc.sh start`.

```bash
MR_CMD_SVC_PRE_START="$(cat <<-'__HEREDOC__'
echo "🚀 Running custom commands before starting runner service."
name="$(<mr.d/name)"
echo "🚀 Runner: $name | User: $USER | Dir: $PWD"
source <( sed -n "1,$(grep -n '^UNIT_PATH=' svc.sh | cut -d: -f1)p" svc.sh )
echo "🚀 UNIT_PATH: $UNIT_PATH"
sudo sed -i -e '/^\[Service\]/a CPUQuota=50%' -e '/^\[Service\]/a MemoryMax=512M' "$UNIT_PATH"
sudo systemctl daemon-reload
echo "🚀 Updated unit file:"
cat "$UNIT_PATH"
__HEREDOC__
)"
```
