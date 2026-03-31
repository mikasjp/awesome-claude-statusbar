#!/usr/bin/env bash
# @awesome-claude-statusbar
# Claude Code status line — configurable, color-coded developer dashboard
# Receives JSON via stdin. Layout controlled by ~/.claude/statusline.conf

export LC_NUMERIC=C

DATA=$(cat)

# --- Parse JSON input (cheap, always needed) ---
dir=$(echo "$DATA" | jq -r '.workspace.current_dir // ""')
model=$(echo "$DATA" | jq -r '.model.display_name // ""')
ctx=$(echo "$DATA" | jq -r '.context_window.used_percentage // 0' | xargs printf "%.0f")
r5h=$(echo "$DATA" | jq -r '.rate_limits.five_hour.used_percentage // 0' | xargs printf "%.0f")
r7d=$(echo "$DATA" | jq -r '.rate_limits.seven_day.used_percentage // 0' | xargs printf "%.0f")

orig_dir="$dir"
dir="${dir/#$HOME/~}"
model="${model/#Claude /}"

# --- ANSI colors ---
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
WHITE='\033[37m'

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

# --- Segment rendering functions ---
# Each sets SEGMENT_RESULT (avoids subshell forks)

render_dir() {
  SEGMENT_RESULT="${BOLD}${CYAN}${dir}${RST}"
}

render_git() {
  SEGMENT_RESULT=""
  command -v git &>/dev/null || return
  git -C "$orig_dir" rev-parse --is-inside-work-tree &>/dev/null || return

  local branch
  branch=$(git -C "$orig_dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$orig_dir" rev-parse --short HEAD 2>/dev/null)

  local status indicator indicator_color
  status=$(git -C "$orig_dir" status --porcelain 2>/dev/null)

  if [ -z "$status" ]; then
    indicator="\xe2\x9c\x93"
    indicator_color="$GREEN"
  else
    local staged unstaged untracked parts=""
    staged=$(echo "$status" | grep -c '^[MADRC]')
    unstaged=$(echo "$status" | grep -c '^.[MDRC]')
    untracked=$(echo "$status" | grep -c '^??')
    [ "$staged" -gt 0 ] && parts="${parts}\xe2\x97\x8f"
    [ "$unstaged" -gt 0 ] && parts="${parts}\xe2\x97\x8b"
    [ "$untracked" -gt 0 ] && parts="${parts}+"
    indicator="$parts"
    indicator_color="$YELLOW"
  fi

  local ab ahead behind
  ab=$(git -C "$orig_dir" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
  if [ -n "$ab" ]; then
    ahead=$(echo "$ab" | cut -f1)
    behind=$(echo "$ab" | cut -f2)
    [ "$ahead" -gt 0 ] && indicator="${indicator}\xe2\x86\x91${ahead}"
    [ "$behind" -gt 0 ] && indicator="${indicator}\xe2\x86\x93${behind}"
  fi

  SEGMENT_RESULT="(${GREEN}${branch}${RST}) ${indicator_color}${indicator}${RST}"
}

render_model() {
  SEGMENT_RESULT="\xf0\x9f\xa7\xa0 ${WHITE}${model}${RST}"
}

render_context() {
  SEGMENT_RESULT="ctx: $(color_usage "$ctx")"
}

render_rate_limits() {
  SEGMENT_RESULT="5h: $(color_usage "$r5h") \xc2\xb7 7d: $(color_usage "$r7d")"
}

render_disk() {
  local disk_raw disk_total disk_used disk_free disk_pct disk_color
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
      SEGMENT_RESULT="disk: ${disk_color}${disk_used}G/${disk_total}G (${disk_pct}%)${RST}"
      return
    fi
  fi
  SEGMENT_RESULT="disk: ${DIM}?${RST}"
}

render_mem() {
  local mem_level mem_free mem_used
  mem_level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)
  mem_free=$(memory_pressure -Q 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d '%')
  mem_used=$(( 100 - ${mem_free:-0} ))
  case "$mem_level" in
    1)  SEGMENT_RESULT="mem: ${GREEN}${mem_used}% (ok)${RST}" ;;
    2)  SEGMENT_RESULT="mem: ${YELLOW}${mem_used}% (warn)${RST}" ;;
    4)  SEGMENT_RESULT="mem: ${RED}${mem_used}% (critical)${RST}" ;;
    *)  SEGMENT_RESULT="mem: ${GREEN}${mem_used}% (ok)${RST}" ;;
  esac
}

