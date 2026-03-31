#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
#  Claude Code Status Bar — Installer (bash/macOS)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/src/statusline-command.sh"
SOURCE_CONFIG="$SCRIPT_DIR/src/statusline.conf.default"
DEST_DIR="$HOME/.claude"
DEST_SCRIPT="$DEST_DIR/statusline-command.sh"
DEST_CONFIG="$DEST_DIR/statusline.conf"
SETTINGS_FILE="$DEST_DIR/settings.json"
SIGNATURE="@awesome-claude-statusbar"

# --- Parse flags ---
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=true ;;
    *)
      echo "Usage: install.sh [--force|-f]" >&2
      exit 1
      ;;
  esac
done

# --- Colors & Symbols ---
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
CYAN='\033[36m'

# --- Helpers ---
header()  { echo -e "\n  ${BOLD}${CYAN}$1${RST}"; }
step()    { echo -e "    ${CYAN}→${RST} $1"; }
ok()      { echo -e "    ${GREEN}✓${RST} $1"; }
warn()    { echo -e "    ${YELLOW}⚠${RST} ${YELLOW}$1${RST}"; }
fail()    { echo -e "    ${RED}✗${RST} ${RED}$1${RST}"; }

# Check if a file contains our signature
is_ours() { head -5 "$1" 2>/dev/null | grep -q "$SIGNATURE"; }

# Extract script path from a statusLine command string like "bash /path/to/script.sh"
extract_script_path() {
  local cmd="$1"
  # Match the last argument that looks like a file path
  echo "$cmd" | grep -oE '/[^ ]+\.(sh|ps1)' | tail -1
}

# --- Banner ---
echo ""
echo -e "  ${BOLD}🚀 Claude Code Status Bar ${DIM}(bash installer)${RST}"
echo -e "  ${DIM}================================================${RST}"

# ── Preflight checks ────────────────────────────────────────────────────────

header "🔍 Preflight checks"

errors=0
warnings=0

# Claude Code (required)
if command -v claude &>/dev/null; then
  ok "Claude Code found"
else
  fail "Claude Code is not installed"
  echo -e "       Install it from: ${BOLD}https://docs.anthropic.com/en/docs/claude-code/overview${RST}"
  exit 1
fi

# OS
if [[ "$(uname -s)" == "Darwin" ]]; then
  ok "Running on ${BOLD}macOS${RST}"
else
  fail "This installer requires macOS (use install.ps1 for other platforms)"
  exit 1
fi

# Source script
if [[ -f "$SOURCE_SCRIPT" ]]; then
  ok "Source script found"
else
  fail "statusline-command.sh not found in $SCRIPT_DIR"
  exit 1
fi

# jq (required)
if command -v jq &>/dev/null; then
  ok "jq ${DIM}$(jq --version 2>&1)${RST}"
else
  fail "jq is required but not installed"
  echo -e "       Install it with: ${BOLD}brew install jq${RST}"
  errors=$((errors + 1))
fi

# git (optional)
if command -v git &>/dev/null; then
  git_ver=$(git --version 2>&1 | sed 's/git version //')
  ok "git ${DIM}v${git_ver}${RST}"
else
  warn "git not found — git branch/status will not be shown"
  warnings=$((warnings + 1))
fi

# docker (optional)
if command -v docker &>/dev/null; then
  docker_ver=$(docker --version 2>&1 | sed 's/Docker version //;s/,.*//')
  ok "docker ${DIM}v${docker_ver}${RST}"
else
  warn "docker not found — container status will not be shown"
  warnings=$((warnings + 1))
fi

if [[ $errors -gt 0 ]]; then
  echo ""
  fail "Cannot continue — $errors required dependency missing"
  exit 1
fi

# ── Detect existing installation ─────────────────────────────────────────────

header "🔎 Checking existing configuration"

existing_script=""
existing_is_ours=""

if [[ -f "$SETTINGS_FILE" ]]; then
  existing_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS_FILE")
  if [[ -n "$existing_cmd" ]]; then
    existing_script=$(extract_script_path "$existing_cmd")
    if [[ -n "$existing_script" && -f "$existing_script" ]]; then
      if is_ours "$existing_script"; then
        existing_is_ours=true
        ok "Found existing Awesome Claude Status Bar"
        step "Will remove old installation and install fresh"
      else
        existing_is_ours=false
        warn "Found a different status line script: ${DIM}${existing_script}${RST}"
        if [[ "$FORCE" == true ]]; then
          step "Force mode: will back up foreign script and override"
        else
          fail "Refusing to overwrite a foreign status line script"
          echo ""
          echo -e "    To override, run: ${BOLD}bash install.sh --force${RST}"
          echo ""
          exit 1
        fi
      fi
    else
      ok "statusLine configured but script not found on disk — will install fresh"
    fi
  else
    ok "No statusLine configured — fresh install"
  fi
else
  ok "No settings.json — fresh install"
fi

# ── Install ──────────────────────────────────────────────────────────────────

header "📦 Installing"

mkdir -p "$DEST_DIR"

# Handle existing scripts
if [[ "$existing_is_ours" == true ]]; then
  # Clean remove our old files
  if [[ -f "$existing_script" ]]; then
    rm "$existing_script"
    step "Removed old script ${DIM}${existing_script}${RST}"
  fi
elif [[ "$existing_is_ours" == false && "$FORCE" == true ]]; then
  # Back up the foreign script
  mv "$existing_script" "${existing_script}.bak"
  ok "Backed up foreign script to ${DIM}${existing_script}.bak${RST}"
fi

cp "$SOURCE_SCRIPT" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
ok "Installed ${DIM}${DEST_SCRIPT}${RST}"

# Install default config (preserve existing)
if [[ -f "$DEST_CONFIG" ]]; then
  ok "Config preserved ${DIM}${DEST_CONFIG}${RST}"
else
  cp "$SOURCE_CONFIG" "$DEST_CONFIG"
  ok "Default config ${DIM}${DEST_CONFIG}${RST}"
fi

# ── Configure settings.json ──────────────────────────────────────────────────

header "⚙️  Configuring Claude Code"

STATUSLINE_CONFIG='{"type":"command","command":"bash '"$DEST_SCRIPT"'","padding":2}'

if [[ -f "$SETTINGS_FILE" ]]; then
  # Always update statusLine — we've already handled detection above
  jq --argjson sl "$STATUSLINE_CONFIG" '.statusLine = $sl' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp"
  mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  ok "Updated statusLine in ${DIM}${SETTINGS_FILE}${RST}"
else
  echo "{}" | jq --argjson sl "$STATUSLINE_CONFIG" '.statusLine = $sl' > "$SETTINGS_FILE"
  ok "Created ${DIM}${SETTINGS_FILE}${RST}"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "  ${DIM}================================================${RST}"
if [[ $warnings -gt 0 ]]; then
  echo -e "  ✨ ${GREEN}${BOLD}Done!${RST} ${DIM}(${warnings} warning(s) — see above)${RST}"
else
  echo -e "  ✨ ${GREEN}${BOLD}Done!${RST} All checks passed."
fi
echo -e "  🔄 ${BOLD}Restart Claude Code${RST} to see the status bar."
echo ""
