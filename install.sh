#!/usr/bin/env bash
set -euo pipefail

# r2d2 installer — curl-pipe-bash safe (everything inside main())
# https://github.com/austinkennethtucker/r2d2

# -- Constants ----------------------------------------------------------------

REPO_URL="https://github.com/austinkennethtucker/r2d2.git"
INSTALL_DIR="$HOME/.local/share/r2d2"

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BLUE='\033[0;34m'
_BOLD='\033[1m'
_RESET='\033[0m'

# -- TUI helpers --------------------------------------------------------------

ok()     { printf '  %b✓%b %s\n' "$_GREEN" "$_RESET" "$1"; }
fail()   { printf '  %b✗ %s%b\n' "$_RED" "$1" "$_RESET" >&2; }
warn()   { printf '  %b! %s%b\n' "$_YELLOW" "$1" "$_RESET" >&2; }
info()   { printf '  %b%s%b\n' "$_BLUE" "$1" "$_RESET"; }
header() { printf '%b── %s %b\n' "$_BOLD" "$1" "$_RESET"; }
step()   { printf '%b[%s]%b %s\n' "$_BOLD" "$1" "$_RESET" "$2"; }

die() {
  printf '%b✗ %s%b\n' "$_RED" "$1" "$_RESET" >&2
  exit 1
}

# -- Preflight ----------------------------------------------------------------

preflight() {
  local os
  os="$(uname -s)"
  if [[ "$os" != "Linux" ]]; then
    die "This installer only supports Linux (detected: $os)"
  fi

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required but not found"
  fi

  # Test sudo access early — if missing and deps are needed, we can't proceed
  if ! sudo -v 2>/dev/null; then
    HAS_SUDO=false
  else
    HAS_SUDO=true
  fi
}

# -- Step 1: apt dependencies ------------------------------------------------

install_apt_deps() {
  step "1/4" "Checking apt dependencies"

  # Map: binary name -> apt package name
  local -a missing=()
  local -A pkg_map=( [git]=git [jq]=jq [column]=bsdmainutils )

  for bin in git jq column; do
    local pkg="${pkg_map[$bin]}"
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      ok "$bin"
    else
      missing+=("$pkg")
      info "$bin (will install $pkg)"
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "$HAS_SUDO" != "true" ]]; then
    fail "Missing packages and no sudo access."
    echo "  Run manually:"
    echo "    sudo apt-get update && sudo apt-get install -y ${missing[*]}"
    exit 1
  fi

  if ! sudo apt-get update -qq 2>/dev/null; then
    fail "apt-get update failed"
    warn "If another process holds the apt lock, wait and retry."
    exit 1
  fi

  if ! sudo apt-get install -y "${missing[@]}" >/dev/null 2>&1; then
    fail "apt-get install failed for: ${missing[*]}"
    warn "If another process holds the apt lock, wait and retry."
    exit 1
  fi

  # Verify each package installed
  for pkg in "${missing[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      ok "$pkg installed"
    else
      fail "$pkg failed to install"
      exit 1
    fi
  done
}

# -- Step 2: glab -------------------------------------------------------------

install_glab() {
  step "2/4" "Installing glab"

  if command -v glab >/dev/null 2>&1; then
    local ver
    ver="$(glab --version 2>/dev/null | head -n1)"
    ok "glab already installed ($ver)"
    return 0
  fi

  if [[ "$HAS_SUDO" != "true" ]]; then
    fail "glab is missing and no sudo access to install it."
    exit 1
  fi

  info "Fetching latest glab release..."

  local latest_version
  latest_version="$(
    curl -fsSL "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases" \
      | jq -r '.[0].tag_name'
  )" || die "Failed to fetch glab releases from GitLab API"

  # Strip leading 'v' for the download filename
  local ver="${latest_version#v}"

  local arch
  arch="$(dpkg --print-architecture)" || die "Could not detect architecture"

  case "$arch" in
    amd64|arm64|386) ;;  # supported
    *) die "Unsupported architecture: $arch" ;;
  esac

  local deb_url="https://gitlab.com/gitlab-org/cli/-/releases/${latest_version}/downloads/glab_${ver}_linux_${arch}.deb"
  local tmp_deb="/tmp/glab_${ver}_linux_${arch}.deb"

  info "Downloading glab ${ver} for ${arch}..."
  curl -fsSL -o "$tmp_deb" "$deb_url" || die "Failed to download glab .deb"

  sudo dpkg -i "$tmp_deb" >/dev/null 2>&1 || die "Failed to install glab .deb"
  rm -f "$tmp_deb"

  if command -v glab >/dev/null 2>&1; then
    ok "glab v${ver}"
  else
    fail "glab not found after install"
    exit 1
  fi
}

# -- Step 3: r2d2 files -------------------------------------------------------

install_r2d2() {
  step "3/4" "Installing r2d2"

  if [[ -d "$INSTALL_DIR" ]]; then
    if [[ -d "$INSTALL_DIR/.git" ]]; then
      info "Updating existing install..."
      if git -C "$INSTALL_DIR" pull --ff-only --quiet 2>/dev/null; then
        ok "updated $INSTALL_DIR"
      else
        warn "git pull failed — existing install left as-is"
      fi
      return 0
    else
      warn "$INSTALL_DIR exists but is not a git repo — skipping"
      return 0
    fi
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"

  if git clone --quiet "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
    ok "cloned to $INSTALL_DIR"
  else
    fail "git clone failed"
    exit 1
  fi
}

# -- Step 4: shell rc sourcing ------------------------------------------------

configure_shell() {
  step "4/4" "Configuring shell"

  local shell_name
  shell_name="$(basename "$SHELL")"

  local rc_file source_file
  case "$shell_name" in
    bash)
      rc_file="$HOME/.bashrc"
      source_file="$INSTALL_DIR/r2d2.sh"
      ;;
    zsh)
      rc_file="$HOME/.zshrc"
      source_file="$INSTALL_DIR/r2d2.zsh"
      ;;
    *)
      warn "Unsupported shell: $shell_name"
      warn "Manually add to your shell rc: source $INSTALL_DIR/r2d2.sh"
      return 0
      ;;
  esac

  if grep -qF ".local/share/r2d2/r2d2" "$rc_file" 2>/dev/null; then
    ok "source line already in $rc_file"
    return 0
  fi

  printf '\n# r2d2 - GitLab utilities\nsource "%s"\n' "$source_file" >> "$rc_file"
  ok "source line added to $rc_file"
}

# -- Main ---------------------------------------------------------------------

main() {
  header "r2d2 installer ──────────────────────────────"

  preflight
  install_apt_deps
  install_glab
  install_r2d2
  configure_shell

  header "done ────────────────────────────────────────"
  echo ""
  echo "  Open a new terminal, then run: r2d2 --config"
  echo ""
}

main "$@"
