# Test Voltune Dynamic Syntax & Detection
$voltuneDir = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $voltuneDir "voltune.ps1"
$content = Get-Content -Path $scriptPath -Raw

$parseErrors = $null
$parseTokens = $null
[System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$parseTokens, [ref]$parseErrors) | Out-Null

if ($parseErrors.Count -eq 0) {
    Write-Host "[OK] Syntax Valid! Tidak ada syntax error pada voltune.ps1." -ForegroundColor Green
} else {
    Write-Host "[ERROR] Ditemukan $($parseErrors.Count) error:" -ForegroundColor Red
    foreach ($err in $parseErrors) {
        Write-Host "    Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Red
    }
    exit 1
}

# Extract functions
$functionsOnly = $content -replace '(?s)^.*?function Test-IsAdmin', 'function Test-IsAdmin'
$functionsOnly = $functionsOnly -replace '(?s)# 11\. ENTRYPOINT LOGIC.*', ''

. ([ScriptBlock]::Create($functionsOnly))

$hw = Get-VoltHardwareProfile
Write-Host "`n=== HASIL DETEKSI DINAMIS VOLTUNE ===" -ForegroundColor Cyan
Write-Host "CPU: $($hw.CPUName) | Cores: $($hw.CPUCores) | Threads: $($hw.CPUThreads) | Hybrid: $($hw.IsHybridCPU)"
Write-Host "RAM: $($hw.RAM_GB) GB | Power: $(if ($hw.IsOnBattery) { 'Battery' } else { 'AC Adapter' })"
Write-Host "Display: $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz"
Write-Host "Dynamic FPS Caps: VRR=$($hw.DynamicFPSCaps.TearFreeVRR) | Half=$($hw.DynamicFPSCaps.HalfRate) | Battery=$($hw.DynamicFPSCaps.BatteryCap)"
Write-Host "Drives Terdeteksi:"
foreach ($d in $hw.Drives.Values) {
    Write-Host "  -> $($d.DeviceID) ($($d.Label)): Free $($d.FreeGB) GB / Total $($d.TotalGB) GB"
}
Write-Host "GPU: $($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM | $($hw.DiscreteGPU.TGP_W)W TGP)"
Write-Host "Steam Libraries Ditemukan: $($hw.SteamLibraries -join ' | ')"
Write-Host "Total Game Ditemukan Dinamis: $($hw.DiscoveredGames.Count) game"
foreach ($k in $hw.DiscoveredGames.Keys) {
    $g = $hw.DiscoveredGames[$k]
    Write-Host "  -> [$($g.Platform)] $($g.Name)"
}
