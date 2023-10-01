# rctl
[![Static Badge](https://img.shields.io/badge/self--hosted%20runners-teal?logo=GitHub&label=GitHub%20Actions)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
[![Linter](https://github.com/vbem/rctl/actions/workflows/linter.yml/badge.svg)](https://github.com/vbem/rctl/actions/workflows/linter.yml)

Yet another GitHub action runners controller - **Multi self-hosted runners on same VM**!

## PAT
This application a [GitHub personal access token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with smallest permissions and shorest expiration time:

PAT types | Repository level runners | Organization levle runners
--- | --- | ---
*Fine-grained PAT* (recommended) | assign the `administration` permission | assign the `organization_self_hosted_runners` permission
*Classic PAT* | assign the `repo` scope | assign the `manage_runners:org` scope

During runtime, set *PAT* in the environment varible named `RCTL_GITHUB_PAT`, such as in a `.env` file.

## Usage
```text
rctl.bash - https://github.com/vbem/rctl

Environment variables:
  RCTL_GIHUB_BASEURL=https://github.com
  RCTL_GIHUB_API_BASEURL=https://api.github.com
  RCTL_RELEASE_URL=
  RCTL_GITHUB_PAT=ghp_45ExfQj****

Sub-commands:
  add       Add a self-hosted runner on this host
            e.g. rctl.bash add --usr runner-0 --org org-name --labels cloud:aliyun,region:cn-shanghai
  del       Delete a self-hosted runner on this host
            e.g. rctl.bash del --usr runner-1
  rst       Reset via attempt to del and then add
            e.g. rctl.bash reset --usr runner-2 --org org-name --repo repo-name
  status    Display status of specified runner
            e.g. rctl.bash status
            e.g. rctl.bash status --usr runner-3
  users     List all runners' username on this host
            e.g. rctl.bash users
  download  Download GitHub Actions Runner release tar to /tmp/
            Detect latest on https://github.com/actions/runner/releases if RCTL_RELEASE_URL empty.
            e.g. rctl.bash download
  pat2token Get runner registration token from GitHub PAT (RCTL_GITHUB_PAT)
            e.g. rctl.bash pat2token --org SOME_OWNER --repo SOME_REPO

Options:
  --usr     Linux local username of runner
  --org     GitHub organization name
  --repo    GitHub repository name, registration on organization-level if empty
  --labels  Extra labels for the runner
  --token   Runner registration token, takes precedence over RCTL_GITHUB_PAT
  -h --help Show this help.
```
