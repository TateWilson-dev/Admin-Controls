<#
Verify-PelyconRepoSecurity.ps1
 
Purpose:
- Read back the security posture of a GitHub repository and report an HONEST verdict.
- Distinguish two things that are NOT the same:
    1. CONFIGURATION - the settings this project controls (toggles, branch protection).
       These can be verified from the API.
    2. ENFORCEMENT   - whether GitHub's secret-scanning engine is actually analyzing and
       blocking. A setting reading "enabled" is NECESSARY but NOT PROOF of this. It must
       be confirmed by a human in the repo's Security -> Secret scanning view.
 
Why this exists:
- A repo can report secret_scanning / push_protection = "enabled" and still not block,
  e.g. private repo without a Secret Protection license, an already-alerted or
  invalid-format test value, or a GitHub-side lag/issue. This script refuses to call
  that a pass. It tells you exactly what it could and could not confirm.
 
This script makes NO changes and needs NO secret values to run.
 
Required environment variable:
$env:GITHUB_TOKEN = "your-token"   (read access to the repo; Administration read helps)
#>
 
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Repo,
    [string]$Branch = "main",
    [string]$GitleaksCheckName = "gitleaks"
)
 
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
 
$GitHubApiBase = "https://api.github.com"
$RepoApiBase = "$GitHubApiBase/repos/$Owner/$Repo"
 
$script:Fails = 0
$script:Warns = 0
 
function Write-Step { param([string]$m) Write-Host ""; Write-Host ("== {0} ==" -f $m) -ForegroundColor Cyan }
function Write-Pass { param([string]$m) Write-Host ("[PASS] {0}" -f $m) -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host ("[INFO] {0}" -f $m) -ForegroundColor Gray }
function Write-Warn { param([string]$m) Write-Host ("[WARN] {0}" -f $m) -ForegroundColor Yellow; $script:Warns++ }
function Write-Fail { param([string]$m) Write-Host ("[FAIL] {0}" -f $m) -ForegroundColor Red;    $script:Fails++ }
 
function Get-GitHubToken {
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        throw "GITHUB_TOKEN is not set. Run: `$env:GITHUB_TOKEN = `"paste-token-here`""
    }
    return $env:GITHUB_TOKEN
}
 
# Returns a result object instead of throwing, so 403/404 (feature unavailable / no access)
# are handled as data rather than crashes.
function Invoke-GitHubSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri
    )
 
    $token = Get-GitHubToken
    $headers = @{
        "Authorization"        = "Bearer $token"
        "Accept"               = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "Pelycon-Repo-Security-Verifier"
    }
 
    try {
        $data = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
        return [pscustomobject]@{ Ok = $true; Status = 200; Data = $data; Error = $null }
    }
    catch {
        $status = $null
        try { $status = [int]$_.Exception.Response.StatusCode } catch { $status = $null }
        return [pscustomobject]@{ Ok = $false; Status = $status; Data = $null; Error = $_.Exception.Message }
    }
}
 
Write-Host "Pelycon repository security verification" -ForegroundColor White
Write-Host ("Target: {0}/{1}  (branch: {2})" -f $Owner, $Repo, $Branch) -ForegroundColor White
Write-Host "This script changes nothing and needs no secret values."
 
# ------------------------------------------------------------------
# 1. Repository facts that change how everything else is interpreted.
# ------------------------------------------------------------------
Write-Step "Repository facts"
 
$repoRes = Invoke-GitHubSafe -Method "GET" -Uri $RepoApiBase
if (-not $repoRes.Ok) {
    Write-Fail ("Cannot read repository ({0}). Check -Owner/-Repo and the token." -f $repoRes.Status)
    Write-Host ""
    Write-Host "VERDICT: could not run." -ForegroundColor Red
    exit 1
}
 
$repo = $repoRes.Data
$visibility = $repo.visibility
Write-Info ("visibility = {0}; archived = {1}; disabled = {2}; fork = {3}" -f `
    $visibility, $repo.archived, $repo.disabled, $repo.fork)
 
if ($repo.archived -or $repo.disabled) {
    Write-Warn "Repo is archived/disabled - secret scanning will not run regardless of the toggles."
}
if ($visibility -ne "public") {
    Write-Warn "Repo is NOT public. Push protection only enforces on private/internal repos with a"
    Write-Warn "GitHub Secret Protection (Advanced Security) license. Without it, the toggle can read"
    Write-Warn "'enabled' while nothing actually blocks. Confirm the account holds that license."
}
 
# ------------------------------------------------------------------
# 2. security_and_analysis toggles (CONFIGURATION only).
# ------------------------------------------------------------------
Write-Step "Secret scanning settings (configuration)"
 
$saa = $repo.security_and_analysis
function Get-Status { param($node) if ($null -ne $node -and $null -ne $node.status) { return $node.status } else { return "absent" } }
 
$ssStatus = Get-Status $saa.secret_scanning
$ppStatus = Get-Status $saa.secret_scanning_push_protection
$npStatus = Get-Status $saa.secret_scanning_non_provider_patterns
$vcStatus = Get-Status $saa.secret_scanning_validity_checks
 
Write-Info ("secret_scanning                       = {0}" -f $ssStatus)
Write-Info ("secret_scanning_push_protection       = {0}" -f $ppStatus)
Write-Info ("secret_scanning_non_provider_patterns = {0}  (optional)" -f $npStatus)
Write-Info ("secret_scanning_validity_checks       = {0}  (optional)" -f $vcStatus)
 
if ($ssStatus -eq "enabled") { Write-Pass "secret_scanning is enabled." }
else { Write-Fail "secret_scanning is NOT enabled." }
 
