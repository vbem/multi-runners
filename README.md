# multi-runners
[![awesome-runners](https://img.shields.io/badge/listed%20on-awesome--runners-blue.svg)](https://github.com/jonico/awesome-runners)
[![GitHub release (latest SemVer)](https://img.shields.io/github/v/release/vbem/multi-runners?label=Release&logo=github)](https://github.com/vbem/multi-runners/releases)
[![Linter](https://github.com/vbem/multi-runners/actions/workflows/linter.yml/badge.svg)](https://github.com/vbem/multi-runners/actions/workflows/linter.yml)
![GitHub closed issues](https://img.shields.io/github/issues-closed/vbem/multi-runners?logo=github)

🌈🌈🌈 **Multi self-hosted GitHub action runners on single host!** 🌈🌈🌈

## Introduction
This application is designed for controlling multi [self-hosted GitHub Action runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) on single host, when [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller) is not feasible in your engineering environment. This application has following advantages:
- Only single Linux host required.
- Simple as more as possible, single Bash script.
- Lightweight wrapper of official self-hosted runner.
- Both *github.com* and *GitHub Enterprise* are support.
- Both *organization* and *repository* level runners are supported.

## Usage
```plain
mr.bash - https://github.com/vbem/multi-runners

Environment variables:
  MR_GIHUB_BASEURL=https://github.com
  MR_GIHUB_API_BASEURL=https://api.github.com
  MR_RELEASE_URL=<latest on github.com/actions/runner/releases>
  MR_GITHUB_PAT=github_pat_***

Sub-commands:
  add       Add one self-hosted runner on this host
            e.g. mr.bash add --org ORG --repo REPO --labels cloud:ali,region:cn-shanghai
  del       Delete one self-hosted runner on this host
            e.g. mr.bash del --user runner-1
  list      List all runners on this host
            e.g. mr.bash list
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on github.com/actions/runner/releases if MR_RELEASE_URL empty
            e.g. mr.bash download
  pat2token Get runner registration token from GitHub PAT (MR_GITHUB_PAT)
            e.g. mr.bash pat2token --org SOME_OWNER --repo SOME_REPO

Options:
  --org     GitHub organization name
  --repo    GitHub repository name, registration on organization-level if empty
  --user    Linux local username of runner
  --labels  Extra labels for the runner
  --group   Runner group for the runner
  --token   Runner registration token, takes precedence over MR_GITHUB_PAT
  --dotenv  The lines to set in runner's '.env' files
  -h --help Show this help.
```

### Download this application
This application requires to be run under a Linux user with **non-password sudo permission** (`%runners ALL=(ALL) NOPASSWD:ALL`). It's also fine to run this application by `root`:

```bash
git clone https://github.com/vbem/multi-runners.git
cd multi-runners
./mr.bash --help
```

### Setup PAT
This application requires a [GitHub personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with smallest permissions and shortest expiration time. Only `add`/`del`/`pat2token` sub-commands need this PAT. You can remove it on *GitHub* after multi-runners' setup.

PAT types | Repository level runners | Organization level runners
--- | --- | ---
*Fine-grained PAT* (recommended) | assign the `administration` permission | assign the `organization_self_hosted_runners` permission
*Classic PAT* | assign the `repo` scope | assign the `manage_runners:org` scope

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

If limited by slow download speed, you can also manually download it to `/tmp/`, and set the `MR_RELEASE_URL` env as `/tmp/actions-runner-linux-x64-2.345.6.tar.gz`.

### GitHub Enterprise Server editions
*GitHub Enterprise Server* editions usually have different server and API URL prefixes comparing with *github.com*, you can set them in environment variables `MR_GIHUB_BASEURL` and `MR_GIHUB_API_BASEURL`.

### Setup multi-runners on single host
To setup multi-runners, you can simplify run following command multi times:
```bash
# 1 runner for repository `<ORG-NAME-1>/<REPO-NAME-1>`
./mr.bash add --org <ORG-NAME-1> --repo <REPO-NAME-1>

# 2 runners for repository `<ORG-NAME-1>/<REPO-NAME-2>`
./mr.bash add --org <ORG-NAME-1> --repo <REPO-NAME-2>
./mr.bash add --org <ORG-NAME-1> --repo <REPO-NAME-2>

# 3 runners for organization `<ORG-NAME-2>`
./mr.bash add --org <ORG-NAME-2>
./mr.bash add --org <ORG-NAME-2>
./mr.bash add --org <ORG-NAME-2>
```

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
You can delete an existing runner by its local Linux username.
```bash
./mr.bash del --user <runner-?>
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
./mr.bash add --org <ORG> --repo <REPO> --dotenv 'TZ=Asia/Shanghai' --dotenv 'PATH=\$PATH:/mybin'
```
Then the following lines will be added to `.env` file located in self-hosted runner's directory before its configuring and starting:
```plain
TZ=Asia/Shanghai
PATH=$PATH:/mybin
```

## Case Study - Deploy multi runners on single host which can not access GitHub directly

A multi-national corporation adopted GitHub as its centralized engineering efficiency platform. But in a country branch, according to  some network blockade/bandwidth/QoS reasons, neither GitHub-hosted runners can access endpoints in this country stably, nor virtual machines in this country can access GitHub liberally.

In such a bad situation, we still need to setup reliable self-hosted runners in this country. What should we do? 🤣

A cost-conscious solution can be described as following architecture:
```plain
Endpoints <-------- VM-Runners ----> Firewall ----> VM-Proxy ----> GitHub
 \                          /                          |    \
  --------------------------                           |     ----> Other endpoints
     Branch office network                        Remote Proxy
```
A host *VM-Runners* is required for self-hosted runners, which is placed in this country and:
- Can access endpoints of this country branch
- Can NOT access *GitHub* directly or stably

A tiny specification host *VM-Proxy* is required as ***Remote Proxy***, which is deployed in a place that:
- Can access *GitHub* directly and stably
- Can be accessed by *VM-Runners* directly and stably

Meanwhile, **outbound traffics from *VM-Runners* MUST be routed by predefined rules**:
- [Requests to *GitHub* endpoints](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners#communication-requirements) and non-local endpoints should be forward to the *Remote Proxy* on *VM-Proxy*
- Requests to local endpoints should be handled directly

Let's implement this solution. 🧐

On *VM-Proxy*, we can setup a *Remote Proxy* that's not easy to be blocked by the firewall, such as [*SS*](https://github.com/shadowsocks), [*TJ*](https://github.com/trojan-gfw), [*XR*](https://github.com/XTLS), etc. These particular proxies have their own deployment and configuration methods. Please read their documents for more information. It's advised to set the outbound IP of *VM-Runners* as the only whitelist of the *Remote Proxy* port on *VM-Proxy* to avoid active detection from the firewall.

Before setup runners on *VM-Runners*, we need a [***Local Proxy***](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/using-a-proxy-server-with-self-hosted-runners) on *VM-Runners*.

Usually firstly we need to setup the client of selected *Remote Proxy* which exposes a SOCKS5 proxy on *VM-Runners* (this local SOCKS5 localhost port will unconditionally forward all traffics to *VM-Proxy*), and then setup a [*privoxy*](https://www.privoxy.org/) on top of previous local SOCKS5 for [domain based forwarding](https://www.privoxy.org/user-manual/config.html#SOCKS). These configurations are complex and prone to errors. Via [*Clash*](https://github.com/Dreamacro/clash), we can combine both client of *Remote Proxy* and domain based forwarding into only one *Local Proxy*. The example configuration file and startup script of *Clash* and given in this repo's [clash.example/](clash.example/) directory.

Assume the *Local Proxy* was launched as `socks5h://localhost:7890`, we can test it via following commands on *VM-Runners*:
```bash
# Without *Local Proxy*, it will print outbound public IP of *VM-Runners*
curl -s -4 icanhazip.com

# With *Local Proxy*, it will print outbound public IP of *VM-Proxy* !!!
all_proxy=socks5h://localhost:7890 curl -s -4 icanhazip.com
```

When *Local Proxy* is ready, we start self-hosted runners' setup on *VM-Runners*.

As *VM-Runners* Can NOT access *GitHub* directly or stably, use *Local Proxy* to clone this repository:
```bash
all_proxy=socks5h://localhost:7890 git clone https://github.com/vbem/multi-runners
cd multi-runners
```

As self-hosted runners' tar package downloading and registration-token fetching also requires communication with GitHub, we also configure *Local Proxy* for this application:
```bash
cat > .env <<- __
    MR_GITHUB_PAT='<paste-for-GitHub-PAT-here>'
    all_proxy='socks5h://localhost:7890'
__
```

To download the self-hosted runners' tar package from *GitHub*:
```bash
./mr.bash download
```

To validate your *PAT* has sufficient permissions for self-hosted runners registration on your GitHub organization `https://github.com/<ORG-NAME>`:
```bash
./mr.bash pat2token --org <ORG-NAME>
```

To setup two self-hosted runners on *VM-Runners* for your GitHub organization:
```bash
./mr.bash add --org <ORG-NAME> --dotenv 'all_proxy=socks5h://localhost:7890'
./mr.bash add --org <ORG-NAME> --dotenv 'all_proxy=socks5h://localhost:7890'
```

To check the status of self-hosted runners:
```bash
./mr.bash list
```

To check the *Local Proxy* works well in your runners' process, you can add a simple workflow `.github/workflows/test-local-proxy.yml` in your repository. If `icanhazip.com` was configured as a following-to-remote domain, the workflow run will print outbound public IP of *VM-Proxy*, even though this workflow actually runs on *VM-Proxy*.
```yaml
---
name: Test Local Proxy works in my self-hosted runners
on:
  workflow_dispatch:
jobs:
  test:
    runs-on: [self-hosted, '${{ github.repository }}']
    steps:
      - run: |
          curl -s -4 icanhazip.com
...
```
