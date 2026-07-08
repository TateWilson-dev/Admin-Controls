# User Device Setup

Run this once per Windows device.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\device-bootstrap\windows\Install-PelyconGitSecurity.ps1
```

Optional self-test:

```powershell
.\device-bootstrap\windows\Install-PelyconGitSecurity.ps1 -RunSelfTest
```

After setup, close and reopen PowerShell, Git Bash, and Claude Code.

## What the user does after setup

The user works normally:

```powershell
git clone <repo-url>
cd <repo>
git checkout -b feature/my-change
git add .
git commit -m "update"
git push
```

Gitleaks runs automatically before commits and pushes.

## Important

Do not use `--no-verify` unless a Pelycon admin explicitly approves it.

The default setup redacts secret values so Claude Code and terminal screenshots do not expose actual secrets.