if ($ppStatus -eq "enabled") { Write-Pass "secret_scanning_push_protection is enabled." }
else { Write-Fail "secret_scanning_push_protection is NOT enabled." }
 
# ------------------------------------------------------------------
# 3. Branch protection + required Gitleaks check (CONFIGURATION).
# ------------------------------------------------------------------
Write-Step "Branch protection (configuration)"
 
$encodedBranch = [System.Uri]::EscapeDataString($Branch)
$bpRes = Invoke-GitHubSafe -Method "GET" -Uri "$RepoApiBase/branches/$encodedBranch/protection"
 
if (-not $bpRes.Ok) {
    if ($bpRes.Status -eq 404) { Write-Fail ("No branch protection on '{0}'." -f $Branch) }
    else { Write-Warn ("Could not read branch protection ({0}). Needs admin read." -f $bpRes.Status) }
}
else {
    $bp = $bpRes.Data
    $contexts = @()
    if ($bp.required_status_checks -and $bp.required_status_checks.contexts) { $contexts = @($bp.required_status_checks.contexts) }
 
    if ($contexts -contains $GitleaksCheckName) { Write-Pass ("Required status check '{0}' is present." -f $GitleaksCheckName) }
    else { Write-Fail ("Required status check '{0}' is missing. Found: {1}" -f $GitleaksCheckName, ($contexts -join ", ")) }
 
    if ($bp.enforce_admins.enabled) { Write-Pass "enforce_admins is on." } else { Write-Warn "enforce_admins is off - admins can bypass protection." }
 
    if ($bp.required_pull_request_reviews -and $bp.required_pull_request_reviews.required_approving_review_count -ge 1) {
        Write-Pass ("PR review required ({0} approval[s])." -f $bp.required_pull_request_reviews.required_approving_review_count)
    }
    else { Write-Warn "No required PR review - changes can merge without approval." }
}
 
# ------------------------------------------------------------------
# 4. Security workflow file present (CONFIGURATION).
# ------------------------------------------------------------------
Write-Step "Security workflow file"
 
$wfRes = Invoke-GitHubSafe -Method "GET" -Uri "$RepoApiBase/contents/.github/workflows/security.yml?ref=$encodedBranch"
if ($wfRes.Ok) { Write-Pass ".github/workflows/security.yml exists (Gitleaks Action backstop)." }
elseif ($wfRes.Status -eq 404) { Write-Warn ".github/workflows/security.yml not found on this branch." }
else { Write-Warn ("Could not read the workflow file ({0})." -f $wfRes.Status) }
 
# ------------------------------------------------------------------
# 5. ENFORCEMENT evidence - read only, interpreted honestly.
#    Alerts existing = the engine has run and detected something (good signal).
#    Zero alerts     = INCONCLUSIVE, not proof of anything.
# ------------------------------------------------------------------
Write-Step "Enforcement evidence (GitHub's engine - cannot be asserted by settings alone)"
 
$alRes = Invoke-GitHubSafe -Method "GET" -Uri "$RepoApiBase/secret-scanning/alerts?per_page=100"
if ($alRes.Ok) {
    $count = @($alRes.Data).Count
    if ($count -gt 0) {
        Write-Pass ("Secret scanning has produced {0} alert(s) - the engine IS running on this repo." -f $count)
        Write-Info "Review them in the repo's Security -> Secret scanning tab."
    }
    else {
        Write-Warn "Zero secret-scanning alerts. This is INCONCLUSIVE:"
        Write-Warn "  - it may simply mean no VALID, non-duplicate secret has ever been pushed, OR"
        Write-Warn "  - the engine may not be analyzing this repo despite the 'enabled' toggle."
        Write-Warn "  Do NOT read zero alerts as either pass or fail on its own."
    }
}
elseif ($alRes.Status -eq 404 -or $alRes.Status -eq 403) {
    Write-Warn ("Secret-scanning alerts API not accessible ({0})." -f $alRes.Status)
    Write-Warn "Usually means the feature isn't active/licensed here, or the token lacks access."
}
else {
    Write-Warn ("Could not read secret-scanning alerts ({0})." -f $alRes.Status)
}
 
# ------------------------------------------------------------------
# Verdict - deliberately two-part and honest.
# ------------------------------------------------------------------
Write-Step "VERDICT"
 
Write-Host ""
Write-Host "CONFIGURATION (what this project controls):" -ForegroundColor White
if ($script:Fails -eq 0) {
    Write-Host "  OK - the required settings read back correctly." -ForegroundColor Green
}
else {
    Write-Host ("  NOT OK - {0} required setting(s) are wrong. Fix these first." -f $script:Fails) -ForegroundColor Red
}
if ($script:Warns -gt 0) {
    Write-Host ("  {0} warning(s) above - read them; several affect real enforcement." -f $script:Warns) -ForegroundColor Yellow
}
 
Write-Host ""
Write-Host "ENFORCEMENT (whether GitHub actually blocks secrets):" -ForegroundColor White
Write-Host "  NOT INDEPENDENTLY VERIFIED by this script - by design." -ForegroundColor Yellow
Write-Host "  A setting of 'enabled' is necessary but not proof. Confirm enforcement here:" -ForegroundColor Yellow
Write-Host ("    https://github.com/{0}/{1}/security/secret-scanning" -f $Owner, $Repo)
Write-Host "  Enforcement is confirmed when a genuinely detected secret produces an alert"
Write-Host "  and/or a blocked push there - not when a toggle says 'enabled'."
Write-Host ""
Write-Host "  Note: do not chase this by pushing invented credential-shaped strings. Use a"
Write-Host "  provider's official designated test/canary token (published for exactly this),"
Write-Host "  or rely on the alerts view above, which reflects real engine activity."
 
if ($script:Fails -gt 0) { exit 1 } else { exit 0 }
