#!/usr/bin/env pwsh
# @awesome-claude-statusbar
# Claude Code status line — configurable, color-coded developer dashboard
# Receives JSON via stdin. Layout controlled by ~/.claude/statusline.conf

$ErrorActionPreference = 'SilentlyContinue'

# Load platform library: installed location or repo lib/ directory
$platformLib = Join-Path $PSScriptRoot 'statusline-platform.ps1'
if (-not (Test-Path $platformLib)) {
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

# Simplify path
$home_path = [Environment]::GetFolderPath('UserProfile')
if ($dir -and $dir.StartsWith($home_path)) {
    $dir = '~' + $dir.Substring($home_path.Length)
}

# Strip "Claude " prefix
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

# --- Segment rendering functions ---

function Render-Dir {
    return "${BOLD}${CYAN}${dir}${RST}"
}

function Render-Git {
    if (-not $orig_dir -or -not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    if (-not (& git -C $orig_dir rev-parse --is-inside-work-tree 2>$null)) { return $null }

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

    return "(${GREEN}${branch}${RST}) ${indicator_color}${indicator}${RST}"
}

function Render-Model {
    return "`u{1F9E0} ${WHITE}${model}${RST}"
}

function Render-Context {
    return "ctx: $(Color-Usage $ctx)"
}

function Render-RateLimits {
    return "5h: $(Color-Usage $r5h) `u{00B7} 7d: $(Color-Usage $r7d)"
}

function Render-Disk {
    $disk = Get-DiskInfo
    if ($disk.TotalGB -gt 0) {
        if ($disk.FreeGB -gt 50)     { $disk_color = $GREEN }
        elseif ($disk.FreeGB -gt 10) { $disk_color = $YELLOW }
        else                         { $disk_color = $RED }
        return "disk: ${disk_color}$($disk.UsedGB)G/$($disk.TotalGB)G ($([math]::Round($disk.UsedGB * 100 / $disk.TotalGB))%)${RST}"
    }
    return "disk: ${DIM}?${RST}"
}

function Render-Mem {
    $mem = Get-MemoryInfo
    $mem_color = Color-Level $mem.Level
    return "mem: ${mem_color}$($mem.UsedPercent)% ($($mem.Level))${RST}"
}

function Render-Batt {
    $batt = Get-BatteryInfo
    if ($null -ne $batt.Percent) {
        $batt_suffix = if ($batt.IsCharging) { " $([char]0x26A1)" } else { '' }
        if ($batt.Percent -gt 50)     { $batt_color = $GREEN }
        elseif ($batt.Percent -gt 20) { $batt_color = $YELLOW }
        else                          { $batt_color = $RED }
        return "batt: ${batt_color}$($batt.Percent)%${batt_suffix}${RST}"
    }
    return "batt: ${DIM}n/a${RST}"
}

function Render-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return "`u{1F433}: n/a"
    }
    $containers = & docker ps -q 2>$null
    if ($LASTEXITCODE -eq 0) {
        $container_count = if ($containers) { @($containers).Count } else { 0 }
        return "`u{1F433}: ${GREEN}up (${container_count})${RST}"
    }
    return "`u{1F433}: ${DIM}down${RST}"
}

# --- Config parsing ---

$ConfigFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude/statusline.conf'
$DefaultSegments = @('dir','git','model','context','rate_limits','---','disk','mem','batt','docker')

function Read-StatusConfig {
    if (-not (Test-Path $ConfigFile)) { return $null }
    $segments = @()
    $hasSegments = $false
    foreach ($rawLine in Get-Content $ConfigFile) {
        # Strip comments
        $line = ($rawLine -replace '#.*', '').Trim()
        if (-not $line) { continue }
        if ($line -match '^---+$') {
            $segments += '---'
        } else {
            $segments += $line.ToLower()
            $hasSegments = $true
        }
    }
    if ($hasSegments) { return ,$segments }
    return $null
}

# --- Build output ---

$config = Read-StatusConfig
if (-not $config) {
    $config = $DefaultSegments
}

$SEP = " ${DIM}|${RST} "
$currentRow = @()
$prevSeg = ''

foreach ($seg in $config) {
    if ($seg -eq '---') {
        if ($currentRow.Count -gt 0) {
            Write-Host ($currentRow -join $SEP)
            $currentRow = @()
        }
        $prevSeg = ''
        continue
    }

    $cell = switch ($seg) {
        'dir'         { Render-Dir }
        'git'         { Render-Git }
        'model'       { Render-Model }
        'context'     { Render-Context }
        'rate_limits' { Render-RateLimits }
        'disk'        { Render-Disk }
        'mem'         { Render-Mem }
        'batt'        { Render-Batt }
        'docker'      { Render-Docker }
        default       { $null }
    }

    if ($null -eq $cell) { continue }

    # git after dir -> append to same cell (preserves "~/path (main) ✓" look)
    if ($seg -eq 'git' -and $prevSeg -eq 'dir' -and $currentRow.Count -gt 0) {
        $currentRow[-1] += " $cell"
    } else {
        $currentRow += $cell
    }
    $prevSeg = $seg
}

if ($currentRow.Count -gt 0) {
    Write-Host ($currentRow -join $SEP)
}
