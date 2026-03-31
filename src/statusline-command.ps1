#!/usr/bin/env pwsh
# @awesome-claude-statusbar
# Claude Code status line — dense developer style with color-coded usage
# Receives JSON via stdin. Cross-platform (Windows / macOS / Linux).
# Requires: statusline-platform.ps1 (OS-specific library) in the same directory.

$ErrorActionPreference = 'SilentlyContinue'

# Load platform library: installed location or repo lib/ directory
$platformLib = Join-Path $PSScriptRoot 'statusline-platform.ps1'
if (-not (Test-Path $platformLib)) {
    # Fallback: detect platform and load from lib/ (running from repo)
    $pname = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } else { 'linux' }
    $platformLib = Join-Path $PSScriptRoot "lib/platform-${pname}.ps1"
}
if (-not (Test-Path $platformLib)) {
    Write-Host "ERROR: platform library not found in $PSScriptRoot"
    exit 1
}
. $platformLib

# --- Parse input ---
$DATA = $input | Out-String
$json = $DATA | ConvertFrom-Json

$dir       = if ($json.workspace.current_dir) { $json.workspace.current_dir } else { '' }
$model     = if ($json.model.display_name)    { $json.model.display_name }    else { '' }
$ctx       = [math]::Round([double]($json.context_window.used_percentage ?? 0))
$r5h       = [math]::Round([double]($json.rate_limits.five_hour.used_percentage ?? 0))
$r7d       = [math]::Round([double]($json.rate_limits.seven_day.used_percentage ?? 0))
$orig_dir  = $dir

# Simplify path: ~/... relative to home
$home_path = [Environment]::GetFolderPath('UserProfile')
if ($dir -and $dir.StartsWith($home_path)) {
    $dir = '~' + $dir.Substring($home_path.Length)
}

# Strip "Claude " prefix from model name
if ($model.StartsWith('Claude ')) {
    $model = $model.Substring(7)
}

# --- ANSI escape sequences ---
$ESC     = [char]0x1B
$RST     = "$ESC[0m"
$BOLD    = "$ESC[1m"
$DIM     = "$ESC[2m"
$GREEN   = "$ESC[32m"
$YELLOW  = "$ESC[33m"
$RED     = "$ESC[31m"
$CYAN    = "$ESC[36m"
$WHITE   = "$ESC[37m"

# --- Utility functions ---

function Color-Usage([int]$val) {
    if ($val -lt 50)     { return "${GREEN}${val}%${RST}" }
    elseif ($val -lt 80) { return "${YELLOW}${val}%${RST}" }
    else                 { return "${RED}${val}%${RST}" }
}

function Color-Level([string]$level) {
    switch ($level) {
        'warn'     { return $YELLOW }
        'critical' { return $RED }
        default    { return $GREEN }
    }
}

function Get-VisibleWidth([string]$text) {
    $stripped = $text -replace "$ESC\[[0-9;]*m", ''
    return $stripped.Length
}

function Pad([string]$text, [int]$target) {
    $w = Get-VisibleWidth $text
    $spaces = $target - $w
    if ($spaces -gt 0) { return $text + (' ' * $spaces) }
    return $text
}

# --- Git branch + status ---
$git_part = ''
if ($orig_dir -and (Get-Command git -ErrorAction SilentlyContinue) -and (& git -C $orig_dir rev-parse --is-inside-work-tree 2>$null)) {
    $branch = & git -C $orig_dir symbolic-ref --short HEAD 2>$null
    if (-not $branch) {
        $branch = & git -C $orig_dir rev-parse --short HEAD 2>$null
    }

    $status_lines = & git -C $orig_dir status --porcelain 2>$null
    $indicator = ''
    $indicator_color = $GREEN

    if (-not $status_lines) {
        $indicator = [char]0x2713
        $indicator_color = $GREEN
    } else {
        $staged    = @($status_lines | Where-Object { $_ -match '^[MADRC]' }).Count
        $unstaged  = @($status_lines | Where-Object { $_ -match '^.[MDRC]' }).Count
        $untracked = @($status_lines | Where-Object { $_ -match '^\?\?' }).Count
        $parts = ''
        if ($staged -gt 0)    { $parts += [char]0x25CF }
        if ($unstaged -gt 0)  { $parts += [char]0x25CB }
        if ($untracked -gt 0) { $parts += '+' }
        $indicator = $parts
        $indicator_color = $YELLOW
    }

    $ab = & git -C $orig_dir rev-list --left-right --count "HEAD...@{upstream}" 2>$null
    if ($ab) {
        $ab_parts = ($ab -split '\s+')
        $ahead  = [int]$ab_parts[0]
        $behind = [int]$ab_parts[1]
        if ($ahead -gt 0)  { $indicator += [char]0x2191 + $ahead }
        if ($behind -gt 0) { $indicator += [char]0x2193 + $behind }
    }

    $git_part = " (${GREEN}${branch}${RST}) ${indicator_color}${indicator}${RST}"
}

