# Pelycon Secure Vibe Coding Bootstrap

This package contains the two bootstrap layers used for Pelycon's secure AI-assisted coding workflow.

## Folder structure

```text
pelycon-secure-vibe-coding-bootstrap/
├─ device-bootstrap/
│  └─ windows/
│     └─ Install-PelyconGitSecurity.ps1
├─ repo-bootstrap/
│  ├─ Set-PelyconRepoSecurity.ps1
│  └─ templates/
│     ├─ CLAUDE.md
│     ├─ security.yml
│     ├─ gitleaks.toml
│     └─ gitleaksignore
└─ docs/
   ├─ User-Device-Setup.md
   ├─ Admin-Repo-Setup.md
   └─ Testing-Checklist.md
```

## What to keep

Use this package as the clean baseline. You can delete older duplicate folders such as:

```text
pelycon-repo-security-v2
pelycon-repo-security-v3
old Set-PelyconRepoSecurity_v2.ps1 copies
old template test folders
```

The repo bootstrap here is the cleaned version that uses visible template names:

```text
templates/gitleaks.toml
templates/gitleaksignore
```

The script uploads those to GitHub as:

```text
.gitleaks.toml
.gitleaksignore
```

## What each bootstrap does

### Device bootstrap

Run once per Windows user profile.

It installs/configures:

- Git, if missing
- Gitleaks, if missing
- Global Git hooks
- Global `core.hooksPath`
- Redacted Gitleaks reports

After this, commits and pushes from that device are scanned automatically.

### Repo bootstrap

Run once per GitHub repo by a Pelycon admin.

It configures:

- `CLAUDE.md`
- `.github/workflows/security.yml`
- `.gitleaks.toml`
- `.gitleaksignore`
- squash merge settings
- auto-delete branches
- branch protection
- required PR review
- required `gitleaks` status check
- optional draft test PR


## v4 note

This version avoids storing detector-shaped fake secrets directly in the bootstrap repo. Test secrets are built at runtime by concatenating strings, so Gitleaks can still test real detection behavior without flagging the bootstrap source code itself.
