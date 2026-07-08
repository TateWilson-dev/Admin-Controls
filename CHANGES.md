# Admin-Controls v5 — Changes

All changes below were syntax-validated with PowerShell 7.5.4 and the hook
logic was live-tested against Gitleaks 8.30.1 on Linux (8/8 scenarios passed).

## Fixed

1. **CLAUDE.md template was truncated.** The old template contained only the
   testing section and ended mid-code-block. Rewritten in full: secret rules,
   never-reveal-values, never weaken controls, feature-branch/PR workflow,
   never --no-verify, gitleaks pre-commit command, testing gate, and the
   before-push summary. **Rerun the repo bootstrap on every existing repo to
   push the complete version out** (it will open a baseline-update PR).

2. **Reruns no longer break against branch protection.** The script now
   compares template content against the repo (unchanged files are truly
   skipped) and, when branch protection is already active, applies changes
   via a PR on `pelycon/baseline-update` instead of a direct push that
   protection would reject. Note: the fine-grained token now needs
   **Pull requests: Read and write** for reruns, not just for
   -CreateTestPullRequest.

## Hardened

3. **Pinned versions + SHA256 verification everywhere.** Gitleaks 8.30.1 and
   PortableGit 2.55.0.2 are pinned in the device script with official
   checksums (x64 + arm64); downloads that fail verification are deleted and
   the script stops. security.yml pins ghcr.io/gitleaks/gitleaks:v8.30.1.
   Side benefit: no more anonymous GitHub API calls, so the 60-requests/hour
   per-IP rate limit can no longer break installs on a shared office network.

4. **Device installs are version-aware.** If the installed Gitleaks doesn't
   match the pinned version, rerunning the installer updates it — bumping the
   pin in the script now rolls out to devices on rerun without -ForceUpdate.

## Improved

5. **Pre-push scans only the outgoing commits** (parsed from the stdin ref
   list; new branches scan commits not on any remote). Pushes stay fast as
   history grows, and a pre-hook-era historical secret can no longer block
   every future push — the GitHub Actions scan remains the full-history
   backstop. Branch deletions are skipped safely.

6. **Hooks chain to repo-local hooks.** Global core.hooksPath used to
   silently disable each repo's own .git/hooks. The Pelycon hooks now exec
   the local pre-commit / pre-push (stdin forwarded) after the scan passes,
   and a failing local hook still blocks.

7. **Hooks are written with LF line endings** (UTF-8, no BOM) instead of
   Set-Content's CRLF — safer across sh implementations.

8. **security.yml:** push trigger narrowed to main (PRs already covered by
   the pull_request trigger — no more double runs) and a concurrency group
   cancels superseded runs.

9. **New templates/dependabot.yml** (weekly GitHub Actions updates), uploaded
   by the bootstrap as .github/dependabot.yml. Still enable Dependabot
   *alerts* + *security updates* per repo in GitHub Settings — that toggle
   has no file equivalent.

10. **README** rewritten to match the current state (was labeled v4 and
    referenced folders that no longer exist).

## How to apply

1. Review these files, then commit them to Admin-Controls through your own
   PR flow.
2. Rerun the repo bootstrap on every bootstrapped repo:
   `.\repo-bootstrap\Set-PelyconRepoSecurity.ps1 -Owner "OWNER" -Repo "REPO"`
   — each repo gets a `pelycon/baseline-update` PR with the fixed CLAUDE.md,
   pinned security.yml, and new dependabot.yml. Review and merge.
3. No action needed on developer machines for the hook fixes until each
   machine reruns the installer; when you want them rolled out, have devs
   rerun the one-liner from the guide (it detects the version pin and
   updates).

## Version bump procedure (new)

When bumping Gitleaks or PortableGit: update the version constants and SHA256
values at the top of Install-PelyconGitSecurity.ps1 (checksums come from the
official release assets), update the image tag in templates/security.yml,
commit via PR, rerun the repo bootstrap, and have devices rerun the
installer.
