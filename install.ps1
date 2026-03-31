#!/usr/bin/env pwsh
#Requires -Version 7.0
param(
    [switch]$Force
)

# ============================================================================
#  Claude Code Status Bar — Installer (PowerShell / cross-platform)
# ============================================================================

$ErrorActionPreference = 'Stop'

$ScriptDir      = $PSScriptRoot
$SrcDir         = Join-Path $ScriptDir 'src'
$SourceScript   = Join-Path $SrcDir 'statusline-command.ps1'
$LibDir         = Join-Path $SrcDir 'lib'
$DestDir        = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'
$DestScript     = Join-Path $DestDir 'statusline-command.ps1'
$DestPlatform   = Join-Path $DestDir 'statusline-platform.ps1'
$SourceConfig   = Join-Path $SrcDir 'statusline.conf.default'
$DestConfig     = Join-Path $DestDir 'statusline.conf'
$SettingsFile   = Join-Path $DestDir 'settings.json'
$Signature      = '@awesome-claude-statusbar'

# Detect platform and pick the right library
if ($IsWindows)    { $platform = 'windows' }
elseif ($IsMacOS)  { $platform = 'darwin' }
else               { $platform = 'linux' }
$SourcePlatform = Join-Path $LibDir "platform-${platform}.ps1"

# --- Colors & Symbols ---
$ESC = [char]0x1B
$RST     = "$ESC[0m"
$BOLD    = "$ESC[1m"
$DIM     = "$ESC[2m"
$RED     = "$ESC[31m"
$GREEN   = "$ESC[32m"
$YELLOW  = "$ESC[33m"
$CYAN    = "$ESC[36m"

# --- Helpers ---
function Write-Header([string]$msg)  { Write-Host "`n  ${BOLD}${CYAN}$msg${RST}" }
function Write-Step([string]$msg)    { Write-Host "    ${CYAN}`u{2192}${RST} $msg" }
function Write-Ok([string]$msg)      { Write-Host "    ${GREEN}`u{2713}${RST} $msg" }
function Write-Warn([string]$msg)    { Write-Host "    ${YELLOW}`u{26A0}${RST} ${YELLOW}$msg${RST}" }
function Write-Fail([string]$msg)    { Write-Host "    ${RED}`u{2717}${RST} ${RED}$msg${RST}" }

function Test-IsOurs([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $head = Get-Content $path -TotalCount 5 -ErrorAction SilentlyContinue
    return ($head -join "`n").Contains($Signature)
}

function Get-ScriptPathFromCommand([string]$cmd) {
    if ($cmd -match '([A-Za-z]:\\[^ ]+\.ps1|/[^ ]+\.(ps1|sh))') {
        return $Matches[1]
    }
    return $null
}

# --- Banner ---
Write-Host ""
Write-Host "  ${BOLD}`u{1F680} Claude Code Status Bar ${DIM}(pwsh installer)${RST}"
Write-Host "  ${DIM}$('=' * 48)${RST}"

# ── Preflight checks ────────────────────────────────────────────────────────

Write-Header "`u{1F50D} Preflight checks"

$errors = 0
$warnings = 0

# Claude Code (required)
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Ok "Claude Code found"
} else {
    Write-Fail "Claude Code is not installed"
    Write-Host "       Install it from: ${BOLD}https://docs.anthropic.com/en/docs/claude-code/overview${RST}"
    exit 1
}

# OS
$os_name = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
Write-Ok "Running on ${BOLD}${os_name}${RST}"

# Source script
if (Test-Path $SourceScript) {
    Write-Ok "Main script found"
} else {
    Write-Fail "statusline-command.ps1 not found in ${ScriptDir}"
    exit 1
}

# Platform library
if (Test-Path $SourcePlatform) {
    Write-Ok "Platform library ${DIM}(${platform})${RST}"
} else {
    Write-Fail "lib/platform-${platform}.ps1 not found"
    $errors++
}

# PowerShell version
Write-Ok "PowerShell ${BOLD}$($PSVersionTable.PSVersion)${RST}"

# git (optional)
if (Get-Command git -ErrorAction SilentlyContinue) {
    $git_ver = (& git --version 2>$null) -replace 'git version ', ''
    Write-Ok "git ${DIM}v${git_ver}${RST}"
} else {
    Write-Warn "git not found `u{2014} git branch/status will not be shown"
    $warnings++
}

# docker (optional)
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $docker_ver = (& docker --version 2>$null) -replace 'Docker version ', '' -replace ',.*', ''
    Write-Ok "docker ${DIM}v${docker_ver}${RST}"
} else {
    Write-Warn "docker not found `u{2014} container status will not be shown"
    $warnings++
}

