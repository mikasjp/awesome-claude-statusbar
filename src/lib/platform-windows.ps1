# @awesome-claude-statusbar
# Platform library: Windows
# Provides: Get-BatteryInfo, Get-DiskInfo, Get-MemoryInfo

function Get-BatteryInfo {
    $result = @{ Percent = $null; IsCharging = $false }
    $batt = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
    if ($batt) {
        $result.Percent = $batt.EstimatedChargeRemaining
        # BatteryStatus: 2=AC, 6-9=various charging states
        if ($batt.BatteryStatus -in 2,6,7,8,9) { $result.IsCharging = $true }
    }
    return $result
}

function Get-DiskInfo {
    $result = @{ TotalGB = 0; UsedGB = 0; FreeGB = 0 }
    try {
        $di = [System.IO.DriveInfo]::new('C:\')
        if ($di.IsReady) {
            $result.TotalGB = [math]::Round($di.TotalSize / 1GB)
            $result.FreeGB  = [math]::Round($di.AvailableFreeSpace / 1GB)
            $result.UsedGB  = $result.TotalGB - $result.FreeGB
        }
    } catch {}
    return $result
}

function Get-MemoryInfo {
    $result = @{ UsedPercent = 0; Level = 'ok' }
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os -and $os.TotalVisibleMemorySize -gt 0) {
        $result.UsedPercent = [math]::Round(
            ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100 / $os.TotalVisibleMemorySize
        )
        if ($result.UsedPercent -ge 85)     { $result.Level = 'critical' }
        elseif ($result.UsedPercent -ge 60) { $result.Level = 'warn' }
    }
    return $result
}
