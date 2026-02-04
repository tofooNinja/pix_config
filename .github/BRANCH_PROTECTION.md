# Branch Protection Setup

This document explains how to configure branch protection to require CI checks to pass before merging pull requests.

## Overview

Branch protection rules ensure that all CI checks must succeed before code can be merged into protected branches (main/master). This helps maintain code quality and prevents broken code from being merged.

## Required CI Checks

The following CI checks must pass before merging:

- **Nix Flake Check** - Validates flake structure and dependencies
- **Evaluate NixOS Configurations (px5n0)** - Ensures px5n0 configuration builds
- **Evaluate NixOS Configurations (px5n1)** - Ensures px5n1 configuration builds
- **Check Formatting** - Verifies code is properly formatted with nixpkgs-fmt

## Setup Methods

There are three ways to configure branch protection:

### Method 1: Using GitHub UI (Recommended for Quick Setup)

1. Navigate to your repository on GitHub
2. Go to **Settings** → **Branches**
3. Click **Add branch protection rule**
4. Configure the rule:
   - **Branch name pattern**: `main` (create another rule for `master` if needed)
   - Check **Require status checks to pass before merging**
   - Check **Require branches to be up to date before merging**
   - Search and select the required status checks:
     - `Nix Flake Check`
     - `Evaluate NixOS Configurations (px5n0)`
     - `Evaluate NixOS Configurations (px5n1)`
     - `Check Formatting`
5. Click **Create** or **Save changes**
6. Repeat for the `master` branch if your repository uses it

### Method 2: Using GitHub Settings App (Configuration as Code)

This repository includes a `.github/settings.yml` file that defines branch protection rules as code.

1. Install the [Settings GitHub App](https://github.com/apps/settings) on your repository
2. The app will automatically apply the configuration from `.github/settings.yml`
3. Any changes to `.github/settings.yml` will be applied automatically

**Benefits:**
- Configuration is version controlled
- Changes are auditable through git history
- Easy to replicate across repositories
- Can be reviewed in pull requests

### Method 3: Using GitHub API or CLI

You can also configure branch protection using the GitHub API or GitHub CLI (`gh`):

#### Using GitHub CLI:

```bash
# For main branch
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks[strict]=true \
  --field required_status_checks[contexts][]=Nix Flake Check \
  --field required_status_checks[contexts][]=Evaluate NixOS Configurations (px5n0) \
  --field required_status_checks[contexts][]=Evaluate NixOS Configurations (px5n1) \
  --field required_status_checks[contexts][]=Check Formatting \
  --field enforce_admins=false \
  --field required_pull_request_reviews=null

# For master branch (if applicable)
gh api repos/:owner/:repo/branches/master/protection \
  --method PUT \
  --field required_status_checks[strict]=true \
  --field required_status_checks[contexts][]=Nix Flake Check \
  --field required_status_checks[contexts][]=Evaluate NixOS Configurations (px5n0) \
  --field required_status_checks[contexts][]=Evaluate NixOS Configurations (px5n1) \
  --field required_status_checks[contexts][]=Check Formatting \
  --field enforce_admins=false \
  --field required_pull_request_reviews=null
```

Replace `:owner` and `:repo` with your GitHub username and repository name.

## Verifying Configuration

After setting up branch protection, you can verify it's working by:

1. Creating a test branch
2. Making a small change that would fail CI (e.g., introduce a formatting error)
3. Opening a pull request
4. Observing that the merge button is blocked until CI passes

## Troubleshooting

### Status check names don't match

If the required status checks don't appear as options:

1. Ensure at least one pull request has run with the CI workflow
2. Check that the job names in `.github/workflows/ci.yml` match exactly
3. The status check name format is: `<job-name>` or `<job-name> (<matrix-config>)`

### Status checks not running

If CI checks aren't running on pull requests:

1. Verify `.github/workflows/ci.yml` has `pull_request:` in the `on:` section
2. Check GitHub Actions are enabled for the repository
3. Review the Actions tab for any error messages

### Can't find status checks in UI

Status checks only appear in the branch protection UI after they've run at least once. To make them appear:

1. Create a test pull request
2. Wait for CI to run
3. Return to branch protection settings
4. The status checks should now be available in the dropdown

## Additional Protection Options

You may also want to consider enabling:

- **Require pull request reviews before merging**: Requires human approval
- **Require signed commits**: Ensures commit authenticity
- **Include administrators**: Enforces rules even for repository admins
- **Restrict who can push**: Limits direct pushes to specific users/teams

These can be configured in `.github/settings.yml` or through the GitHub UI.

## References

- [GitHub Branch Protection Documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub Settings App](https://github.com/apps/settings)
- [GitHub API - Branch Protection](https://docs.github.com/en/rest/branches/branch-protection)
