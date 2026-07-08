<#
Pelycon Device-Level Git Security Bootstrap
Windows PowerShell Script

Purpose:
- Install/configure Git and Gitleaks once per Windows user profile.
- Configure global Git hooks so every repo automatically runs Gitleaks.
- Redact secret values by default so Claude Code does not see the secret in terminal output.

Normal install:
Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1"

Optional self-test:
Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1" -RunSelfTest

Force Gitleaks update:
Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1" -ForceUpdate

Uninstall hook/Gitleaks setup:
Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1" -Uninstall

Sandbox/admin-only mode that may show actual secret values:
Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1" -ShowSecretsInReports
#>

[CmdletBinding()]
param(
    [switch]$SkipGitInstall,
    [switch]$RunSelfTest,
    [switch]$ForceUpdate,
    [switch]$ShowSecretsInReports,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PelyconRoot = Join-Path $env:LOCALAPPDATA "Pelycon"
$ToolsRoot = Join-Path $PelyconRoot "Tools"
$PortableGitDir = Join-Path $ToolsRoot "PortableGit"
$GitleaksDir = Join-Path $ToolsRoot "gitleaks"
$HooksDir = Join-Path $PelyconRoot "GitHooks"
$LogDir = Join-Path $PelyconRoot "Logs"
$GitleaksExe = Join-Path $GitleaksDir "gitleaks.exe"

# ------------------------------------------------------------------
# Pinned tool versions. Bump these deliberately after reviewing the
# upstream release notes, and update the SHA256 values from the
# official checksums published with each release.
# ------------------------------------------------------------------
$GitleaksVersion = "8.30.1"
$GitleaksSha256 = @{
    "x64"   = "d29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e"
    "arm64" = "b95f5e4f5c425cedca7ee203d9afd29597e692c4924a12ed42f970537c72cc0f"
}

$PortableGitTag = "v2.55.0.windows.2"
$PortableGitFileVersion = "2.55.0.2"
$PortableGitSha256 = @{
    "x64"   = "b20d42da3afa228e9fa6174480de820282667e799440d655e308f700dfa0d0df"
    "arm64" = "65b913a56a62d7a91fc11a2eecb08422aaa34332d3b2ea39457d2eda02c2f99c"
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    if ($PSVersionTable.PSVersion.Major -le 5) {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    }
    else {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile
    }
}

function Refresh-CurrentSessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")

    $extraPaths = @(
        "C:\Program Files\Git\cmd",
        "C:\Program Files\Git\mingw64\bin",
        "C:\Program Files\Git\usr\bin",
        "$env:LOCALAPPDATA\Programs\Git\cmd",
        "$env:LOCALAPPDATA\Programs\Git\mingw64\bin",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin",
        "$PortableGitDir\cmd",
        "$PortableGitDir\mingw64\bin",
        "$PortableGitDir\usr\bin",
        $GitleaksDir
    ) | Where-Object { $_ -and (Test-Path $_) }

    $env:Path = (($extraPaths + ($machinePath -split ";") + ($userPath -split ";")) |
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Select-Object -Unique) -join ";"
}

function Add-DirectoryToUserPath {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) {
        return
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()

    if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
        $parts = $currentUserPath -split ";" | Where-Object { $_ -and $_.Trim() -ne "" }
    }

    $alreadyExists = $false
    foreach ($part in $parts) {
        if ($part.TrimEnd("\") -ieq $Directory.TrimEnd("\")) {
            $alreadyExists = $true
            break
        }
    }

    if (-not $alreadyExists) {
        $newPath = ($parts + $Directory | Select-Object -Unique) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Ok "Added to user PATH: $Directory"
    }
    else {
        Write-Ok "Already in user PATH: $Directory"
    }

    Refresh-CurrentSessionPath
}

function Convert-ToGitShellPath {
    param([string]$WindowsPath)

    $p = $WindowsPath -replace "\\", "/"

    if ($p -match "^([A-Za-z]):/(.*)$") {
        $drive = $matches[1].ToLower()
        $rest = $matches[2]
        return "/$drive/$rest"
    }

    return $p
}

