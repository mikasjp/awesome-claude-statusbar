# Awesome Claude Code Status Bar

> Bring the awesomeness to your Claude Code terminal.

A dense, color-coded, information-packed status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) that turns your terminal into a cockpit. See everything that matters at a glance -- context usage, rate limits, git state, system health -- without leaving your flow.

The layout adapts to your terminal width automatically:

**Wide (100+ columns)**
```
awesome-claude-statusbar (main) ✓ | ctx: 62% · 5h: 34% · 7d: 13%
disk: 128G/460G (28%) · mem: 42% (ok) · batt: 91% ⚡ · 🐳: up (3)
🧠 Opus 4.6 (1M context)
```

**Medium (80-99 columns)**
```
awesome-claude-statusbar (main) ✓
ctx: 62% · 5h: 34% · 7d: 13%
🧠 Opus 4.6 (1M context)
```

**Narrow (<80 columns)**
```
awesome-claude-statusbar (main) ✓
ctx: 62% · 5h: 34% · 7d: 13%
🧠 Opus 4.6 (1M context)
```

Everything is color-coded: **green** when you're comfortable, **yellow** when you should pay attention, **red** when something needs action.

## What You Get

| Segment | What it shows |
|---------|---------------|
| **Directory + Git** | Current directory name, branch, staged/unstaged/untracked indicators, ahead/behind upstream |
| **Model** | Active Claude model name |
| **Context & Rate limits** | Context window usage, 5-hour and 7-day rate limit usage |
| **Disk** | Used / total with percentage |
| **Memory** | System memory pressure with ok/warn/critical levels |
| **Battery** | Charge percentage + charging indicator |
| **Docker** | Daemon status and running container count |

Git indicators: `✓` clean, `●` staged, `○` unstaged, `+` untracked, `↑↓` ahead/behind.

> System stats (disk, memory, battery, docker) are only shown in the wide layout.

## Installation

### Bash (macOS)

Requires `jq`.

```bash
git clone https://github.com/mikasjp/awesome-claude-statusbar.git
cd awesome-claude-statusbar
bash install.sh
```

### PowerShell (Windows / macOS / Linux)

Requires PowerShell 7+. No other dependencies -- the script uses native PowerShell and .NET APIs.

```powershell
git clone https://github.com/mikasjp/awesome-claude-statusbar.git
cd awesome-claude-statusbar
pwsh install.ps1
```

Then restart Claude Code.

## Updating

The installer registers a global `/update-statusbar` skill in Claude Code. To update to the latest version, just type in any Claude Code session:

```
/update-statusbar
```

This will pull the latest changes from GitHub and re-run the installer automatically.

## Responsive Layout

The status bar detects your terminal width and switches between three layouts:

| Terminal Width | Layout | Content |
|---|---|---|
| **100+** | Wide | Dir + git, limits, system stats, model |
| **80-99** | Medium | Dir + git, limits, model |
| **<80** | Narrow | Dir + git, limits, model |

Width detection works by walking the process tree to find the controlling TTY:
- **macOS**: `stty -f /dev/ttysXXX size`
- **Linux**: `stty -F /dev/pts/X size`
- **Windows**: `mode con`

You can also force a layout with the `STATUSBAR_LAYOUT` environment variable:

```bash
export STATUSBAR_LAYOUT=narrow  # wide | medium | narrow
```

## Smart Installer

The installer is more than just a file copier:

- **Preflight checks** -- verifies all required and optional dependencies before touching anything, with clear pass/warn/fail indicators
- **Detects existing installations** -- if Awesome Claude Status Bar is already installed, it cleanly removes the old version and installs fresh
- **Respects foreign scripts** -- if you have a different status bar script configured, the installer stops and warns you instead of silently overwriting it
- **Force mode** -- override foreign script detection with `--force` (bash) or `-Force` (PowerShell); the foreign script is backed up as `.bak` before overwriting
- **Installs `/update-statusbar` skill** -- registers a global Claude Code skill for easy future updates

```bash
# Override a foreign status line script
bash install.sh --force
pwsh install.ps1 -Force
```

## Architecture

### Bash version

A single self-contained script. macOS only.

```
src/
  statusline-command.sh          # Everything in one file
```

### PowerShell version

Modular, cross-platform architecture with OS-specific platform libraries:

```
src/
  statusline-command.ps1         # Main script (OS-agnostic)
  lib/
    platform-darwin.ps1          # macOS provider
    platform-windows.ps1         # Windows provider
    platform-linux.ps1           # Linux provider
```

Each platform library implements the same interface:

| Function | Returns |
|----------|---------|
| `Get-BatteryInfo` | `@{ Percent; IsCharging }` |
| `Get-DiskInfo` | `@{ TotalGB; UsedGB; FreeGB }` |
| `Get-MemoryInfo` | `@{ UsedPercent; Level }` |

The installer detects your OS and copies the right library as `statusline-platform.ps1` alongside the main script. No dead code, no runtime OS branching -- just the platform code you actually need.

### Skills

```
src/
  skills/
    update-statusbar/
      SKILL.md                   # /update-statusbar skill definition
```

The skill is installed to `~/.claude/skills/update-statusbar/SKILL.md` and handles cloning/pulling the repo and running the appropriate installer.

## How it works

Claude Code supports a `statusLine` configuration in `~/.claude/settings.json`. The status bar script receives JSON with workspace, model, context, and rate limit data via stdin, and outputs ANSI-colored text to render below the input area.

The installer writes this configuration for you:

**Bash (macOS)**
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh",
    "padding": 2
  }
}
```

**PowerShell (cross-platform)**
```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File ~/.claude/statusline-command.ps1",
    "padding": 2
  }
}
```

## Uninstalling

Remove the scripts, skill, and the `statusLine` config from your settings:

### Bash

```bash
rm -f ~/.claude/statusline-command.sh
rm -rf ~/.claude/skills/update-statusbar
jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.tmp && mv ~/.claude/settings.tmp ~/.claude/settings.json
```

### PowerShell

```powershell
Remove-Item ~/.claude/statusline-command.ps1, ~/.claude/statusline-platform.ps1 -ErrorAction SilentlyContinue
Remove-Item ~/.claude/skills/update-statusbar -Recurse -ErrorAction SilentlyContinue
$s = Get-Content ~/.claude/settings.json -Raw | ConvertFrom-Json; $s.PSObject.Properties.Remove('statusLine'); $s | ConvertTo-Json -Depth 10 | Set-Content ~/.claude/settings.json
```

Restart Claude Code after uninstalling.

## Optional Dependencies

Both versions gracefully degrade when optional tools are missing:

| Tool | What happens without it |
|------|------------------------|
| `git` | Git branch/status segment is hidden |
| `docker` | Shows `n/a` instead of container count |
| Battery hardware | Shows `n/a` on desktops without a battery |

## License

MIT
