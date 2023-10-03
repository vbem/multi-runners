# multi-runners
[![Static Badge](https://img.shields.io/badge/self--hosted%20runners-teal?logo=GitHub&label=GitHub%20Actions)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
[![Linter](https://github.com/vbem/rctl/actions/workflows/linter.yml/badge.svg)](https://github.com/vbem/rctl/actions/workflows/linter.yml)

**Multi self-hosted GitHub action runners on same host!**

## Intorduction
This application is designed for controlling multi [self-hosted GitHub Action runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) on single host, when [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller) is not feasible in your engineering environment. This applciation has following advantages:
- Only Linux based hosts required.
- Simple as more as possible.
- Lightweight wapper of offcial self-hosted runner.
- Both *github.com* and *GitHub Enterprise* are suppport.
- Both *organizatuon* and *repository* level runners are supported.

## Usage
```text
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
  --token   Runner registration token, takes precedence over MR_GITHUB_PAT
  -h --help Show this help.
```

### Download this application
This applciation reuqires to be run under a Linux user with non-password sudo permission (`%runners ALL=(ALL) NOPASSWD:ALL`), such as `ec2-user` and etc. It's also fine to run this application as `root`:

```bash
git clone https://github.com/vbem/multi-runners.git
cd multi-runners
./mr.bash --help
```

### Setup PAT
This application requires a [GitHub personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with smallest permissions and shorest expiration time. Only `add`/`del`/`pat2token` sub-commands need this PAT. You can remove it on *GitHub* after multi-runners' setup.

PAT types | Repository level runners | Organization levle runners
--- | --- | ---
*Fine-grained PAT* (recommended) | assign the `administration` permission | assign the `organization_self_hosted_runners` permission
*Classic PAT* | assign the `repo` scope | assign the `manage_runners:org` scope

During runtime, you can set your *PAT* in environment varible `RCTL_GITHUB_PAT`. **To simplify subsequent execution, you can define any environment variable in `.env` file**. For example,

```bash
# .env file under the directory of this application
RCTL_GITHUB_PAT='github_pat_***********'
ENV_VAR_2=blablabla
```

You can run following command to check whether or not your PAT can generate [GitHub Actions runners' registration-token](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners#authentication-requirements):
```bash
./mr.bash pat2token --org <ORG-NAME> --repo <REPO-NAME>
```

### Download the latest version of GitHub Actions package
If environment variable `MR_RELEASE_URL` is empty, this applciation will download the [latest version of GitHub Actions runners tar package](https://github.com/actions/runner/releases) to local directory `/tmp/` during runtime.

```bash
./mr.bash download
```

If limited by slow download speed, you can also manually download it to `/tmp/`, and set the `MR_RELEASE_URL` env as `/tmp/actions-runner-linux-x64-2.345.6.tar.gz`.

### GitHub Enterprise Server editions
*GitHub Enterprise Server* editions usally have differnt server and API URL prefies then *github.com*, you can set them in environment variables `MR_GIHUB_BASEURL` and `MR_GIHUB_API_BASEURL`.

### Setup multi-runners on single host
To setup multi-runners, you can simplify run following command mult times:
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
This application also wrappered status check of runners.
```bash
./mr.bash list
```
Which outpus,
```bash
runner-0 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-1>
runner-1 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-2>
runner-2 537M running https://github.com/<ORG-NAME-1>/<REPO-NAME-2>
runner-3 537M running https://github.com/<ORG-NAME-2>
runner-4 537M running https://github.com/<ORG-NAME-2>
runner-5 537M running https://github.com/<ORG-NAME-2>
```

### Delete an existing runner
You can delete an existing runner by its Linux username.
```bash
./mr.bash del --user <runner-?>
```

### Specify runner in workflow file
In [`jobs.<job_id>.runs-on`](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idruns-on), target runners can be based on the labels as follows via [GitHub context](https://docs.github.com/en/actions/learn-github-actions/contexts#github-context):
```yaml
# For organization level self-hosted runners
runs-on: [self-hosted, ${{ github.repository_owner }}]

# For repository level self-hosted runners
runs-on: [self-hosted, ${{ github.repository }}]
```