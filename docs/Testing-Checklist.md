# Testing Checklist

## 1. Confirm repo files

In GitHub, check the Code tab for:

```text
CLAUDE.md
.gitleaks.toml
.gitleaksignore
.github/workflows/security.yml
```

## 2. Confirm GitHub Action

In the Actions tab, check for:

```text
security
gitleaks
```

## 3. Confirm branch protection

Go to Settings -> Branches and confirm:

```text
main is protected
pull requests are required
approval is required
gitleaks status check is required
force pushes are blocked
branch deletion is blocked
```

## 4. Test local hook

```powershell
git clone <repo-url>
cd <repo>
git checkout -b pelycon/local-gitleaks-test
$fakeGitHubToken = "ghp_" + "1234567890abcdefghij" + "ABCDEFGHIJ123456"
"GITHUB_TOKEN=$fakeGitHubToken" | Out-File secret-test.txt -Encoding utf8
git add secret-test.txt
git commit -m "test local gitleaks block"
```

Expected result: commit is blocked and the secret is redacted.

Clean up:

```powershell
git reset
Remove-Item secret-test.txt
```

## 5. Test GitHub backstop

Only in a test repo:

```powershell
git checkout -b pelycon/github-gitleaks-fail-test
$fakeGitHubToken = "ghp_" + "1234567890abcdefghij" + "ABCDEFGHIJ123456"
"GITHUB_TOKEN=$fakeGitHubToken" | Out-File secret-test.txt -Encoding utf8
git add secret-test.txt
git commit -m "test GitHub gitleaks block" --no-verify
git push -u origin pelycon/github-gitleaks-fail-test --no-verify
```

Open a PR.

Expected result:

```text
gitleaks fails
PR cannot merge
```

Close the PR and delete the branch. Do not merge it.