# macOS-specific optional deps
if ($IsMacOS) {
    if (Test-Path /usr/bin/memory_pressure) {
        Write-Ok "memory_pressure available"
    } else {
        Write-Warn "memory_pressure not found `u{2014} memory info will not be shown"
        $warnings++
    }
}

if ($errors -gt 0) {
    Write-Host ""
    Write-Fail "Cannot continue `u{2014} ${errors} required dependency missing"
    exit 1
}

# ── Detect existing installation ─────────────────────────────────────────────

Write-Header "`u{1F50E} Checking existing configuration"

$existingScript = $null
$existingIsOurs = $null

if (Test-Path $SettingsFile) {
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    $existingCmd = $settings.statusLine.command
    if ($existingCmd) {
        $existingScript = Get-ScriptPathFromCommand $existingCmd
        if ($existingScript -and (Test-Path $existingScript)) {
            if (Test-IsOurs $existingScript) {
                $existingIsOurs = $true
                Write-Ok "Found existing Awesome Claude Status Bar"
                Write-Step "Will remove old installation and install fresh"
            } else {
                $existingIsOurs = $false
                Write-Warn "Found a different status line script: ${DIM}${existingScript}${RST}"
                if ($Force) {
                    Write-Step "Force mode: will back up foreign script and override"
                } else {
                    Write-Fail "Refusing to overwrite a foreign status line script"
                    Write-Host ""
                    Write-Host "    To override, run: ${BOLD}pwsh install.ps1 -Force${RST}"
                    Write-Host ""
                    exit 1
                }
            }
        } else {
            Write-Ok "statusLine configured but script not found on disk `u{2014} will install fresh"
        }
    } else {
        Write-Ok "No statusLine configured `u{2014} fresh install"
    }
} else {
    Write-Ok "No settings.json `u{2014} fresh install"
}

# ── Install ──────────────────────────────────────────────────────────────────

Write-Header "`u{1F4E6} Installing"

if (-not (Test-Path $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

# Handle existing scripts
if ($existingIsOurs -eq $true) {
    # Clean remove our old files
    if (Test-Path $existingScript) {
        Remove-Item $existingScript -Force
        Write-Step "Removed old script ${DIM}${existingScript}${RST}"
    }
    # Also remove old platform library if present
    $existingPlatform = Join-Path $DestDir 'statusline-platform.ps1'
    if (Test-Path $existingPlatform) {
        Remove-Item $existingPlatform -Force
        Write-Step "Removed old platform library ${DIM}${existingPlatform}${RST}"
    }
} elseif ($existingIsOurs -eq $false -and $Force) {
    # Back up the foreign script
    $backupPath = "${existingScript}.bak"
    Move-Item $existingScript $backupPath -Force
    Write-Ok "Backed up foreign script to ${DIM}${backupPath}${RST}"
}

# Copy main script
Copy-Item $SourceScript $DestScript -Force
if (-not $IsWindows) { & chmod +x $DestScript }
Write-Ok "Main script ${DIM}${DestScript}${RST}"

# Copy platform library
Copy-Item $SourcePlatform $DestPlatform -Force
Write-Ok "Platform library ${DIM}(${platform}) ${DestPlatform}${RST}"

# Install default config (preserve existing)
if (Test-Path $DestConfig) {
    Write-Ok "Config preserved ${DIM}${DestConfig}${RST}"
} else {
    Copy-Item $SourceConfig $DestConfig -Force
    Write-Ok "Default config ${DIM}${DestConfig}${RST}"
}

# ── Configure settings.json ──────────────────────────────────────────────────

Write-Header "`u{2699}`u{FE0F}  Configuring Claude Code"

$statusline_config = @{
    type    = 'command'
    command = "pwsh -NoProfile -File ${DestScript}"
    padding = 2
}

if (Test-Path $SettingsFile) {
    # Always update statusLine — we've already handled detection above
    $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    if ($settings.statusLine) {
        $settings.statusLine = $statusline_config
    } else {
        $settings | Add-Member -NotePropertyName 'statusLine' -NotePropertyValue $statusline_config
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile -Encoding UTF8
    Write-Ok "Updated statusLine in ${DIM}${SettingsFile}${RST}"
} else {
    @{ statusLine = $statusline_config } | ConvertTo-Json -Depth 10 | Set-Content $SettingsFile -Encoding UTF8
    Write-Ok "Created ${DIM}${SettingsFile}${RST}"
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ${DIM}$('=' * 48)${RST}"
if ($warnings -gt 0) {
    Write-Host "  `u{2728} ${GREEN}${BOLD}Done!${RST} ${DIM}(${warnings} warning(s) `u{2014} see above)${RST}"
} else {
    Write-Host "  `u{2728} ${GREEN}${BOLD}Done!${RST} All checks passed."
}
Write-Host "  `u{1F504} ${BOLD}Restart Claude Code${RST} to see the status bar."
Write-Host ""
