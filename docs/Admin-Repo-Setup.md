# Admin Repo Setup

Run this once per GitHub repo.

## Token permissions

Use a fine-grained GitHub personal access token scoped to the target repo with:

```text
Administration: Read and write
Contents: Read and write
Workflows: Read and write
Pull requests: Read and write
Metadata: Read-only
```

Set the token in PowerShell:

```powershell
$env:GITHUB_TOKEN = "paste-token-here"
```

## Dry run

From the package root:

```powershell
.\repo-bootstrap\Set-PelyconRepoSecurity.ps1 `
  -Owner "TateWilson-dev" `
  -Repo "repo-security-test" `
  -DryRun `
  -CreateTestPullRequest
```

## Apply

```powershell
.\repo-bootstrap\Set-PelyconRepoSecurity.ps1 `
  -Owner "TateWilson-dev" `
  -Repo "repo-security-test" `
  -CreateTestPullRequest
```

## What it creates in the repo

```text
CLAUDE.md
.github/workflows/security.yml
.gitleaks.toml
.gitleaksignore
```

The local template files use visible names so they do not get hidden:

```text
templates/gitleaks.toml
templates/gitleaksignore
```

The script uploads them as dotfiles in the repo.
