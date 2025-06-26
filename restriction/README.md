# Scripts for testing branch restriction

This utility checks if a change affects a restricted branch, and if so, whether the commit has appropriate approval in JIRA.

## Local Testing

For local testing, you want to run:

    rye run test-restriction

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
- `PR_NUMBER` - The PR number to check
- `GITHUB_TOKEN` - GitHub token with read access to repository
- `JIRA_URL` - URL of the JIRA instance
- `JIRA_USER` - JIRA username
- `JIRA_API_PASS` - JIRA API token
