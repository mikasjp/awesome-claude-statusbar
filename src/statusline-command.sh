#!/usr/bin/env bash
# @awesome-claude-statusbar
# Claude Code status line — dense developer style with color-coded usage
# Receives JSON via stdin

export LC_NUMERIC=C

DATA=$(cat)

dir=$(echo "$DATA" | jq -r '.workspace.current_dir // ""')
model=$(echo "$DATA" | jq -r '.model.display_name // ""')
ctx=$(echo "$DATA" | jq -r '.context_window.used_percentage // 0' | xargs printf "%.0f")
r5h=$(echo "$DATA" | jq -r '.rate_limits.five_hour.used_percentage // 0' | xargs printf "%.0f")
r7d=$(echo "$DATA" | jq -r '.rate_limits.seven_day.used_percentage // 0' | xargs printf "%.0f")

# Read config file for segment visibility
CONFIG_FILE="$HOME/.claude/awesome-statusbar.json"
if [ -f "$CONFIG_FILE" ]; then
  show_disk=$(jq -r 'if .segments.disk == false then "false" else "true" end' "$CONFIG_FILE")
  show_mem=$(jq -r 'if .segments.mem == false then "false" else "true" end' "$CONFIG_FILE")
  show_batt=$(jq -r 'if .segments.batt == false then "false" else "true" end' "$CONFIG_FILE")
  show_docker=$(jq -r 'if .segments.docker == false then "false" else "true" end' "$CONFIG_FILE")
  show_model=$(jq -r 'if .segments.model == false then "false" else "true" end' "$CONFIG_FILE")
else
  show_disk=true
  show_mem=true
  show_batt=true
  show_docker=true
  show_model=true
fi

# Simplify path: ~/... relative to home
dir="${dir/#$HOME/~}"

# Strip "Claude " prefix from model name
model="${model/#Claude /}"

# ANSI colors
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
WHITE='\033[37m'
MAGENTA='\033[35m'

# Color by usage percentage (higher = worse)
color_usage() {
  local val=$1
  if (( val < 50 )); then
    printf "${GREEN}%s%%${RST}" "$val"
  elif (( val < 80 )); then
    printf "${YELLOW}%s%%${RST}" "$val"
  else
    printf "${RED}%s%%${RST}" "$val"
  fi
}

# Visible width: strip ANSI, count chars, +1 per emoji (they're 2 cols but ${#} counts 1)
vwidth() {
  local stripped
  stripped=$(printf '%b' "$1" | sed $'s/\033\[[0-9;]*m//g')
  local len=${#stripped}
  # Count known wide chars (emojis): 🧠 🐳 ⚡ ✓ ● ○ ↑ ↓
  local emoji_count=0
  [[ "$stripped" == *🧠* ]] && (( emoji_count++ ))
  [[ "$stripped" == *🐳* ]] && (( emoji_count++ ))
  [[ "$stripped" == *⚡* ]] && (( emoji_count++ ))
  echo $(( len + emoji_count ))
}

# Pad segment to target width with trailing spaces
pad() {
  local text="$1"
  local target="$2"
  local w=$(vwidth "$text")
  local spaces=$(( target - w ))
  if (( spaces > 0 )); then
    printf '%b%*s' "$text" "$spaces" ""
  else
    printf '%b' "$text"
  fi
}

# Git branch + status
git_part=""
orig_dir=$(echo "$DATA" | jq -r '.workspace.current_dir // ""')
if command -v git &>/dev/null && git -C "$orig_dir" rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git -C "$orig_dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$orig_dir" rev-parse --short HEAD 2>/dev/null)

  status=$(git -C "$orig_dir" status --porcelain 2>/dev/null)
  emoji=""
  if [ -z "$status" ]; then
    emoji="✓"
    emoji_color="$GREEN"
  else
    staged=$(echo "$status" | grep -c '^[MADRC]')
    unstaged=$(echo "$status" | grep -c '^.[MDRC]')
    untracked=$(echo "$status" | grep -c '^??')
    parts=""
    [ "$staged" -gt 0 ] && parts="${parts}●"
    [ "$unstaged" -gt 0 ] && parts="${parts}○"
    [ "$untracked" -gt 0 ] && parts="${parts}+"
    emoji="$parts"
    emoji_color="$YELLOW"
  fi

  ab=$(git -C "$orig_dir" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ab" ]; then
    ahead=$(echo "$ab" | cut -f1)
    behind=$(echo "$ab" | cut -f2)
    [ "$ahead" -gt 0 ] && emoji="${emoji}↑${ahead}"
    [ "$behind" -gt 0 ] && emoji="${emoji}↓${behind}"
  fi

  git_part=" (${GREEN}${branch}${RST}) ${emoji_color}${emoji}${RST}"
fi

c_ctx=$(color_usage "$ctx")
c_5h=$(color_usage "$r5h")
c_7d=$(color_usage "$r7d")

# Battery info
batt_pct=""
batt_suffix=""
batt_color="$DIM"
if [ "$show_batt" = "true" ]; then
  batt_raw=$(pmset -g batt 2>/dev/null)
  if [ -n "$batt_raw" ]; then
    batt_pct=$(echo "$batt_raw" | grep -o '[0-9]\+%' | head -1 | tr -d '%')
    if [ -n "$batt_pct" ]; then
      batt_state=$(echo "$batt_raw" | grep -oE '(charging|discharging|charged|finishing charge|AC attached)' | head -1)
      case "$batt_state" in
        charging|"finishing charge") batt_suffix=" ⚡" ;;
        charged|"AC attached")      batt_suffix=" ⚡" ;;
        *)                           batt_suffix="" ;;
      esac
      if (( batt_pct > 50 )); then
        batt_color="$GREEN"
      elif (( batt_pct > 20 )); then
        batt_color="$YELLOW"
      else
        batt_color="$RED"
      fi
    fi
  fi
