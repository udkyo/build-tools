# Scripts for testing branch restriction

This utility checks if a change affects a restricted branch, and if so, whether the commit has appropriate approval in JIRA.

## Local Testing

For local testing, you want to run:

    uv run test-restriction


Run just that command for help. This will do either
restricted-manifest-check (for changes to the `manifest` project) or
restricted-branch-check (for any other changes).

## Usage Environments

### Gerrit

When running in Gerrit, the script uses environment variables set by the Gerrit trigger:
- `GERRIT_PROJECT`
- `GERRIT_BRANCH`
- `GERRIT_CHANGE_COMMIT_MESSAGE`
- `GERRIT_CHANGE_URL`
- `GERRIT_PATCHSET_NUMBER`
- `GERRIT_EVENT_TYPE`

JIRA credentials are read from `~/.ssh/cloud-jira-creds.json`.

### GitHub Actions

When running in GitHub Actions, the following environment variables must be set:
- `GITHUB_BASE_REF` - The target branch of the PR
- `GITHUB_REPOSITORY` - The repository name (e.g. "owner/repo")
- `GITHUB_TOKEN` - GitHub token with read access to repository
- `PR_NUMBER` - The PR number to check
- `JIRA_URL` - URL of the JIRA instance
- `JIRA_USER` - JIRA username
- `JIRA_API_PASS` - JIRA API token

To enable this on a new repo, set up the JIRA secrets at repo or org level
and add the following `.github/workflows/restricted-branch-check.yml`:

```
name: Restricted Branch Check

on:
  pull_request_target:
    types: [opened, reopened, synchronize]

jobs:
  run-check:
    uses: couchbase/build-tools/.github/workflows/restricted-branch-check.yml@main
    with:
      head_ref: ${{ github.event.pull_request.head.ref }}
      head_repo: ${{ github.event.pull_request.head.repo.full_name }}
      pr_number: ${{ github.event.pull_request.number }}
    secrets:
      JIRA_URL: ${{ secrets.JIRA_URL }}
      JIRA_USERNAME: ${{ secrets.JIRA_USERNAME }}
      JIRA_API_TOKEN: ${{ secrets.JIRA_API_TOKEN }}
```

Note: you must also enable branch protection rules to prevent PRs from being
merged if the branch is restricted. At a minimum, ensure your rule is active,
targets all branches, and requires status checks to pass (but does not require
status checks on creation) and that the action has been added to the required
status checks.
