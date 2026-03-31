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

$L1_1 = "${BOLD}${CYAN}${dir}${RST}${git_part}"
$L1_2 = "`u{1F9E0} ${WHITE}${model}${RST}"
$L1_3 = "ctx: ${c_ctx}"
$L1_4 = "5h: ${c_5h} `u{00B7} 7d: ${c_7d}"

$L2_1 = $disk_text
$L2_2 = $mem_text
$L2_3 = $batt_text
$L2_4 = $docker_text

$cols = @(0, 0, 0, 0)
$L1 = @($L1_1, $L1_2, $L1_3, $L1_4)
$L2 = @($L2_1, $L2_2, $L2_3, $L2_4)
for ($i = 0; $i -lt 4; $i++) {
    $w1 = Get-VisibleWidth $L1[$i]
    $w2 = Get-VisibleWidth $L2[$i]
    $cols[$i] = [math]::Max($w1, $w2)
}

$line1 = (Pad $L1_1 $cols[0]) + $SEP + (Pad $L1_2 $cols[1]) + $SEP + (Pad $L1_3 $cols[2]) + $SEP + $L1_4
$line2 = (Pad $L2_1 $cols[0]) + $SEP + (Pad $L2_2 $cols[1]) + $SEP + (Pad $L2_3 $cols[2]) + $SEP + $L2_4

Write-Host $line1
Write-Host $line2