fi

# Docker status
docker_text=""
if [ "$show_docker" = "true" ]; then
  if ! command -v docker &>/dev/null; then
    docker_text="🐳: n/a"
  elif docker ps -q &>/dev/null; then
    container_count=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    docker_text="🐳: ${GREEN}up (${container_count})${RST}"
  else
    docker_text="🐳: ${DIM}down${RST}"
  fi
fi

# Disk usage
disk_text=""
if [ "$show_disk" = "true" ]; then
  disk_text="disk: ?"
  disk_raw=$(df -g / 2>/dev/null | tail -1)
  if [ -n "$disk_raw" ]; then
    disk_total=$(echo "$disk_raw" | awk '{print $2}')
    disk_used=$(echo "$disk_raw" | awk '{print $3}')
    disk_free=$(echo "$disk_raw" | awk '{print $4}')
    if (( disk_total > 0 )); then
      disk_pct=$(( disk_used * 100 / disk_total ))
      if (( disk_free > 50 )); then
        disk_color="$GREEN"
      elif (( disk_free > 10 )); then
        disk_color="$YELLOW"
      else
        disk_color="$RED"
      fi
      disk_text="disk: ${disk_color}${disk_used}G/${disk_total}G (${disk_pct}%)${RST}"
    fi
  fi
fi

# Memory pressure
mem_text=""
if [ "$show_mem" = "true" ]; then
  mem_level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
  mem_free=$(memory_pressure -Q 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d '%')
  mem_used=$(( 100 - ${mem_free:-0} ))
  case "$mem_level" in
    1)  mem_text="mem: ${GREEN}${mem_used}% (ok)${RST}" ;;
    2)  mem_text="mem: ${YELLOW}${mem_used}% (warn)${RST}" ;;
    4)  mem_text="mem: ${RED}${mem_used}% (critical)${RST}" ;;
    *)  mem_text="mem: ${GREEN}${mem_used}% (ok)${RST}" ;;
  esac
fi

# Build segments
SEP=" ${DIM}|${RST} "

S_DIR="${BOLD}${CYAN}${dir##*/}${RST}${git_part}"
S_MODEL="🧠 ${WHITE}${model}${RST}"
S_LIMITS="ctx: ${c_ctx} · 5h: ${c_5h} · 7d: ${c_7d}"
S_BATT=""
if [ "$show_batt" = "true" ]; then
  if [ -n "$batt_pct" ]; then
    S_BATT="batt: ${batt_color}${batt_pct}%${batt_suffix}${RST}"
  else
    S_BATT="batt: ${DIM}n/a${RST}"
  fi
fi

# Build S_SYS dynamically from enabled segments
S_SYS=""
_sys_sep=" · "
if [ "$show_disk" = "true" ] && [ -n "$disk_text" ]; then
  S_SYS="${disk_text}"
fi
if [ "$show_mem" = "true" ] && [ -n "$mem_text" ]; then
  [ -n "$S_SYS" ] && S_SYS="${S_SYS}${_sys_sep}"
  S_SYS="${S_SYS}${mem_text}"
fi
if [ "$show_batt" = "true" ] && [ -n "$S_BATT" ]; then
  [ -n "$S_SYS" ] && S_SYS="${S_SYS}${_sys_sep}"
  S_SYS="${S_SYS}${S_BATT}"
fi
if [ "$show_docker" = "true" ] && [ -n "$docker_text" ]; then
  [ -n "$S_SYS" ] && S_SYS="${S_SYS}${_sys_sep}"
  S_SYS="${S_SYS}${docker_text}"
fi

# Detect terminal width by finding the controlling TTY from the process tree
TERM_WIDTH=""
pid=$$
for _ in 1 2 3 4 5 6; do
  ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -z "$ppid" ] || [ "$ppid" = "0" ] || [ "$ppid" = "1" ] && break
  tty_name=$(ps -o tty= -p "$ppid" 2>/dev/null | tr -d ' ')
  if [ -n "$tty_name" ] && [ "$tty_name" != "??" ]; then
    tty_dev="/dev/$tty_name"
    [ ! -e "$tty_dev" ] && tty_dev="/dev/tty$tty_name"
    if [ -e "$tty_dev" ]; then
      w=$(stty size < "$tty_dev" 2>/dev/null | awk '{print $2}')
      if [ -n "$w" ] && [ "$w" -gt 0 ] 2>/dev/null; then
        TERM_WIDTH=$w
        break
      fi
    fi
  fi
  pid=$ppid
done
: "${TERM_WIDTH:=120}"

# Allow manual override
case "${STATUSBAR_LAYOUT:-}" in
  wide)    TERM_WIDTH=200 ;;
  compact) TERM_WIDTH=50 ;;
esac

if (( TERM_WIDTH >= 100 )); then
  # Wide: dir + limits on one line, system stats, model
  echo -e "${S_DIR}${SEP}${S_LIMITS}"
  [ -n "$S_SYS" ] && echo -e "${S_SYS}"
  [ "$show_model" = "true" ] && echo -e "${S_MODEL}"
else
  # Compact: essentials only
  echo -e "${S_DIR}"
  echo -e "${S_LIMITS}"
  [ "$show_model" = "true" ] && echo -e "${S_MODEL}"
fi
