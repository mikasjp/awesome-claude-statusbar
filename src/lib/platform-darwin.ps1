# @awesome-claude-statusbar
# Platform library: macOS (Darwin)
# Provides: Get-BatteryInfo, Get-DiskInfo, Get-MemoryInfo

function Get-BatteryInfo {
    $result = @{ Percent = $null; IsCharging = $false }
    $ioreg = & /usr/sbin/ioreg -rc AppleSmartBattery 2>$null | Out-String
    if ($ioreg -match '"CurrentCapacity"\s*=\s*(\d+)') {
        $current = [int]$Matches[1]
        if ($ioreg -match '"MaxCapacity"\s*=\s*(\d+)') {
            $max = [int]$Matches[1]
            if ($max -gt 0) { $result.Percent = [math]::Round($current * 100 / $max) }
        }
        if ($ioreg -match '"IsCharging"\s*=\s*Yes') {
            $result.IsCharging = $true
        } elseif ($ioreg -match '"ExternalConnected"\s*=\s*Yes') {
            $result.IsCharging = $true
        }
    }
    return $result
}

function Get-DiskInfo {
    $result = @{ TotalGB = 0; UsedGB = 0; FreeGB = 0 }
    $df_line = & df -g / 2>$null | Select-Object -Last 1
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
    $mp_out = & /usr/bin/memory_pressure -Q 2>$null | Out-String
    $mem_free_pct = 0
    if ($mp_out -match '(\d+)%') { $mem_free_pct = [int]$Matches[1] }
    $result.UsedPercent = 100 - $mem_free_pct
    $mem_level = & /usr/sbin/sysctl -n kern.memorystatus_vm_pressure_level 2>$null
    switch ($mem_level) {
        '2' { $result.Level = 'warn' }
        '4' { $result.Level = 'critical' }
    }
    return $result
}
