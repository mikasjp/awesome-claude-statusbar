# @awesome-claude-statusbar
# Platform library: Linux
# Provides: Get-BatteryInfo, Get-DiskInfo, Get-MemoryInfo

function Get-BatteryInfo {
    $result = @{ Percent = $null; IsCharging = $false }
    $cap_file = '/sys/class/power_supply/BAT0/capacity'
    $status_file = '/sys/class/power_supply/BAT0/status'
    if (Test-Path $cap_file) {
        $result.Percent = [int](Get-Content $cap_file)
        $status = Get-Content $status_file -ErrorAction SilentlyContinue
        if ($status -match 'Charging|Full') { $result.IsCharging = $true }
    }
    return $result
}

function Get-DiskInfo {
    $result = @{ TotalGB = 0; UsedGB = 0; FreeGB = 0 }
    $df_line = & df --block-size=1G / 2>$null | Select-Object -Last 1
    if ($df_line) {
        $fields = $df_line.Trim() -split '\s+'
        $result.TotalGB = [int]$fields[1]
        $result.UsedGB  = [int]$fields[2]
        $result.FreeGB  = [int]$fields[3]
    }
    return $result
}

function Get-MemoryInfo {
    $result = @{ UsedPercent = 0; Level = 'ok' }
    $meminfo = Get-Content /proc/meminfo -ErrorAction SilentlyContinue | Out-String
    $mem_total = 0; $mem_avail = 0
    if ($meminfo -match 'MemTotal:\s+(\d+)')     { $mem_total = [long]$Matches[1] }
    if ($meminfo -match 'MemAvailable:\s+(\d+)') { $mem_avail = [long]$Matches[1] }
    if ($mem_total -gt 0) {
        $result.UsedPercent = [math]::Round(($mem_total - $mem_avail) * 100 / $mem_total)
        if ($result.UsedPercent -ge 85)     { $result.Level = 'critical' }
        elseif ($result.UsedPercent -ge 60) { $result.Level = 'warn' }
    }
    return $result
}