function Convert-ToGitConfigPath {
    param([string]$WindowsPath)
    return ($WindowsPath -replace "\\", "/")
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $actual = (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        Remove-Item -Path $Path -Force -ErrorAction SilentlyContinue
        throw "$Description failed SHA256 verification. Expected $ExpectedSha256 but got $actual. The download was deleted. Do not proceed - verify the pinned version and checksum in this script."
    }

    Write-Ok "$Description passed SHA256 verification."
}

function Install-GitIfMissing {
    Write-Step "Checking Git"
    Refresh-CurrentSessionPath

    if (Test-Command "git.exe") {
        Write-Ok "Git is already installed."
        git --version
        return
    }

    if ($SkipGitInstall) {
        throw "Git is not installed and -SkipGitInstall was used."
    }

    Write-Warn "Git was not found. Downloading pinned PortableGit $PortableGitFileVersion directly from GitHub."
    Write-Warn "This avoids winget and avoids requiring admin rights for Git."

    $arch = Get-WindowsArchitectureForGitleaks
    $assetSuffix = if ($arch -eq "arm64") { "arm64" } else { "64-bit" }
    $assetName = "PortableGit-$PortableGitFileVersion-$assetSuffix.7z.exe"
    $assetUrl = "https://github.com/git-for-windows/git/releases/download/$PortableGitTag/$assetName"
    $expectedSha = $PortableGitSha256[$arch]

    New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    if (Test-Path $PortableGitDir) {
        Write-Warn "Removing old PortableGit folder before reinstalling."
        Remove-Item -Path $PortableGitDir -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $PortableGitDir | Out-Null

    $installerPath = Join-Path $env:TEMP $assetName
    Write-Host "Downloading $assetName..."
    Download-File -Uri $assetUrl -OutFile $installerPath
    Assert-FileHash -Path $installerPath -ExpectedSha256 $expectedSha -Description "PortableGit download"

    Write-Host "Extracting PortableGit to $PortableGitDir ..."
    $extractArg = "-o`"$PortableGitDir`""
    $process = Start-Process -FilePath $installerPath -ArgumentList @("-y", $extractArg) -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "PortableGit extraction exited with code $($process.ExitCode)."
    }

    Add-DirectoryToUserPath -Directory (Join-Path $PortableGitDir "cmd")
    Add-DirectoryToUserPath -Directory (Join-Path $PortableGitDir "mingw64\bin")
    Add-DirectoryToUserPath -Directory (Join-Path $PortableGitDir "usr\bin")
    Refresh-CurrentSessionPath

    if (-not (Test-Command "git.exe")) {
        throw "PortableGit was extracted, but git.exe is still not available. Close and reopen PowerShell, then rerun this script."
    }

    Write-Ok "PortableGit installed successfully."
    git --version
}

function Get-WindowsArchitectureForGitleaks {
    $archText = "$env:PROCESSOR_ARCHITECTURE $env:PROCESSOR_ARCHITEW6432"

    if ($archText -match "ARM64") {
        return "arm64"
    }

    return "x64"
}

function Install-Gitleaks {
    Write-Step "Checking Gitleaks"
    New-Item -ItemType Directory -Force -Path $GitleaksDir | Out-Null

    if ((Test-Path $GitleaksExe) -and (-not $ForceUpdate)) {
        try {
            $installedVersion = (& $GitleaksExe version 2>$null | Select-Object -First 1).Trim().TrimStart("v")

            if ($installedVersion -eq $GitleaksVersion) {
                Write-Ok "Gitleaks $GitleaksVersion is already installed. Skipping download."
                Add-DirectoryToUserPath -Directory $GitleaksDir
                Refresh-CurrentSessionPath
                return
            }

            Write-Warn "Installed Gitleaks is $installedVersion but this script pins $GitleaksVersion. Updating."
        }
        catch {
            Write-Warn "Existing Gitleaks copy appears broken. Re-downloading."
        }
    }

    Write-Step "Installing Gitleaks"
    $arch = Get-WindowsArchitectureForGitleaks
    Write-Host "Detected Windows architecture: $arch"

    $assetName = "gitleaks_$($GitleaksVersion)_windows_$arch.zip"
    $assetUrl = "https://github.com/gitleaks/gitleaks/releases/download/v$GitleaksVersion/$assetName"
    $expectedSha = $GitleaksSha256[$arch]

    $zipPath = Join-Path $env:TEMP $assetName
    $extractDir = Join-Path $env:TEMP ("gitleaks-" + [guid]::NewGuid().ToString())

    Write-Host "Downloading $assetName..."
    Download-File -Uri $assetUrl -OutFile $zipPath
    Assert-FileHash -Path $zipPath -ExpectedSha256 $expectedSha -Description "Gitleaks download"

    Write-Host "Extracting Gitleaks..."
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    $downloadedExe = Get-ChildItem -Path $extractDir -Filter "gitleaks.exe" -Recurse | Select-Object -First 1

    if (-not $downloadedExe) {
        throw "Could not find gitleaks.exe inside the downloaded ZIP."
    }

    Copy-Item -Path $downloadedExe.FullName -Destination $GitleaksExe -Force
    $GitleaksVersion | Set-Content -Path (Join-Path $GitleaksDir "version.txt") -Encoding UTF8

    Add-DirectoryToUserPath -Directory $GitleaksDir
    Refresh-CurrentSessionPath

    Write-Ok "Gitleaks installed to $GitleaksExe"
    & $GitleaksExe version
}

function Write-GlobalGitHooks {
    Write-Step "Creating global Git hooks"
    New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

    $gitleaksShellPath = Convert-ToGitShellPath -WindowsPath $GitleaksExe
    $showSecretsValue = "false"
    $redactText = "--redact"

    if ($ShowSecretsInReports) {
        $showSecretsValue = "true"
        $redactText = ""
        Write-Warn "ShowSecretsInReports is enabled. Secret values may be printed in terminal output."
        Write-Warn "Do not use this mode with Claude Code or normal users."
    }

    $preCommit = @'
#!/bin/sh
set -u

GL="__GITLEAKS_PATH__"
SHOW_SECRETS="__SHOW_SECRETS__"
REDACT_FLAG="__REDACT_FLAG__"

if [ ! -x "$GL" ]; then
  echo ""
  echo "Pelycon Git Security: Gitleaks was not found at:"
  echo "  $GL"
  echo "Rerun Install-PelyconGitSecurity.ps1."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

echo "Pelycon Git Security: running Gitleaks pre-commit scan..."

if [ -n "$REDACT_FLAG" ]; then
  "$GL" git --pre-commit --staged --redact --no-banner --exit-code 1
else
  "$GL" git --pre-commit --staged --no-banner --exit-code 1
fi

STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  echo ""
  echo "------------------------------------------------------------"
  echo "Pelycon Git Security: COMMIT BLOCKED"
  echo "------------------------------------------------------------"
  echo "Gitleaks found a possible secret in the staged changes."
  echo "Review the Gitleaks output above for the file, line, rule, and fingerprint."
  if [ "$SHOW_SECRETS" = "true" ]; then
    echo "WARNING: secret-display mode is enabled. The output above may include the actual secret value."
  else
    echo "Secret values are redacted by default so they are not exposed to Claude Code, logs, or screenshots."
  fi
  echo ""
  echo "Fix steps:"
  echo "  1. Remove the secret from the listed file."
  echo "  2. Put the value in an approved secret store such as Azure Key Vault or GitHub Secrets."
  echo "  3. If it was a real secret, rotate/revoke it."
  echo "  4. Stage the cleaned file and commit again."
  echo ""
  echo "Do not bypass this with --no-verify unless a Pelycon administrator approves it."
  exit "$STATUS"
fi

# Chain to the repository's own local pre-commit hook, if it has one.
# (Global core.hooksPath replaces local hooks, so we call them ourselves.)
LOCAL_HOOK="$(git rev-parse --git-dir)/hooks/pre-commit"
if [ -x "$LOCAL_HOOK" ]; then
  exec "$LOCAL_HOOK" "$@"
fi

exit 0
'@

    $prePush = @'
#!/bin/sh
set -u

GL="__GITLEAKS_PATH__"
SHOW_SECRETS="__SHOW_SECRETS__"
REDACT_FLAG="__REDACT_FLAG__"

if [ ! -x "$GL" ]; then
  echo ""
  echo "Pelycon Git Security: Gitleaks was not found at:"
  echo "  $GL"
  echo "Rerun Install-PelyconGitSecurity.ps1."
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
ZERO_SHA="0000000000000000000000000000000000000000"

# Git gives pre-push one line per ref on stdin:
#   <local_ref> <local_sha> <remote_ref> <remote_sha>
# Scan only the outgoing commits, not the whole history - fast, and a
# historical finding (handled by the GitHub Actions backstop) cannot
# block every future push.
STDIN_DATA="$(cat)"

if [ -z "$STDIN_DATA" ]; then
  exit 0
fi

echo "Pelycon Git Security: running Gitleaks pre-push scan on outgoing commits..."

STATUS=$(
  printf '%s\n' "$STDIN_DATA" | {
    fail=0
    while read -r local_ref local_sha remote_ref remote_sha; do
      [ -z "$local_ref" ] && continue
      # Deleting a remote branch pushes nothing to scan.
      [ "$local_sha" = "$ZERO_SHA" ] && continue

      if [ "$remote_sha" = "$ZERO_SHA" ]; then
        # New branch: scan commits not already on any remote ref.
        RANGE="$local_sha --not --remotes"
      else
        RANGE="$remote_sha..$local_sha"
      fi

      if [ -n "$REDACT_FLAG" ]; then
        "$GL" git --redact --no-banner --exit-code 1 --log-opts "$RANGE" "$ROOT" || fail=1
      else
        "$GL" git --no-banner --exit-code 1 --log-opts "$RANGE" "$ROOT" || fail=1
      fi
    done
    echo "$fail"
  }
)

if [ "$STATUS" -ne 0 ]; then
  echo ""
  echo "------------------------------------------------------------"
  echo "Pelycon Git Security: PUSH BLOCKED"
  echo "------------------------------------------------------------"
  echo "Gitleaks found a possible secret in the commits being pushed."
  echo "Review the Gitleaks output above for the file, line, rule, and fingerprint."
  if [ "$SHOW_SECRETS" = "true" ]; then
    echo "WARNING: secret-display mode is enabled. The output above may include the actual secret value."
  else
    echo "Secret values are redacted by default so they are not exposed to Claude Code, logs, or screenshots."
  fi
  echo ""
  echo "Fix steps:"
  echo "  1. Remove the secret from the listed file/history."
  echo "  2. Put the value in an approved secret store such as Azure Key Vault or GitHub Secrets."
  echo "  3. If it was a real secret, rotate/revoke it."
  echo "  4. Commit the cleaned change and push again."
  echo ""
  echo "Do not bypass this with --no-verify unless a Pelycon administrator approves it."
  exit "$STATUS"
fi

# Chain to the repository's own local pre-push hook, forwarding stdin.
LOCAL_HOOK="$(git rev-parse --git-dir)/hooks/pre-push"
if [ -x "$LOCAL_HOOK" ]; then
  printf '%s\n' "$STDIN_DATA" | "$LOCAL_HOOK" "$@"
  exit $?
fi

exit 0
'@

    $preCommit = $preCommit.Replace("__GITLEAKS_PATH__", $gitleaksShellPath)
    $preCommit = $preCommit.Replace("__SHOW_SECRETS__", $showSecretsValue)
    $preCommit = $preCommit.Replace("__REDACT_FLAG__", $redactText)

    $prePush = $prePush.Replace("__GITLEAKS_PATH__", $gitleaksShellPath)
    $prePush = $prePush.Replace("__SHOW_SECRETS__", $showSecretsValue)
    $prePush = $prePush.Replace("__REDACT_FLAG__", $redactText)

    # Shell hooks must use LF line endings; Set-Content on Windows
    # PowerShell writes CRLF, so write the files explicitly with LF.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $preCommitLf = $preCommit.Replace("`r`n", "`n")
    $prePushLf = $prePush.Replace("`r`n", "`n")

    if (-not $preCommitLf.EndsWith("`n")) { $preCommitLf += "`n" }
    if (-not $prePushLf.EndsWith("`n")) { $prePushLf += "`n" }

    [System.IO.File]::WriteAllText((Join-Path $HooksDir "pre-commit"), $preCommitLf, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $HooksDir "pre-push"), $prePushLf, $utf8NoBom)

    $hooksGitConfigPath = Convert-ToGitConfigPath -WindowsPath $HooksDir
    $existingHooksPath = $null

    try {
        $existingHooksPath = git config --global --get core.hooksPath
    }
    catch {
        $existingHooksPath = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($existingHooksPath) -and ($existingHooksPath -ne $hooksGitConfigPath)) {
        Write-Warn "Existing global core.hooksPath will be replaced."
        Write-Warn "Old: $existingHooksPath"
        Write-Warn "New: $hooksGitConfigPath"
    }

    git config --global core.hooksPath "$hooksGitConfigPath"

    Write-Ok "Global Git hooks written to $HooksDir"
    Write-Ok "Git global core.hooksPath set to $hooksGitConfigPath"
}

