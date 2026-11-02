$voltDir = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $voltDir "voltune.ps1"
$content = Get-Content -Path $scriptPath -Raw

# Extract functions
$functionsOnly = $content -replace '(?s)^.*?function Test-IsAdmin', 'function Test-IsAdmin'
$functionsOnly = $functionsOnly -replace '(?s)#\s*\d+\.\s*ENTRYPOINT LOGIC.*', ''

. ([ScriptBlock]::Create($functionsOnly))

Write-Host "[*] Menguji pembuatan snapshot backup VoltUndo..." -ForegroundColor Cyan
$snapDir = New-VoltBackupSnapshot

if (Test-Path $snapDir) {
    Write-Host "[OK] Snapshot folder berhasil dibuat di: $snapDir" -ForegroundColor Green
    Get-ChildItem -Path $snapDir | Select-Object Name, Length | Format-Table -AutoSize
} else {
    Write-Host "[ERROR] Snapshot folder gagal dibuat." -ForegroundColor Red
    exit 1
}
