#!/usr/bin/env bash
# r2d2 - GitLab utilities
# Standalone bash port of the r2d2 zsh function.
# Works with bash 3.2+ (macOS default) and newer.

# -- Constants ------------------------------------------------------------
_R2_RED='\033[0;31m'
_R2_GREEN='\033[0;32m'
_R2_YELLOW='\033[0;33m'
_R2_BLUE='\033[0;34m'
_R2_RESET='\033[0m'
_R2_HOST="code.levelup.cce.af.mil"

# Helper: Expand shortcuts to full paths.
# Handles both bare group names (sec, os, net, cctc) and prefixed paths (sec/repo).
_r2d2_expand_repo_path() {
  local repo_path="$1"
  case "$repo_path" in
    sec/*|os/*|net/*|sec|os|net)
      echo "cyber/cted/tech/cctc/$repo_path"
      ;;
    cctc/*|cctc)
      echo "cyber/cted/tech/$repo_path"
      ;;
    *)
      echo "$repo_path"
      ;;
  esac
}

# -- Color helpers --------------------------------------------------------
_r2d2_info()    { printf '%b%s%b\n' "$_R2_BLUE"   "$1" "$_R2_RESET"; }
_r2d2_success() { printf '%b%s%b\n' "$_R2_GREEN"  "$1" "$_R2_RESET"; }
_r2d2_warn()    { printf '%b%s%b\n' "$_R2_YELLOW" "$1" "$_R2_RESET" >&2; }
_r2d2_error()   { printf '%b%s%b\n' "$_R2_RED"    "$1" "$_R2_RESET" >&2; }
_r2d2_ok()      { printf '%b✓%b %s\n' "$_R2_GREEN" "$_R2_RESET" "$1"; }
_r2d2_fail()    { printf '%b✗ %s%b\n' "$_R2_RED"   "$1" "$_R2_RESET" >&2; }

# -- Glab wrapper ---------------------------------------------------------
_r2d2_glab() {
  GITLAB_HOST="$_R2_HOST" command glab "$@"
}

# -- Auth helpers ---------------------------------------------------------
_r2d2_require_auth() {
  local auth_output
  if ! auth_output="$(_r2d2_glab auth status --hostname "$_R2_HOST" 2>&1)"; then
    # Token may be stored but API unreachable (TLS certs, network).
    # Let the command through so it surfaces its own error.
    if printf '%s' "$auth_output" | grep -q "Token found"; then
      return 0
    fi
    _r2d2_error "Not authenticated to $_R2_HOST"
    _r2d2_warn "$auth_output"
    _r2d2_warn "Run: r2d2 --config"
    return 1
  fi
}

# Authenticate with keyring, falling back to plaintext on failure.
# Token is passed as $1 to avoid stdin consumption issues on retry.
_r2d2_auth_with_fallback() {
  local token="$1"
  if printf '%s\n' "$token" | _r2d2_glab auth login --hostname "$_R2_HOST" --stdin --use-keyring; then
    if _r2d2_verify_keyring; then
      _r2d2_success "Authentication configured with keyring storage."
    else
      _r2d2_success "Authentication configured."
    fi
    return 0
  fi

  _r2d2_fail "Authentication with keyring failed."
  printf '%s' "Retry without keyring (plaintext storage)? [y/N]: "
  read -r retry_choice
  if [[ "$retry_choice" =~ ^[Yy]$ ]]; then
    # Remove the broken host entry left by the failed keyring attempt.
    # On Ubuntu 18 (GNOME Keyring without D-Bus), the failed --use-keyring
    # writes a hosts.yml entry that tells glab to read from the keyring.
    # Without this logout, the plaintext retry can't fully overwrite it,
    # so glab keeps looking in the empty keyring and reports "not authenticated."
    _r2d2_glab auth logout --hostname "$_R2_HOST" 2>/dev/null || true
    if printf '%s\n' "$token" | _r2d2_glab auth login --hostname "$_R2_HOST" --stdin; then
      # Verify the token was actually stored.
      # glab auth status makes an API call that can fail for reasons
      # unrelated to auth (TLS certs, network). Check for "Token found"
      # in the output to distinguish "token missing" from "API unreachable."
      local verify_output
      verify_output="$(_r2d2_glab auth status --hostname "$_R2_HOST" 2>&1)" || true
      if ! printf '%s' "$verify_output" | grep -q "Token found"; then
        _r2d2_fail "Token not found after login."
        _r2d2_warn "$verify_output"
        _r2d2_warn "Check your PAT and try again."
        return 1
      fi
      if printf '%s' "$verify_output" | grep -q "API call failed"; then
        _r2d2_warn "Token stored, but API verification failed (likely a TLS certificate issue)."
        _r2d2_warn "Install your organization's CA certificates to fix HTTPS access."
      fi
      _r2d2_success "Authentication configured (plaintext storage)."
      return 0
    fi
    _r2d2_fail "Authentication failed."
  fi
  return 1
}

# -- Config subhelpers ----------------------------------------------------
_r2d2_verify_keyring() {
  local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/glab-cli/hosts.yml"
  if [[ -f "$config_file" ]] && grep -q "token:" "$config_file" 2>/dev/null; then
    _r2d2_warn "Warning: Token stored in plaintext ($config_file), not keyring."
    _r2d2_warn "  Keyring may be unavailable. Consider securing or removing the config file."
    return 1
  fi
  return 0
}

_r2d2_set_config() {
  local key="$1" value="$2"
  if _r2d2_glab config set --global --host "$_R2_HOST" "$key" "$value"; then
    _r2d2_ok "Set $key"
    return 0
  else
    _r2d2_fail "Failed to set $key"
    return 1
  fi
}

_r2d2_set_git_config() {
  local key="$1" value="$2"
  if command git config --global "$key" "$value"; then
    _r2d2_ok "Set git $key"
    return 0
  else
    _r2d2_fail "Failed to set git $key"
    return 1
  fi
}

_r2d2_set_identity_include() {
  local git_name="$1" git_email="$2"
  local identity_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/r2d2-identity.gitconfig"
  local identity_dir="${identity_file%/*}"

  if ! command mkdir -p "$identity_dir"; then
    _r2d2_fail "Failed to create $identity_dir"
    return 1
  fi

  if command git config -f "$identity_file" user.name "$git_name" \
    && command git config -f "$identity_file" user.email "$git_email"; then
    _r2d2_ok "Wrote git identity to $identity_file"
  else
    _r2d2_fail "Failed to write identity file"
    return 1
  fi

  if command git config --global --replace-all "includeIf.hasconfig:remote.*.url:https://$_R2_HOST/**.path" "$identity_file"; then
    _r2d2_ok "Enabled host-scoped identity include for https://$_R2_HOST"
  else
    _r2d2_fail "Failed to enable host-scoped identity include"
    return 1
  fi
}

# -- Subcommand functions -------------------------------------------------

_r2d2_cmd_config() {
  _r2d2_info "Configuring glab for $_R2_HOST..."

  if ! command -v glab >/dev/null 2>&1; then
    _r2d2_error "Error: glab is not installed."
    return 1
  fi

  local err=0

  _r2d2_set_config container_registry_domains "$_R2_HOST,$_R2_HOST:443,registry.$_R2_HOST" || err=1
  _r2d2_set_config api_host "$_R2_HOST" || err=1
  _r2d2_set_config git_protocol "https" || err=1
  _r2d2_set_config api_protocol "https" || err=1
  _r2d2_set_git_config "credential.https://$_R2_HOST.helper" "!glab auth git-credential" || err=1

  # Telemetry is a global setting (not per-host), so we call glab directly
  # rather than using _r2d2_set_config which adds --host.
  if _r2d2_glab config set --global telemetry disabled; then
    _r2d2_ok "Disabled telemetry"
  else
    _r2d2_fail "Failed to disable telemetry"
    err=1
  fi

  if _r2d2_glab auth status --hostname "$_R2_HOST" >/dev/null 2>&1; then
    _r2d2_success "Authentication already configured for $_R2_HOST."
  else
    _r2d2_warn "glab is not authenticated for $_R2_HOST."
    _r2d2_info "How would you like to authenticate?"
    echo "  1) Paste PAT interactively"
    echo "  2) Read PAT from file"
    echo "  3) Skip (configure manually later)"
    printf '%s' "Choice [1-3]: "
    read -r auth_choice

    case "$auth_choice" in
      1)
        printf '%s' "Paste your PAT: "
        read -s -r pat_token
        echo ""
        if [[ -n "$pat_token" ]]; then
          _r2d2_auth_with_fallback "$pat_token" || err=1
        else
          _r2d2_error "No token provided."
          err=1
        fi
        ;;
      2)
        local pat_file=""
        echo "Path to PAT file (tab completion enabled): "
        read -e -r -p "> " pat_file
        pat_file="${pat_file/#\~/$HOME}"
        if [[ -f "$pat_file" ]]; then
          local pat_content
          pat_content="$(cat "$pat_file")"
          if _r2d2_auth_with_fallback "$pat_content"; then
            printf '%s' "Delete PAT file? [y/N]: "
            read -r delete_choice
            if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
              if rm -f "$pat_file"; then
                _r2d2_success "Deleted $pat_file"
              else
                _r2d2_warn "Could not delete $pat_file"
              fi
            fi
          else
            err=1
          fi
        else
          _r2d2_error "File not found: $pat_file"
          err=1
        fi
        ;;
      3)
        _r2d2_warn "Skipped. Run manually: glab auth login --hostname $_R2_HOST --use-keyring"
        ;;
      *)
        _r2d2_warn "Invalid choice. Run manually: glab auth login --hostname $_R2_HOST --use-keyring"
        ;;
    esac
  fi

  local identity_key="includeIf.hasconfig:remote.*.url:https://$_R2_HOST/**.path"
  local existing_identity_file=""
  existing_identity_file="$(command git config --global --get "$identity_key" 2>/dev/null)"

  if [[ -n "$existing_identity_file" ]]; then
    _r2d2_info "Current host-scoped identity include: $existing_identity_file"
    printf '%s' "Update git author identity for $_R2_HOST repos? [y/N]: "
  else
    printf '%s' "Configure git author identity for $_R2_HOST repos? [y/N]: "
  fi
  read -r identity_choice

  if [[ "$identity_choice" =~ ^[Yy]$ ]]; then
    local git_name="" git_email=""
    printf '%s' "Git author name for $_R2_HOST repos: "
    read -r git_name
    printf '%s' "Git author email for $_R2_HOST repos: "
    read -r git_email

    if [[ -z "$git_name" || -z "$git_email" ]]; then
      _r2d2_error "Name and email are required to configure host-scoped identity."
      err=1
    else
      _r2d2_set_identity_include "$git_name" "$git_email" || err=1
    fi
  fi

  if [[ "$err" -ne 0 ]]; then
    _r2d2_error "One or more configuration steps failed."
    return 1
  fi

  _r2d2_success "Configuration complete for $_R2_HOST."
}

_r2d2_cmd_list_repos() {
  local cmd="$1"
  shift

  _r2d2_require_auth || return 1

  case "$cmd" in
    --mine)    _r2d2_glab repo list --mine "$@" ;;
    --member)  _r2d2_glab repo list --member "$@" ;;
    --starred) _r2d2_glab repo list --starred "$@" ;;
    --user)
      if [[ -z "$1" ]]; then
        _r2d2_error "Error: --user requires a username argument"
        return 1
      fi
      _r2d2_glab repo list --user "$@"
      ;;
  esac
}

_r2d2_cmd_members_add() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
Add a member to the project with the specified role.

Roles:
- guest (10): Can view the project.
- reporter (20): Can view and create issues.
- developer (30): Can push to non-protected branches.
- maintainer (40): Can manage the project.
- owner (50): Full access to the project.

For custom roles, use `--role-id` with the ID of a custom role defined in the project or group.
Note: If the custom role does not exist an error is returned.

USAGE
  r2d2 --members-add [--flags]

EXAMPLES
  # Add a user as a developer
  $ r2d2 --members-add --username=john.doe --role=developer
  # Add a user as a maintainer with expiration date
  $ r2d2 --members-add --username=jane.smith --role=maintainer --expires-at=2024-12-31
  # Add a user by ID
  $ r2d2 --members-add --user-id=123 --role=reporter
  # Add a user with a custom role
  $ r2d2 --members-add --username=john.doe --role-id=101

FLAGS
  -e --expires-at  Expiration date for the membership (YYYY-MM-DD)
  -h --help        Show help for this command.
  -R --repo        Select another repository. Can use either `OWNER/REPO` or `GROUP/NAMESPACE/REPO` format.
  -r --role        Role for the user (guest, reporter, developer, maintainer, owner) (developer)
  --role-id        Id of a custom role defined in the project or group
  -u --user-id     User ID instead of username
  --username       Username instead of user-id
EOF
    return 0
  fi

  _r2d2_require_auth || return 1

  _r2d2_glab repo members add "$@"
}

_r2d2_cmd_members_remove() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<'EOF'
Remove a member from the project.

USAGE
  r2d2 --members-remove [--flags]

EXAMPLES
  # Remove a user by username
  $ r2d2 --members-remove --username=john.doe
  # Remove a user by ID
  $ r2d2 --members-remove --user-id=123

FLAGS
  -h --help     Show help for this command.
  -R --repo     Select another repository. Can use either `OWNER/REPO` or `GROUP/NAMESPACE/REPO` format.
  -u --user-id  User ID instead of username
  --username    Username instead of user-id
EOF
    return 0
  fi

  _r2d2_require_auth || return 1

  _r2d2_glab repo members remove "$@"
}

_r2d2_cmd_clone() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Clone repositories from $_R2_HOST.

Supports shorthand references:
- repo
- namespace/repo
- org/group/repo
- project ID

USAGE
  r2d2 --clone <repo> [<dir>] [-- <gitflags>...] [--flags]
  r2d2 --clone -g <group> [<dir>] [--flags]

EXAMPLES
  # Clone a repository by path
  $ r2d2 --clone cyber/cted/tech/cctc/sec/security-internal

  # Clone using shortcut
  $ r2d2 --clone sec/security-internal

  # Clone by project ID
  $ r2d2 --clone 39397

  # Clone into specific directory
  $ r2d2 --clone sec/security-internal mydirectory

  # Clone all repos in a group
  $ r2d2 --clone -g cyber/cted/tech/cctc/sec --paginate

  # Clone with namespace preservation
  $ r2d2 --clone cyber/cted/tech/cctc/sec/security-internal --preserve-namespace

FLAGS
  -g --group                Specify the group to clone repositories from.
  -p --preserve-namespace   Clone in subdirectory based on namespace.
  -a --archived             Limit by archived status.
  -G --include-subgroups    Include projects in subgroups. (true)
  -m --mine                 Limit by projects owned by current user.
  -v --visibility           Limit by visibility: public, internal, private.
  --paginate                Fetch all pages before cloning.
  --page                    Page number. (1)
  --per-page                Number of items per page. (30)
  -h --help                 Show help for this command.
EOF
    return 0
  fi

  if [[ $# -eq 0 ]]; then
    _r2d2_error "Usage: r2d2 --clone <repo> [-- <gitflags>...]"
    _r2d2_error "Run 'r2d2 --clone --help' for details."
    return 1
  fi

  _r2d2_require_auth || return 1

  local clone_status=0

  # Expand shortcuts for single repo clones (not for -g group clones)
  if [[ "$1" != "-g" && "$1" != "--group" && -n "$1" && "$1" != --* ]]; then
    local repo_path="$1"
    shift

    repo_path="$(_r2d2_expand_repo_path "$repo_path")"
    _r2d2_glab repo clone "$repo_path" "$@"
    clone_status=$?
  else
    # Pass everything through for group clones or flag-first usage
    _r2d2_glab repo clone "$@"
    clone_status=$?
  fi

  if [[ "$clone_status" -eq 128 ]]; then
    _r2d2_warn "Clone failed with exit status 128."
    _r2d2_warn "If this was an SSL certificate error, ensure your system's CA certificates are up to date."
  fi

  return "$clone_status"
}

_r2d2_cmd_search() {
  _r2d2_require_auth || return 1

  local search_path="${1:-cctc}"
  [[ -n "$1" ]] && shift

  search_path="$(_r2d2_expand_repo_path "$search_path")"

  _r2d2_glab repo search --search "$search_path" -F json "$@" \
    | jq -r '["Project ID","Project path"], (.[] | [.id, .path_with_namespace]) | @tsv' \
    | column -t -s $'\t'
}

_r2d2_usage() {
  echo "Usage: r2d2 [option]"
  echo ""
  echo "Options:"
  echo "  --config        Configure glab for $_R2_HOST"
  echo "  --mine          List your own projects"
  echo "  --member        List projects you're a member of"
  echo "  --starred       List starred projects"
  echo "  --user <name>   List projects for a specific user"
  echo "  --list <path>   List repos in a namespace/path"
  echo "  --clone <repo>  Clone a repository (use --help for details)"
  echo "  --members-add      Add a member to a project (use --help for details)"
  echo "  --members-remove   Remove a member from a project (use --help for details)"
  return 1
}

# -- Main function --------------------------------------------------------

r2d2() {
  # Set credential helper once per invocation (not on every glab call)
  command git config --global "credential.https://$_R2_HOST.helper" "!glab auth git-credential" >/dev/null 2>&1 || true

  local cmd="$1"
  [[ -n "$1" ]] && shift

  case "$cmd" in
    --config)         _r2d2_cmd_config "$@" ;;
    --mine|--member|--starred|--user)
                      _r2d2_cmd_list_repos "$cmd" "$@" ;;
    --members-add)    _r2d2_cmd_members_add "$@" ;;
    --members-remove) _r2d2_cmd_members_remove "$@" ;;
    --clone)          _r2d2_cmd_clone "$@" ;;
    --list)           _r2d2_cmd_search "$@" ;;
    *)                _r2d2_usage ;;
  esac
}

# If executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  r2d2 "$@"
fi
