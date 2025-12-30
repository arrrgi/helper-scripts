#!/bin/sh
#
# Configure Git identity using GitHub CLI
# This script is idempotent - it only updates Git config if values are missing
#
# Usage:
#   Local:  ./config-git-identity.sh
#   Remote: curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/.devcontainer/config-git-identity.sh | sh
#

set -eu

# Colors for output (disabled if not a TTY)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Required GitHub CLI scopes (GitHub CLI defaults + email + SSH signing key)
REQUIRED_SCOPES="repo,read:org,gist,user:email,read:ssh_signing_key"

# Dependency check
command -v gh >/dev/null 2>&1 || { echo "Error: GitHub CLI (gh) is required but not installed. Aborting." >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Error: Git is required but not installed. Aborting." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed. Aborting." >&2; exit 1; }

# ============================================================================
# Helper Functions
# ============================================================================

log_info() {
    printf "%b✓ %s%b\n" "$GREEN" "$1" "$NC"
}

log_warn() {
    printf "%b⚠ %s%b\n" "$YELLOW" "$1" "$NC"
}

log_error() {
    printf "%b✗ %s%b\n" "$RED" "$1" "$NC"
}

log_pending() {
    printf "  → %s\n" "$1"
}

# Check if a Git config value is set
get_git_config() {
    key="$1"
    git config --global "$key" 2>/dev/null || echo ""
}

# Set a Git config value
set_git_config() {
    key="$1"
    value="$2"
    git config --global "$key" "$value"
}

# ============================================================================
# Authentication Functions
# ============================================================================

ensure_gh_authenticated() {
    if ! gh auth status >/dev/null 2>&1; then
        printf "%bGitHub CLI not authenticated. Starting OAuth flow...%b\n" "$YELLOW" "$NC"
        gh auth login --web --git-protocol https --clipboard --scopes "$REQUIRED_SCOPES"
    else
        log_info "GitHub CLI already authenticated"
        ensure_required_scopes
    fi
}

ensure_required_scopes() {
    # Test if we can access the user API
    api_test=$(gh api user 2>&1 || true)

    if echo "$api_test" | grep -q "needs the.*scope"; then
        printf "%bRefreshing GitHub CLI authentication with required scopes...%b\n" "$YELLOW" "$NC"
        gh auth refresh --scopes "$REQUIRED_SCOPES"
    fi
}

# ============================================================================
# Git Config Checking Functions
# ============================================================================

check_git_config_status() {
    needs_update=false

    user_name=$(get_git_config "user.name")
    user_email=$(get_git_config "user.email")
    signing_key=$(get_git_config "user.signingkey")

    if [ -z "$user_name" ]; then
        log_pending "user.name not set"
        needs_update=true
    else
        log_info "user.name already set: $user_name"
    fi

    if [ -z "$user_email" ]; then
        log_pending "user.email not set"
        needs_update=true
    else
        log_info "user.email already set: $user_email"
    fi

    if [ -z "$signing_key" ]; then
        log_pending "user.signingkey not set"
        needs_update=true
    else
        log_info "user.signingkey already set: $signing_key"
    fi

    # Return 0 if update needed, 1 if not
    [ "$needs_update" = true ]
}

# ============================================================================
# GitHub API Functions
# ============================================================================

fetch_github_user_info() {
    gh api user --jq '{login, name: (.name // .login)}'
}

fetch_github_email() {
    gh api user/emails --jq '[.[] | select(.primary == true)] | .[0].email'
}

fetch_ssh_signing_key() {
    # Fetch the first SSH signing key (most recent)
    gh api user/ssh_signing_keys --jq '.[0].key // empty' 2>/dev/null || echo ""
}

# ============================================================================
# Git Config Update Functions
# ============================================================================

update_user_name() {
    current_value="$1"
    gh_name="$2"

    if [ -z "$current_value" ]; then
        if [ -n "$gh_name" ]; then
            set_git_config "user.name" "$gh_name"
            log_info "Set user.name: $gh_name"
        else
            log_error "Could not retrieve name from GitHub"
        fi
    fi
}

update_user_email() {
    current_value="$1"
    gh_email="$2"

    if [ -z "$current_value" ]; then
        if [ -n "$gh_email" ]; then
            set_git_config "user.email" "$gh_email"
            log_info "Set user.email: $gh_email"
        else
            log_error "Could not retrieve email from GitHub"
        fi
    fi
}

update_signing_key() {
    current_value="$1"

    if [ -n "$current_value" ]; then
        return
    fi

    ssh_key=$(fetch_ssh_signing_key)

    if [ -n "$ssh_key" ]; then
        # POSIX-compliant substring: use awk instead of ${var:0:60}
        short_key=$(echo "$ssh_key" | awk '{print substr($0,1,60)}')
        set_git_config "user.signingkey" "$ssh_key"
        set_git_config "gpg.format" "ssh"
        set_git_config "commit.gpgsign" "true"
        set_git_config "tag.gpgsign" "true"
        log_info "Set user.signingkey: ${short_key}..."
        log_info "Enabled SSH commit and tag signing"
    else
        log_warn "No SSH signing key found on GitHub account. Skipping signingkey setup."
    fi
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    printf "🔧 Configuring Git identity from GitHub...\n"

    # Ensure GitHub CLI is authenticated with required scopes
    ensure_gh_authenticated

    # Check current Git config status
    if ! check_git_config_status; then
        log_info "All Git config values already set. Skipping update."
        exit 0
    fi

    printf "\n"
    printf "Fetching GitHub user information...\n"

    # Get current config values
    user_name=$(get_git_config "user.name")
    user_email=$(get_git_config "user.email")
    signing_key=$(get_git_config "user.signingkey")

    # Fetch GitHub user info
    gh_info=$(fetch_github_user_info)
    gh_name=$(echo "$gh_info" | jq -r '.name')
    gh_email=$(fetch_github_email)

    # Update Git config
    update_user_name "$user_name" "$gh_name"
    update_user_email "$user_email" "$gh_email"
    update_signing_key "$signing_key"

    printf "\n"
    log_info "Git identity configuration complete!"
}

# Run main function
main
