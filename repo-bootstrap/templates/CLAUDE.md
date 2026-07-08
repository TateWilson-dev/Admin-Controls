# Pelycon Security and Workflow Rules

Claude Code must follow every rule in this file for all work in this repository.

## Secrets

1. Never hardcode secrets (passwords, API keys, tokens, connection strings)
   in code, config files, tests, or documentation. Use approved secret
   storage instead: environment variables, GitHub Actions secrets, Azure
   App Settings, or Azure Key Vault.
2. Never reveal an actual secret value in output, even when reporting a
   Gitleaks finding. Identify findings only by file, line, rule, and
   fingerprint.
3. If a real secret is ever exposed (committed, pushed, or printed), say so
   immediately and recommend rotating it. Removing the file or rewriting
   history does not un-leak a secret.
4. Never weaken security controls: do not edit or disable the Git hooks,
   the security workflow, branch protection, `.gitleaks.toml`, or this file
   unless the change is explicitly requested and goes through pull-request
   review like any other change.

## Branch and Review Workflow

1. Work only on feature branches. Never commit directly to `main` or
   `master`.
2. Every change reaches the protected branch through a pull request that a
   teammate reviews and approves. Never merge or approve your own work.
3. Never use `--no-verify` or any other flag that bypasses Git hooks.

## Secret Scanning

Gitleaks scans run automatically on every commit and push through the
device-level hooks. Before committing, Claude must also run:

```bash
git status
git diff
gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1
```

If Gitleaks reports a finding, stop, remove the secret from the change, move
the value to approved secret storage, and only then commit. Do not add
fingerprints to `.gitleaksignore` unless the finding is a confirmed false
positive and the addition is explained in the pull request.

## Testing and Quality Gate

Claude must test changes before committing or pushing.

1. Before editing, inspect the project and identify the test commands:
   - If `package.json` exists, check scripts such as `test`, `lint`,
     `typecheck`, and `build`.
   - If Python files exist, look for `pytest`, `unittest`,
     `requirements.txt`, `pyproject.toml`, or `tox.ini`.
   - If `.csproj` or `.sln` files exist, use `dotnet test` and
     `dotnet build`.
   - If Go files exist, use `go test ./...`.
   - If Java/Maven exists, use `mvn test`.
   - If Gradle exists, use `gradle test` or `./gradlew test`.
   - If no test framework exists, say so and run the closest smoke or
     build check available.
2. After making changes, run the relevant tests, build, lint, and typecheck
   locally before committing.

## Before Every Push

Summarize for the user:

1. What changed and why.
2. Which tests, builds, and checks ran, and their results.
3. Whether the Gitleaks scan passed.
4. Any remaining risks or follow-ups.