function Test-Installation {
    Write-Step "Verifying installation"

    Refresh-CurrentSessionPath

    if (-not (Test-Command "git.exe")) {
        throw "Git is not available."
    }

    if (-not (Test-Path $GitleaksExe)) {
        throw "Gitleaks is not installed at $GitleaksExe"
    }

    $configuredHooks = git config --global --get core.hooksPath

    if ([string]::IsNullOrWhiteSpace($configuredHooks)) {
        throw "Git global core.hooksPath is not configured."
    }

    Write-Ok "Git version:"
    git --version

    Write-Ok "Gitleaks version:"
    & $GitleaksExe version

    Write-Ok "Global hooks path:"
    Write-Host $configuredHooks

    if ($ShowSecretsInReports) {
        Write-Warn "Secret values may be shown because -ShowSecretsInReports is enabled."
    }
    else {
        Write-Ok "Secret values are redacted by default."
    }

    Write-Ok "Device-level Git security bootstrap is installed."
}

function Run-SelfTest {
    Write-Step "Running optional self-test"

    $testRoot = Join-Path $env:TEMP ("pelycon-gitleaks-selftest-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

    Push-Location $testRoot

    try {
        $initOutput = & git -c init.defaultBranch=main init 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Self-test failed: could not create a temporary Git repo."
        }

        & git config user.email "security-test@example.com" 2>&1 | Out-Null
        & git config user.name "Pelycon Security Test" 2>&1 | Out-Null
        & git config core.autocrlf false 2>&1 | Out-Null

        "hello" | Set-Content -Path "ok.txt" -Encoding UTF8
        $addCleanOutput = & git add ok.txt 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Self-test failed: could not stage the clean test file."
        }

        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $cleanCommitOutput = & git commit -m "clean test" 2>&1
        $cleanExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference
        $cleanExitCode = $LASTEXITCODE

        if ($cleanExitCode -ne 0) {
            throw "Self-test failed: clean commit was blocked. The hook may be misconfigured."
        }

        Write-Ok "Clean commit was allowed."

        $fakeGitHubToken = "ghp_" + "1234567890abcdefghij" + "ABCDEFGHIJ123456"
        $fakeAzureSecret = "Ab78Q~" + "zK4mP9xQ2wL7vR3nT8sB6yD1fG5hJ0cA"

@"
GITHUB_TOKEN=$fakeGitHubToken
AZURE_CLIENT_SECRET=$fakeAzureSecret
"@ | Set-Content -Path "secret-test.txt" -Encoding UTF8

        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $cleanCommitOutput = & git commit -m "clean test" 2>&1
        $cleanExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference

if ($cleanExitCode -ne 0) {
    throw "Self-test failed: clean commit was blocked. The hook may be misconfigured."
}

Write-Ok "Clean commit was allowed."
        if ($LASTEXITCODE -ne 0) {
            throw "Self-test failed: could not stage the fake secret test file."
        }

        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $secretCommitOutput = & git commit -m "secret test should be blocked" 2>&1
        $secretExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorActionPreference

        $secretExitCode = $LASTEXITCODE
        $secretCommitText = $secretCommitOutput -join "`n"

        if ($secretExitCode -eq 0) {
            throw "Self-test failed: fake secret commit was allowed. Gitleaks is not blocking commits."
        }

        if (
            ($secretCommitText -notmatch "COMMIT BLOCKED") -and
            ($secretCommitText -notmatch "leaks found") -and
            ($secretCommitText -notmatch "Gitleaks found")
        ) {
            throw "Self-test failed: fake secret commit failed, but not clearly because of Gitleaks."
        }

        Write-Ok "Fake secret commit was blocked."

        Write-Host ""
        Write-Host "SELF-TEST PASSED" -ForegroundColor Green
        Write-Host "Device Git secret scanning is working." -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  1. Close and reopen PowerShell, Git Bash, and Claude Code."
        Write-Host "  2. Use Git normally."
        Write-Host "  3. If a commit is blocked, remove the secret and commit again."
        Write-Host ""
        Write-Host "Test repo location:"
        Write-Host "  $testRoot"
    }
    finally {
        Pop-Location
    }
}

