#!/usr/bin/env bash
# Pelycon Repository Security Bootstrap - bash port (no PowerShell required).
#
# Does what Set-PelyconRepoSecurity.ps1 does, using the GitHub CLI (`gh`),
# which is preinstalled in GitHub Codespaces. Run it from a checkout of the
# Admin-Controls repo so the templates in repo-bootstrap/templates/ are present.
#
# Auth: export a fine-grained PAT scoped to the TARGET repo (A.2 permissions:
#   Administration RW, Contents RW, Workflows RW, Pull requests RW, Metadata R).
# The Codespace's built-in token only covers Admin-Controls, so set your own:
#   export GH_TOKEN="paste-token-here"
#
# Usage:
#   ./set-pelycon-repo-security.sh --owner OWNER --repo REPO [--dry-run] [--test-pr]
#   [--branch main] [--approvals 1] [--template-dir PATH]
 
set -euo pipefail
 
OWNER="" ; REPO="" ; BRANCH="main" ; APPROVALS="1"
GITLEAKS_CHECK="gitleaks" ; TEMPLATE_DIR="" ; DRY_RUN="false" ; TEST_PR="false"
 
while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --approvals) APPROVALS="$2"; shift 2 ;;
    --template-dir) TEMPLATE_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN="true"; shift ;;
    --test-pr) TEST_PR="true"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
 
[[ -z "$OWNER" || -z "$REPO" ]] && { echo "ERROR: --owner and --repo are required." >&2; exit 2; }
command -v gh  >/dev/null || { echo "ERROR: gh (GitHub CLI) not found." >&2; exit 1; }
[[ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]] || { echo "ERROR: set GH_TOKEN to your fine-grained PAT." >&2; exit 1; }
 