# --- Collect data from platform library ---
$c_ctx = Color-Usage $ctx
$c_5h  = Color-Usage $r5h
$c_7d  = Color-Usage $r7d

$batt = Get-BatteryInfo
$disk = Get-DiskInfo
$mem  = Get-MemoryInfo

# --- Format battery ---
if ($null -ne $batt.Percent) {
    $batt_suffix = if ($batt.IsCharging) { " $([char]0x26A1)" } else { '' }
    if ($batt.Percent -gt 50)     { $batt_color = $GREEN }
    elseif ($batt.Percent -gt 20) { $batt_color = $YELLOW }
    else                          { $batt_color = $RED }
    $batt_text = "batt: ${batt_color}$($batt.Percent)%${batt_suffix}${RST}"
} else {
    $batt_text = "batt: ${DIM}n/a${RST}"
}

# --- Format disk ---
if ($disk.TotalGB -gt 0) {
    if ($disk.FreeGB -gt 50)     { $disk_color = $GREEN }
    elseif ($disk.FreeGB -gt 10) { $disk_color = $YELLOW }
    else                         { $disk_color = $RED }
    $disk_text = "disk: ${disk_color}$($disk.UsedGB)G/$($disk.TotalGB)G ($([math]::Round($disk.UsedGB * 100 / $disk.TotalGB))%)${RST}"
} else {
    $disk_text = "disk: ${DIM}?${RST}"
}

# --- Format memory ---
$mem_color = Color-Level $mem.Level
$mem_text = "mem: ${mem_color}$($mem.UsedPercent)% ($($mem.Level))${RST}"

# --- Docker status ---
$docker_text = ''
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $docker_text = "`u{1F433}: n/a"
} else {
    $containers = & docker ps -q 2>$null
    if ($LASTEXITCODE -eq 0) {
        $container_count = if ($containers) { @($containers).Count } else { 0 }
        $docker_text = "`u{1F433}: ${GREEN}up (${container_count})${RST}"
    } else {
        $docker_text = "`u{1F433}: ${DIM}down${RST}"
    }
}

# --- Build output ---
$SEP = " ${DIM}|${RST} "

$dir_short = $dir.Split('/')[-1].Split('\')[-1]
$S_DIR     = "${BOLD}${CYAN}${dir_short}${RST}${git_part}"
$S_MODEL   = "`u{1F9E0} ${WHITE}${model}${RST}"
$S_LIMITS  = "ctx: ${c_ctx} `u{00B7} 5h: ${c_5h} `u{00B7} 7d: ${c_7d}"
$S_SYS     = "${disk_text} `u{00B7} ${mem_text} `u{00B7} ${batt_text} `u{00B7} ${docker_text}"

# Detect terminal width
$TERM_WIDTH = 0

if ($IsWindows) {
    # Windows: parse "mode con" output for Columns
    $modeOutput = & cmd /c "mode con" 2>$null
    if ($modeOutput) {
        $colLine = $modeOutput | Where-Object { $_ -match 'Columns' }
        if ($colLine -match '(\d+)') { $TERM_WIDTH = [int]$Matches[1] }
    }
} else {
    # macOS/Linux: walk process tree for controlling TTY
    $sttyFlag = if ($IsMacOS) { '-f' } else { '-F' }
    $cpid = $PID
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $ppid = (& ps -o ppid= -p $cpid 2>$null)?.Trim()
        if (-not $ppid -or $ppid -eq '0' -or $ppid -eq '1') { break }
        $ttyName = (& ps -o tty= -p $ppid 2>$null)?.Trim()
        if ($ttyName -and $ttyName -ne '??') {
            $ttyDev = "/dev/$ttyName"
            if (-not (Test-Path $ttyDev)) { $ttyDev = "/dev/tty$ttyName" }
            if (Test-Path $ttyDev) {
                $sizeOutput = (& stty $sttyFlag $ttyDev size 2>$null)?.Trim()
                $w = if ($sizeOutput) { ($sizeOutput -split '\s+')[1] } else { $null }
                if ($w -and [int]$w -gt 0) { $TERM_WIDTH = [int]$w; break }
            }
        }
        $cpid = $ppid
    }
}

# Fallback
if (-not $TERM_WIDTH -or $TERM_WIDTH -le 0) { $TERM_WIDTH = 120 }

# Allow manual override
if ($env:STATUSBAR_LAYOUT) {
    switch ($env:STATUSBAR_LAYOUT) {
        'wide'    { $TERM_WIDTH = 200 }
        'compact' { $TERM_WIDTH = 50 }
    }
}

if ($TERM_WIDTH -ge 100) {
    # Wide: dir + limits on one line, system stats, model
    Write-Host ($S_DIR + $SEP + $S_LIMITS)
    Write-Host $S_SYS
    Write-Host $S_MODEL
}
else {
    # Compact: essentials only
    Write-Host $S_DIR
    Write-Host $S_LIMITS
    Write-Host $S_MODEL
}