function Uninstall-PelyconGitSecurity {
    Write-Step "Uninstalling Pelycon Git security bootstrap"
    Refresh-CurrentSessionPath

    if (Test-Command "git.exe") {
        $configuredHooks = $null

        try {
            $configuredHooks = git config --global --get core.hooksPath
        }
        catch {
            $configuredHooks = $null
        }

        $expectedHooksPath = Convert-ToGitConfigPath -WindowsPath $HooksDir

        if ($configuredHooks -eq $expectedHooksPath) {
            git config --global --unset core.hooksPath
            Write-Ok "Removed global Git core.hooksPath."
        }
        elseif (-not [string]::IsNullOrWhiteSpace($configuredHooks)) {
            Write-Warn "Global core.hooksPath is set to a different path, so it was not removed:"
            Write-Warn $configuredHooks
        }
    }

    if (Test-Path $HooksDir) {
        Remove-Item -Path $HooksDir -Recurse -Force
        Write-Ok "Removed Pelycon Git hooks folder."
    }

    if (Test-Path $GitleaksDir) {
        Remove-Item -Path $GitleaksDir -Recurse -Force
        Write-Ok "Removed Pelycon Gitleaks folder."
    }

    Write-Ok "Uninstall complete. Git itself was not removed."
}

try {
    if ($Uninstall) {
        Uninstall-PelyconGitSecurity
        exit 0
    }

    Write-Step "Starting Pelycon device-level Git security bootstrap"

    New-Item -ItemType Directory -Force -Path $PelyconRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

    Install-GitIfMissing
    Install-Gitleaks
    Write-GlobalGitHooks
    Test-Installation

    if ($RunSelfTest) {
        Run-SelfTest
    }

    Write-Host ""
    Write-Host "DONE" -ForegroundColor Green
    Write-Host "This device is now configured for Pelycon Git secret scanning." -ForegroundColor Green
    Write-Host ""
    Write-Host "What this means:"
    Write-Host "  - Every Git commit on this Windows profile runs Gitleaks."
    Write-Host "  - Every Git push on this Windows profile runs Gitleaks."
    Write-Host "  - This applies to every repo because Git global core.hooksPath is configured."
    Write-Host "  - Secret values are redacted by default."
    Write-Host ""
    Write-Host "Recommended next step:"
    Write-Host "  Close and reopen PowerShell, Git Bash, and Claude Code so they reload PATH."
    Write-Host ""
    Write-Host "Optional test command:"
    Write-Host '  Set-ExecutionPolicy -Scope Process Bypass -Force; Invoke-WebRequest "https://raw.githubusercontent.com/TateWilson-dev/Admin-Controls/main/device-bootstrap/windows/Install-PelyconGitSecurity.ps1" -OutFile "$env:TEMP\Install-PelyconGitSecurity.ps1"; & "$env:TEMP\Install-PelyconGitSecurity.ps1" -RunSelfTest'
}
catch {
    Write-Host ""
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Try closing and reopening PowerShell, then rerun the script."
    exit 1
}