render_batt() {
  local batt_raw batt_pct batt_state batt_suffix batt_color
  batt_raw=$(pmset -g batt 2>/dev/null)
  if [ -n "$batt_raw" ]; then
    batt_pct=$(echo "$batt_raw" | grep -o '[0-9]\+%' | head -1 | tr -d '%')
    if [ -n "$batt_pct" ]; then
      batt_state=$(echo "$batt_raw" | grep -oE '(charging|discharging|charged|finishing charge|AC attached)' | head -1)
      case "$batt_state" in
        charging|"finishing charge") batt_suffix=" \xe2\x9a\xa1" ;;
        charged|"AC attached")      batt_suffix=" \xe2\x9a\xa1" ;;
        *)                           batt_suffix="" ;;
      esac
      if (( batt_pct > 50 )); then
        batt_color="$GREEN"
      elif (( batt_pct > 20 )); then
        batt_color="$YELLOW"
      else
        batt_color="$RED"
      fi
      SEGMENT_RESULT="batt: ${batt_color}${batt_pct}%${batt_suffix}${RST}"
      return
    fi
  fi
  SEGMENT_RESULT="batt: ${DIM}n/a${RST}"
}

render_docker() {
  if ! command -v docker &>/dev/null; then
    SEGMENT_RESULT="\xf0\x9f\x90\xb3: n/a"
    return
  fi
  if docker ps -q &>/dev/null; then
    local container_count
    container_count=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    SEGMENT_RESULT="\xf0\x9f\x90\xb3: ${GREEN}up (${container_count})${RST}"
  else
    SEGMENT_RESULT="\xf0\x9f\x90\xb3: ${DIM}down${RST}"
  fi
}

# --- Config parsing ---

CONFIG_FILE="$HOME/.claude/statusline.conf"
DEFAULT_SEGMENTS="dir git model context rate_limits --- disk mem batt docker"

read_config() {
  # Outputs segment names one per line, with --- as row breaks
  if [[ -f "$CONFIG_FILE" ]]; then
    local has_segments=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs 2>/dev/null)" # trim whitespace
      [[ -z "$line" ]] && continue
      if [[ "$line" =~ ^---+$ ]]; then
        echo "---"
      else
        echo "${line,,}" # lowercase
        has_segments=true
      fi
    done < "$CONFIG_FILE"
    if [[ "$has_segments" == true ]]; then
      return 0
    fi
  fi
  return 1 # use default
}

# --- Build output ---

mapfile -t segments < <(read_config)
if [[ ${#segments[@]} -eq 0 ]]; then
  # shellcheck disable=SC2206
  segments=($DEFAULT_SEGMENTS)
fi

SEP=" ${DIM}|${RST} "
current_row=()
prev_seg=""

flush_row() {
  if [[ ${#current_row[@]} -gt 0 ]]; then
    local row_str=""
    for ((j=0; j<${#current_row[@]}; j++)); do
      if [[ $j -gt 0 ]]; then row_str+="$SEP"; fi
      row_str+="${current_row[$j]}"
    done
    echo -e "$row_str"
    current_row=()
  fi
}

for seg in "${segments[@]}"; do
  if [[ "$seg" == "---" ]]; then
    flush_row
    prev_seg=""
    continue
  fi

  SEGMENT_RESULT=""
  case "$seg" in
    dir)         render_dir ;;
    git)         render_git ;;
    model)       render_model ;;
    context)     render_context ;;
    rate_limits) render_rate_limits ;;
    disk)        render_disk ;;
    mem)         render_mem ;;
    batt)        render_batt ;;
    docker)      render_docker ;;
    *)           continue ;; # unknown segment, skip
  esac

  [[ -z "$SEGMENT_RESULT" ]] && { prev_seg="$seg"; continue; }

  # git after dir → append to same cell (preserves "~/path (main) ✓" look)
  if [[ "$seg" == "git" && "$prev_seg" == "dir" && ${#current_row[@]} -gt 0 ]]; then
    current_row[-1]="${current_row[-1]} ${SEGMENT_RESULT}"
  else
    current_row+=("$SEGMENT_RESULT")
  fi
  prev_seg="$seg"
done

flush_row
