# Test Voltune Script Syntax & Detection
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

# Extract functions only and skip top elevation & entrypoint loop
$functionsOnly = $content -replace '(?s)^.*?function Test-IsAdmin', 'function Test-IsAdmin'
$functionsOnly = $functionsOnly -replace '(?s)# 11\. ENTRYPOINT LOGIC.*', ''

. ([ScriptBlock]::Create($functionsOnly))

$hw = Get-VoltHardwareProfile
Write-Host "`n=== HASIL DETEKSI HARDWARE VOLTUNE ===" -ForegroundColor Cyan
Write-Host "CPU: $($hw.CPUName)"
Write-Host "Cores/Threads: $($hw.CPUCores) Cores, $($hw.CPUThreads) Threads (Hybrid: $($hw.IsHybridCPU))"
Write-Host "RAM: $($hw.RAM_GB) GB | Disk C Free: $($hw.DriveC_FreeGB) GB"
Write-Host "Display: $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz"
Write-Host "GPU Flags -> NVIDIA: $($hw.HasNvidiaGPU) | AMD: $($hw.HasAmdGPU) | Intel: $($hw.HasIntelGPU)"
if ($hw.DiscreteGPU) {
    Write-Host "Discrete GPU: $($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM)"
}
Write-Host "HAGS Status: $($hw.HAGS_Status)"
Write-Host "Games Found: $($hw.InstalledGames.Keys -join ', ')"
foreach ($k in $hw.InstalledGames.Keys) {
    $game = $hw.InstalledGames[$k]
    Write-Host "  -> $k : $($game.Name) [$($game.Type)] ($($game.ConfigPath))"
}