# Templates default to repo-bootstrap/templates relative to this script.
if [[ -z "$TEMPLATE_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEMPLATE_DIR="$SCRIPT_DIR/templates"
fi
 
REPO_API="repos/$OWNER/$REPO"
 
step()   { printf '\n============================================================\n%s\n============================================================\n' "$1"; }
ok()     { printf '[OK] %s\n' "$1"; }
warn()   { printf '[WARN] %s\n' "$1"; }
dryrun() { printf '[DRY RUN] %s\n' "$1"; }
 
# Template name candidates -> repo path -> commit message (matches the .ps1 map).
# Pipe-delimited; first template name that exists on disk wins.
TEMPLATES=(
  "CLAUDE.md|CLAUDE.md|Add Pelycon CLAUDE.md security rules"
  "security.yml|.github/workflows/security.yml|Add Pelycon security workflow"
  "dependabot.yml|.github/dependabot.yml|Add Pelycon Dependabot configuration"
  "gitleaks.toml,.gitleaks.toml|.gitleaks.toml|Add Pelycon Gitleaks config"
  "gitleaksignore,.gitleaksignore|.gitleaksignore|Add Pelycon Gitleaks ignore file"
)
 
resolve_template() {  # $1 = comma-separated candidate names -> prints path or empty
  local IFS=','; for name in $1; do
    [[ -f "$TEMPLATE_DIR/$name" ]] && { echo "$TEMPLATE_DIR/$name"; return; }
  done
}
 
normalize() { sed 's/\r$//' | sed -e :a -e '/^\n*$/{$d;N;ba}'; }  # CRLF->LF, strip trailing blank lines
 
# ---- 1. repository access ----
step "Checking repository access"
if [[ "$DRY_RUN" == "true" ]]; then dryrun "Would check access for $OWNER/$REPO."; fi
FULL_NAME="$(gh api "$REPO_API" --jq .full_name)"
DEFAULT_BRANCH="$(gh api "$REPO_API" --jq .default_branch)"
ok "Repository found: $FULL_NAME"
echo "GitHub default branch: $DEFAULT_BRANCH"
[[ "$BRANCH" != "$DEFAULT_BRANCH" ]] && warn "Script branch '$BRANCH' != default '$DEFAULT_BRANCH' (use --branch $DEFAULT_BRANCH?)."
 
# ---- 2. templates present ----
step "Checking templates folder"
[[ -d "$TEMPLATE_DIR" ]] || { echo "ERROR: templates folder not found: $TEMPLATE_DIR" >&2; exit 1; }
for entry in "${TEMPLATES[@]}"; do
  IFS='|' read -r names path _msg <<< "$entry"
  tp="$(resolve_template "$names")"
  [[ -n "$tp" ]] || { echo "ERROR: missing template for '$path' (expected ${names//,/ or } in $TEMPLATE_DIR)" >&2; exit 1; }
  ok "Template found for $path: $tp"
done
 
# remote file: prints "<sha>\t<base64content>" or empty if 404
remote_file() {
  local path="$1" ref="$2" out
  out="$(gh api "$REPO_API/contents/$path?ref=$ref" --jq '[.sha, .content] | @tsv' 2>/dev/null)" || return 0
  echo "$out"
}
 
branch_protection_active() {
  gh api "$REPO_API/branches/$BRANCH/protection" >/dev/null 2>&1
}
 
put_file() {  # $1 path  $2 template-path  $3 message  $4 target-branch
  local path="$1" tpath="$2" msg="$3" target="$4"
  if [[ "$DRY_RUN" == "true" ]]; then dryrun "Would create/update on $target: $path"; return; fi
  local b64 sha rf
  b64="$(base64 -w0 "$tpath")"
  rf="$(remote_file "$path" "$target")"; sha="$(printf '%s' "$rf" | cut -f1)"
  if [[ -n "$sha" ]]; then
    gh api -X PUT "$REPO_API/contents/$path" -f message="$msg" -f content="$b64" -f branch="$target" -f sha="$sha" >/dev/null
  else
    gh api -X PUT "$REPO_API/contents/$path" -f message="$msg" -f content="$b64" -f branch="$target" >/dev/null
  fi
  ok "Created/updated $path on $target"
}
 
# ---- 3. baseline files (compare; direct push if unprotected, else via PR) ----
step "Comparing baseline files against templates"
PENDING_NAMES=() ; PENDING_PATHS=() ; PENDING_MSGS=()
for entry in "${TEMPLATES[@]}"; do
  IFS='|' read -r names path msg <<< "$entry"
  tp="$(resolve_template "$names")"
  rf="$(remote_file "$path" "$BRANCH")"
  if [[ -n "$rf" ]]; then
    remote_txt="$(printf '%s' "$rf" | cut -f2 | base64 -d 2>/dev/null | normalize || true)"
    local_txt="$(normalize < "$tp")"
    if [[ "$remote_txt" == "$local_txt" ]]; then ok "Unchanged: $path"; continue; fi
  fi
  warn "Needs create/update: $path"
  PENDING_NAMES+=("$tp"); PENDING_PATHS+=("$path"); PENDING_MSGS+=("$msg")
done
 
if [[ ${#PENDING_PATHS[@]} -eq 0 ]]; then
  ok "All baseline files already match the templates."
elif ! branch_protection_active; then
  step "Writing baseline files directly to $BRANCH (no branch protection yet)"
  for i in "${!PENDING_PATHS[@]}"; do
    put_file "${PENDING_PATHS[$i]}" "${PENDING_NAMES[$i]}" "${PENDING_MSGS[$i]}" "$BRANCH"
  done
else
  step "Branch protection is active - applying baseline updates via pull request"
  UPD="pelycon/baseline-update"
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun "Would create/reset $UPD from $BRANCH, update files, and open a PR."
  else
    BASE_SHA="$(gh api "$REPO_API/git/ref/heads/$BRANCH" --jq .object.sha)"
    if gh api "$REPO_API/git/ref/heads/$UPD" >/dev/null 2>&1; then
      gh api -X PATCH "$REPO_API/git/refs/heads/$UPD" -F sha="$BASE_SHA" -F force=true >/dev/null
      ok "Reset $UPD to tip of $BRANCH."
    else
      gh api -X POST "$REPO_API/git/refs" -f ref="refs/heads/$UPD" -f sha="$BASE_SHA" >/dev/null
      ok "Created branch: $UPD"
    fi
    for i in "${!PENDING_PATHS[@]}"; do
      put_file "${PENDING_PATHS[$i]}" "${PENDING_NAMES[$i]}" "${PENDING_MSGS[$i]}" "$UPD"
    done
    if [[ -n "$(gh api "$REPO_API/pulls?state=open&head=$OWNER:$UPD&base=$BRANCH" --jq '.[0].html_url // empty')" ]]; then
      ok "Baseline-update PR already open."
    else
      URL="$(gh api -X POST "$REPO_API/pulls" -f title="Pelycon security baseline update" \
        -f head="$UPD" -f base="$BRANCH" \
        -f body="Automated update of the Pelycon security baseline files. Review and merge to apply." \
        --jq .html_url)"
      ok "Opened baseline-update PR: $URL"
    fi
    warn "Baseline changes are NOT live until that PR is reviewed and merged."
  fi
fi
 
# ---- 4. repository settings (squash-only, auto-delete branches) ----
step "Configuring repository settings"
if [[ "$DRY_RUN" == "true" ]]; then
  dryrun "Would set squash merge only and auto-delete branches."
else
  gh api -X PATCH "$REPO_API" --input - >/dev/null <<'JSON'
{ "allow_squash_merge": true, "allow_merge_commit": false, "allow_rebase_merge": false,
  "allow_auto_merge": false, "delete_branch_on_merge": true, "allow_update_branch": true,
  "squash_merge_commit_title": "PR_TITLE", "squash_merge_commit_message": "PR_BODY" }
JSON
  ok "Repository settings configured."
fi
 
# ---- 5. secret scanning + push protection (warn, don't abort, on failure) ----
step "Enabling GitHub secret scanning + push protection"
if [[ "$DRY_RUN" == "true" ]]; then
  dryrun "Would enable secret_scanning and secret_scanning_push_protection."
else
  if gh api -X PATCH "$REPO_API" --input - >/dev/null 2>&1 <<'JSON'
{ "security_and_analysis": { "secret_scanning": { "status": "enabled" },
  "secret_scanning_push_protection": { "status": "enabled" } } }
JSON
  then
    PP="$(gh api "$REPO_API" --jq '.security_and_analysis.secret_scanning_push_protection.status // "unknown"')"
    echo "Push protection status: $PP"
    [[ "$PP" == "enabled" ]] && ok "Push protection is ON." || warn "Push protection not confirmed ON (check licensing on private repos)."
  else
    warn "COULD NOT enable secret scanning / push protection."
    warn "Private/internal repos need GitHub Secret Protection (Advanced Security); public repos get it free."
    warn "Branch protection and the Gitleaks Action still apply."
  fi
fi
 
# ---- 6. branch protection ----
step "Configuring branch protection"
if [[ "$DRY_RUN" == "true" ]]; then
  dryrun "Would protect $BRANCH: require '$GITLEAKS_CHECK' check and $APPROVALS approval(s)."
else
  gh api -X PUT "$REPO_API/branches/$BRANCH/protection" --input - >/dev/null <<JSON
{ "required_status_checks": { "strict": true, "contexts": ["$GITLEAKS_CHECK"] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": $APPROVALS,
    "dismiss_stale_reviews": true, "require_code_owner_reviews": false, "require_last_push_approval": true },
  "restrictions": null, "required_linear_history": true, "allow_force_pushes": false,
  "allow_deletions": false, "block_creations": false, "required_conversation_resolution": false,
  "lock_branch": false, "allow_fork_syncing": true }
JSON
  ok "Branch protection configured for $BRANCH."
fi
 
# ---- 7. optional draft test PR ----
if [[ "$TEST_PR" == "true" ]]; then
  step "Creating test branch and draft pull request"
  TB="pelycon/security-bootstrap-test" ; TF=".pelycon/security-bootstrap-test.txt"
  if [[ "$DRY_RUN" == "true" ]]; then
    dryrun "Would create $TB, add $TF, and open a draft PR."
  else
    BASE_SHA="$(gh api "$REPO_API/git/ref/heads/$BRANCH" --jq .object.sha)"
    gh api "$REPO_API/git/ref/heads/$TB" >/dev/null 2>&1 || \
      gh api -X POST "$REPO_API/git/refs" -f ref="refs/heads/$TB" -f sha="$BASE_SHA" >/dev/null
    TS="$(date '+%Y-%m-%d %H:%M:%S %z')"
    CONTENT=$(printf 'Pelycon security bootstrap test\n\nCreated: %s\nRepository: %s/%s\nBase branch: %s\n\nDo not merge this pull request. Close it after confirming the security check appears.\n' "$TS" "$OWNER" "$REPO" "$BRANCH")
    B64="$(printf '%s' "$CONTENT" | base64 -w0)"
    SHA="$(printf '%s' "$(remote_file "$TF" "$TB")" | cut -f1)"
    if [[ -n "$SHA" ]]; then
      gh api -X PUT "$REPO_API/contents/$TF" -f message="Add Pelycon security bootstrap test file" -f content="$B64" -f branch="$TB" -f sha="$SHA" >/dev/null
    else
      gh api -X PUT "$REPO_API/contents/$TF" -f message="Add Pelycon security bootstrap test file" -f content="$B64" -f branch="$TB" >/dev/null
    fi
    if [[ -n "$(gh api "$REPO_API/pulls?state=open&head=$OWNER:$TB&base=$BRANCH" --jq '.[0].html_url // empty')" ]]; then
      warn "A test pull request already exists."
    else
      URL="$(gh api -X POST "$REPO_API/pulls" -f title="Pelycon security bootstrap test" \
        -f head="$TB" -f base="$BRANCH" -F draft=true \
        -f body="Draft PR to trigger the security workflow and confirm the Gitleaks check appears. Do not merge; close after verification." \
        --jq .html_url)"
      ok "Draft test pull request opened: $URL"
    fi
  fi
fi
 
step "Done"
[[ "$DRY_RUN" == "true" ]] && echo "This was a dry run. No repository changes were made." || echo "Baseline applied. Check the repo's Code tab, Actions, and Settings > Branches."
