# Pelycon Secure Vibe Coding Bootstrap

This package contains the two bootstrap layers used for Pelycon's secure
AI-assisted coding workflow.

## Folder structure

```
Admin-Controls/
├─ device-bootstrap/
│  └─ windows/
│     └─ Install-PelyconGitSecurity.ps1
├─ repo-bootstrap/
│  ├─ Set-PelyconRepoSecurity.ps1
│  └─ templates/
│     ├─ CLAUDE.md
│     ├─ security.yml
│     ├─ dependabot.yml
│     ├─ gitleaks.toml
│     └─ gitleaksignore
└─ docs/
   ├─ User-Device-Setup.md
   ├─ Admin-Repo-Setup.md
   └─ Testing-Checklist.md
```

Template names are stored without leading dots (`templates/gitleaks.toml`,
`templates/gitleaksignore`) so they are not hidden or missed during uploads.
The repo bootstrap uploads them to GitHub as `.gitleaks.toml` and
`.gitleaksignore`.

## What each bootstrap does

### Device bootstrap

Run once per Windows user profile.

It installs/configures:

- Git (pinned PortableGit, SHA256-verified), if missing
- Gitleaks (pinned version, SHA256-verified), if missing or outdated
- Global Git hooks (LF line endings) with global `core.hooksPath`
- Redacted Gitleaks reports by default

After this, every commit and push from that device is scanned automatically.
The pre-push hook scans only the outgoing commits (fast, and a historical
finding cannot block every future push - the GitHub Actions scan remains the
full-history backstop). If a repository has its own local hooks in
`.git/hooks`, the Pelycon hooks chain to them after the scan passes.

### Repo bootstrap

Run once per GitHub repo by a Pelycon admin (and rerun whenever templates
change).

It configures:

- `CLAUDE.md`
- `.github/workflows/security.yml` (pinned Gitleaks version)
- `.github/dependabot.yml`
- `.gitleaks.toml` / `.gitleaksignore`
- squash-merge-only settings, auto-delete branches
- branch protection: required PR review, required `gitleaks` status check
- optional draft test PR (`-CreateTestPullRequest`)

Reruns compare content and skip unchanged files. Once branch protection is
active, changed templates are applied through a pull request on
`pelycon/baseline-update` (direct pushes to the protected branch are blocked
by design), so baseline changes go through the same review gate as any other
change.

## Version pinning

Tool versions and their SHA256 checksums are pinned at the top of
`Install-PelyconGitSecurity.ps1`, and the Gitleaks container tag is pinned in
`templates/security.yml`. Bump them deliberately after reviewing upstream
release notes, then rerun the bootstraps.

## Fake test secrets

Never store detector-shaped fake secrets as literal strings in this repo.
Test secrets are built at runtime by concatenating strings, so Gitleaks can
test real detection behavior without flagging the bootstrap source itself.
