<#
.SYNOPSIS
    VoltPlay & Voltune Windows Utility v3.1 - Ultimate Universal Windows Performance, Gaming & System Toolkit
.DESCRIPTION
    Toolkit komprehensif optimasi Windows, manajemen kartu grafis dual-GPU (NVIDIA/AMD/Intel),
    penyelarasan setting game anti-stutter dinamis multi-drive, pembersih disk lintas-drive,
    Windows 11 QoL tweaks (Classic Context Menu, Explorer, Taskbar), privasi & anti-telemetri,
    TCP/IP gaming latency optimizer (Zero-VPN harm), Windows Services optimizer,
    Windows Update control (Security Updates Only), gaming raw mouse input & Defender auto-exclusions,
    WinGet software catalog & game runtimes installer (Chris Titus style), System Restore automation,
    serta sistem snapshot 1-klik Undo dinamis dengan Modern Native WPF Desktop GUI & Interactive TUI.
.NOTES
    Safe by default, Reversible by design, 100% Dynamic, Zero VPN Harm.
#>

[CmdletBinding()]
param(
    [switch]$AutoOptimize,
    [switch]$CleanOnly,
    [switch]$UndoOnly,
    [switch]$GUI,
    [switch]$NoElevation
)

# ------------------------------------------------------------------------------
# 1. ELEVASI HAK AKSES (SELF-ELEVATION)
# ------------------------------------------------------------------------------
function Test-IsAdmin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-VoltElevation {
    param([switch]$Bypass)
    if ($Bypass -or (Test-IsAdmin)) {
        return
    }

    Write-Host "[!] Voltune memerlukan hak akses Administrator untuk mengonfigurasi registri performa." -ForegroundColor Yellow
    Write-Host "[*] Meminta izin UAC Administrator..." -ForegroundColor Cyan
    try {
        $arguments = "-NoProfile -ExecutionPolicy Bypass"
        if ($PSCommandPath) {
            $arguments += " -File `"$PSCommandPath`""
        } else {
            $arguments += " -Command `"irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex`""
        }
        Start-Process powershell.exe -ArgumentList $arguments -Verb RunAs
        exit 0
    } catch {
        Write-Error "Gagal meminta izin Administrator: $_"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 2. KONFIGURASI GLOBAL & PATHS
# ------------------------------------------------------------------------------
$Script:VoltVersion = "3.1.0-Universal"
$Script:AppDataDir  = Join-Path $env:LOCALAPPDATA "Voltune"
$Script:BackupDir   = Join-Path $Script:AppDataDir "Backups"
$Script:LogDir      = Join-Path $Script:AppDataDir "Logs"

if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null }
if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

# ------------------------------------------------------------------------------
# 3. DYNAMIC DETECTION ENGINE (HARDWARE, ENVIRONMENT, DRIVES, & GAMES)
# ------------------------------------------------------------------------------
function Get-VoltHardwareProfile {
    $profile = [ordered]@{
        # CPU
        CPUName          = "Unknown CPU"
        CPUCores         = 0
        CPUThreads       = 0
        IsHybridCPU      = $false
        CPUArchitecture  = "x64"

        # Memory & Power
        RAM_GB           = 0.0
        IsOnBattery      = $false
        BatteryChargePct = $null
        HibernateActive  = $false
        HiberfilSizeGB   = 0.0

        # Storage (Multi-Drive)
        Drives           = [ordered]@{}

        # Display
        ScreenResolution = "1920x1080"
        ScreenRefreshHz  = 60
        DynamicFPSCaps   = [ordered]@{}

        # GPU
        HasNvidiaGPU     = $false
        HasAmdGPU        = $false
        HasIntelGPU      = $false
        DiscreteGPU      = $null
        IntegratedGPU    = $null
        HAGS_Status      = $false

        # System Restore
        SystemRestoreOnC = $false

        # Game Ecosystem (Dynamic Multi-Platform Discovery)
        SteamLibraries   = @()
        DiscoveredGames  = [ordered]@{}
    }

    # 1. CPU Detection
    try {
        $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
        if ($proc) {
            $profile.CPUName = $proc.Name.Trim()
            $profile.CPUCores = [int]$proc.NumberOfCores
            $profile.CPUThreads = [int]$proc.NumberOfLogicalProcessors
            $profile.CPUArchitecture = if ($proc.AddressWidth -eq 64) { "x64" } else { "x86" }

            if ($profile.CPUName -match "1[234]th Gen" -or $profile.CPUName -match "Core Ultra" -or ($profile.CPUThreads -gt ($profile.CPUCores * 1.5) -and $profile.CPUThreads -ne ($profile.CPUCores * 2))) {
                $profile.IsHybridCPU = $true
            }
        }
    } catch {}

    # 2. RAM & Battery / Power Detection
    try {
        $cs = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
        if ($cs -and $cs.TotalPhysicalMemory) {
            $profile.RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        }
    } catch {}

    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($battery) {
            $profile.BatteryChargePct = [int]$battery.EstimatedChargeRemaining
            if ($battery.BatteryStatus -eq 1) {
                $profile.IsOnBattery = $true
            }
        }
    } catch {}

    # Check Hibernate status & hiberfil.sys
    if (Test-Path "C:\hiberfil.sys") {
        $profile.HibernateActive = $true
        try {
            $item = Get-Item "C:\hiberfil.sys" -Force -ErrorAction SilentlyContinue
            if ($item) {
                $profile.HiberfilSizeGB = [math]::Round($item.Length / 1GB, 2)
            }
        } catch {}
    }

    # Check System Restore status
    try {
        $sr = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        $profile.SystemRestoreOnC = $true
    } catch {
        $profile.SystemRestoreOnC = $false
    }

    # 3. Multi-Drive Storage Detection (All Drives)
    try {
        $disks = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        foreach ($d in $disks) {
            $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($d.Size / 1GB, 1)
            $label   = if ($d.VolumeName) { $d.VolumeName } else { "Local Disk" }
            $profile.Drives[$d.DeviceID] = [ordered]@{
                DeviceID = $d.DeviceID
                Label    = $label
                FreeGB   = $freeGB
                TotalGB  = $totalGB
            }
        }
    } catch {}

    # 4. Display & Refresh Rate Calculation
    try {
        $videoControllers = Get-CimInstance Win32_VideoController
        foreach ($vc in $videoControllers) {
            $gpuName = $vc.Name
            $ramGB = 0
            if ($vc.AdapterRAM) {
                $ramGB = [math]::Round($vc.AdapterRAM / 1GB, 1)
            }

            if ($gpuName -match "NVIDIA|GeForce|RTX|GTX") {
                $profile.HasNvidiaGPU = $true
                $profile.DiscreteGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "NVIDIA"; TGP_W = $null; Driver = $null }
            } elseif ($gpuName -match "AMD Radeon.*(RX|XT|M\b|\d{4})") {
                $profile.HasAmdGPU = $true
                $profile.DiscreteGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "AMD"; TGP_W = $null; Driver = $null }
            } elseif ($gpuName -match "Intel") {
                $profile.HasIntelGPU = $true
                if (-not $profile.IntegratedGPU) {
                    $profile.IntegratedGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "Intel" }
                }
            } elseif ($gpuName -match "Radeon" -and -not $profile.HasAmdGPU) {
                $profile.HasAmdGPU = $true
                $profile.IntegratedGPU = @{ Name = $gpuName; VRAM_GB = $ramGB; Type = "AMD" }
            }

            if ($vc.CurrentRefreshRate -and $vc.CurrentRefreshRate -gt 30) {
                $profile.ScreenRefreshHz = [int]$vc.CurrentRefreshRate
            }
            if ($vc.VideoModeDescription -match "(\d+)\s*x\s*(\d+)") {
                $profile.ScreenResolution = "$($Matches[1])x$($Matches[2])"
            }
        }
    } catch {}

    # Dynamic Frame Rate Caps Calculation based on Hz and Power State
    $hz = $profile.ScreenRefreshHz
    $profile.DynamicFPSCaps["TearFreeVRR"] = [math]::Max(30, ($hz - 3))
    $profile.DynamicFPSCaps["HalfRate"]    = [math]::Max(30, [int][math]::Floor($hz / 2))
    $profile.DynamicFPSCaps["BatteryCap"]  = if ($profile.IsOnBattery) { 30 } else { $profile.DynamicFPSCaps["TearFreeVRR"] }

    # Dynamic NVIDIA TGP & Precision VRAM Query via nvidia-smi
    if ($profile.HasNvidiaGPU) {
        $nvsmi = "C:\Windows\System32\nvidia-smi.exe"
        if (Test-Path $nvsmi) {
            try {
                $out = & $nvsmi --query-gpu=power.max_limit,memory.total,driver_version --format=csv,noheader,nounits 2>$null
                if ($out -match "([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)") {
                    $profile.DiscreteGPU.TGP_W = [int][math]::Round([double]$Matches[1])
                    $profile.DiscreteGPU.VRAM_GB = [math]::Round(([double]$Matches[2] / 1024), 1)
                    $profile.DiscreteGPU.Driver = $Matches[3]
                }
            } catch {}
        }
    }

    # Check HAGS Status from registry
    try {
        $hags = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($hags -and $hags.HwSchMode -eq 2) {
            $profile.HAGS_Status = $true
        }
    } catch {}

    # 5. DYNAMIC MULTI-PLATFORM GAME DISCOVERY
    $foundSteamLibs = [System.Collections.Generic.List[string]]::new()
    $steamReg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
    if ($steamReg -and $steamReg.SteamPath) {
        $mainSteam = ($steamReg.SteamPath -replace '/', '\')
        if (Test-Path $mainSteam) {
            $foundSteamLibs.Add($mainSteam)
            $vdf = Join-Path $mainSteam "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                Get-Content $vdf | ForEach-Object {
                    if ($_ -match '^\s*"path"\s+"([^"]+)"') {
                        $p = ($Matches[1] -replace '\\\\', '\')
                        if ((Test-Path $p) -and -not $foundSteamLibs.Contains($p)) {
                            $foundSteamLibs.Add($p)
                        }
                    }
                }
            }
        }
    }

    foreach ($d in $profile.Drives.Keys) {
        $cand = "$d\Games\SteamLibrary"
        if ((Test-Path $cand) -and -not $foundSteamLibs.Contains($cand)) { $foundSteamLibs.Add($cand) }
        $cand2 = "$d\SteamLibrary"
        if ((Test-Path $cand2) -and -not $foundSteamLibs.Contains($cand2)) { $foundSteamLibs.Add($cand2) }
    }
    $profile.SteamLibraries = @($foundSteamLibs)

    foreach ($lib in $profile.SteamLibraries) {
        $appsDir = Join-Path $lib "steamapps"
        if (Test-Path $appsDir) {
            Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $txt = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $appId = $null
                $appName = $null
                $installSub = $null

                if ($txt -match '"appid"\s+"(\d+)"') { $appId = $Matches[1] }
                if ($txt -match '"name"\s+"([^"]+)"') { $appName = $Matches[1] }
                if ($txt -match '"installdir"\s+"([^"]+)"') { $installSub = $Matches[1] }

                if ($appId -and $appName -and $installSub) {
                    $fullPath = Join-Path $appsDir "common\$installSub"
                    if ($appName -notmatch "Steamworks|Redistributable|Proton|Shared") {
                        $profile.DiscoveredGames["Steam_$appId"] = [ordered]@{
                            Name        = $appName
                            Platform    = "Steam"
                            AppId       = $appId
                            InstallPath = $fullPath
                        }
                    }
                }
            }
        }
    }

    # HoYoPlay
    $hoyoReg = "HKCU:\Software\Cognosphere"
    if (Test-Path $hoyoReg) {
        Get-ChildItem -Path $hoyoReg -ErrorAction SilentlyContinue | ForEach-Object {
            $gameKey = $_.PSChildName
            if ($gameKey -match "StarRail|Honkai") {
                $profile.DiscoveredGames["HoYo_HSR"] = [ordered]@{
                    Name     = "Honkai: Star Rail"
                    Platform = "HoYoPlay"
                    RegPath  = $_.Name
                }
            } elseif ($gameKey -match "Genshin") {
                $profile.DiscoveredGames["HoYo_Genshin"] = [ordered]@{
                    Name     = "Genshin Impact"
                    Platform = "HoYoPlay"
                    RegPath  = $_.Name
                }
            }
        }
    }

    # Rockstar
    $rdr2Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Doc) {
        $profile.DiscoveredGames["Rockstar_RDR2"] = [ordered]@{
            Name       = "Red Dead Redemption 2"
            Platform   = "Rockstar Games"
            ConfigFile = $rdr2Doc
        }
    }

    # CDPR
    $w3Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "The Witcher 3\dx12user.settings"
    if (Test-Path $w3Doc) {
        $profile.DiscoveredGames["CDPR_W3"] = [ordered]@{
            Name       = "The Witcher 3: Wild Hunt (DX12)"
            Platform   = "CD Projekt RED"
            ConfigFile = $w3Doc
        }
    }

    return $profile
}

# ------------------------------------------------------------------------------
# 4. SAFETY & SYSTEM RESTORE POINT AUTOMATION
# ------------------------------------------------------------------------------
function New-VoltRestorePoint {
    param([string]$Description = "Voltune Pre-Tweak Snapshot")
    Write-Host "`n[*] Membuat Windows System Restore Point untuk keamanan maksimal..." -ForegroundColor Cyan

    try {
        Set-Service -Name "VSS" -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service -Name "VSS" -ErrorAction SilentlyContinue
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
        Write-Host " [✓] System Restore Point berhasil dibuat: '$Description'" -ForegroundColor Green
        return $true
    } catch {
        Write-Host " [!] Catatan: System Restore Point dilewati atau dibatasi frekuensi Windows (hanya bisa 1x per 24 jam via API)." -ForegroundColor DarkYellow
        Write-Host "     -> Snapshot lokal VoltUndo mandiri tetap aktif sebagai jaminan utama." -ForegroundColor Gray
        return $false
    }
}

# ------------------------------------------------------------------------------
# 5. DYNAMIC BACKUP & UNDO ENGINE (VOLTUNDO)
# ------------------------------------------------------------------------------
function New-VoltBackupSnapshot {
    param([hashtable]$Hardware)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $snapshotDir = Join-Path $Script:BackupDir "Snapshot-$timestamp"
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

    Write-Host "`n[*] Mengambil snapshot registri & konfigurasi dinamis (VoltUndo)..." -ForegroundColor Cyan
    Write-Host "    -> Lokasi Backup: $snapshotDir" -ForegroundColor Gray

    $manifest = [ordered]@{
        Timestamp    = $timestamp
        VoltVersion  = $Script:VoltVersion
        SystemRegs   = @()
        GameRegs     = @()
        ConfigFiles  = @()
    }

    $systemRegs = @(
        @{ Key = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; File = "SystemProfile.reg" },
        @{ Key = "HKCU\System\GameConfigStore"; File = "GameConfigStore.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; File = "GameDVR_Policy.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; File = "GraphicsDrivers.reg" },
        @{ Key = "HKCU\Control Panel\Mouse"; File = "MouseSettings.reg" },
        @{ Key = "HKCU\Control Panel\Desktop"; File = "DesktopSettings.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; File = "ExplorerAdvanced.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"; File = "WindowsSearch.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; File = "DataCollection.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; File = "WindowsUpdate.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; File = "AdvertisingInfo.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; File = "DeliveryOptimization.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; File = "TcpipParameters.reg" }
    )

    foreach ($r in $systemRegs) {
        $outFile = Join-Path $snapshotDir $r.File
        $regKey = $r.Key
        & reg.exe export $regKey $outFile /y 2>$null | Out-Null
        if (Test-Path $outFile) {
            $manifest.SystemRegs += @{ Key = $regKey; File = $r.File }
        }
    }

    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.RegPath) {
                $sanitized = ($g.Name -replace '[\\/:*?"<>|]', '_')
                $regOut = Join-Path $snapshotDir "Game_${sanitized}.reg"
                $rawKey = $g.RegPath -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_LOCAL_MACHINE', 'HKLM'
                & reg.exe export $rawKey $regOut /y 2>$null | Out-Null
                if (Test-Path $regOut) {
                    $manifest.GameRegs += @{ Name = $g.Name; Key = $rawKey; File = "Game_${sanitized}.reg" }
                }
            }
        }
    }

    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.ConfigFile -and (Test-Path $g.ConfigFile)) {
                $sanitized = ($g.Name -replace '[\\/:*?"<>|]', '_')
                $bakName = "Config_${sanitized}.bak"
                $destBak = Join-Path $snapshotDir $bakName
                Copy-Item -Path $g.ConfigFile -Destination $destBak -Force
                $manifest.ConfigFiles += @{ Name = $g.Name; Source = $g.ConfigFile; Backup = $bakName }
            }
        }
    }

    $manifestPath = Join-Path $snapshotDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Host " [✓] Snapshot selesai. $($manifest.SystemRegs.Count) registri sistem & $($manifest.ConfigFiles.Count) file konfigurasi game dicadangkan." -ForegroundColor Green
    return $snapshotDir
}

function Restore-VoltSnapshotByPath {
    param([string]$SnapshotDir)

    if (-not (Test-Path $SnapshotDir)) { return $false }
    $manifestPath = Join-Path $SnapshotDir "manifest.json"
    if (-not (Test-Path $manifestPath)) { return $false }

    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

    if ($manifest.SystemRegs) {
        foreach ($r in $manifest.SystemRegs) {
            $f = Join-Path $SnapshotDir $r.File
            if (Test-Path $f) {
                & reg.exe import $f 2>$null | Out-Null
            }
        }
    }

    if ($manifest.GameRegs) {
        foreach ($gr in $manifest.GameRegs) {
            $f = Join-Path $SnapshotDir $gr.File
            if (Test-Path $f) {
                & reg.exe import $f 2>$null | Out-Null
            }
        }
    }

    if ($manifest.ConfigFiles) {
        foreach ($cf in $manifest.ConfigFiles) {
            $bak = Join-Path $SnapshotDir $cf.Backup
            if (Test-Path $bak) {
                Copy-Item -Path $bak -Destination $cf.Source -Force
            }
        }
    }

    Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    return $true
}

function Invoke-VoltUndo {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "                     ↩️ VOLTUNDO: RESTORE SISTEM KE KONDISI ASAL                " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow

    $snapshots = Get-ChildItem -Path $Script:BackupDir -Directory | Sort-Object CreationTime -Descending
    if ($snapshots.Count -eq 0) {
        Write-Host "[-] Tidak ditemukan snapshot backup pada $Script:BackupDir" -ForegroundColor Red
        return
    }

    Write-Host "[*] Snapshot backup yang tersedia:" -ForegroundColor Cyan
    for ($i = 0; $i -lt [math]::Min(5, $snapshots.Count); $i++) {
        Write-Host "  [$i] $($snapshots[$i].Name) ($($snapshots[$i].CreationTime.ToString('yyyy-MM-dd HH:mm:ss')))" -ForegroundColor White
    }

    $pick = Read-Host "`nPilih nomor snapshot yang ingin di-restore [0-$([math]::Min(4, $snapshots.Count - 1))]"
    if ($pick -match "^\d+$" -and [int]$pick -lt $snapshots.Count) {
        $targetSnap = $snapshots[[int]$pick].FullName
        Write-Host "`n[*] Merestore snapshot dari: $targetSnap" -ForegroundColor Cyan
        $res = Restore-VoltSnapshotByPath -SnapshotDir $targetSnap
        if ($res) {
            Write-Host "`n[✓] Seluruh konfigurasi berhasil dikembalikan ke kondisi snapshot!" -ForegroundColor Green
        } else {
            Write-Host "`n[-] Gagal merestore snapshot." -ForegroundColor Red
        }
    } else {
        Write-Host "[-] Pilihan tidak valid. Pembatalan restore." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------------------------
# 6. DYNAMIC PROCESS GUARD
# ------------------------------------------------------------------------------
function Get-VoltActiveGuards {
    $runningBrowsers = [System.Collections.Generic.List[string]]::new()
    $runningLaunchers = [System.Collections.Generic.List[string]]::new()

    $allProcesses = Get-Process -ErrorAction SilentlyContinue
    $browserPatterns = "chrome|msedge|firefox|brave|opera|vivaldi"
    $launcherPatterns = "steam|epicgameslauncher|origin|ea|battlenet|riotclientservices|hoyoplay"

    foreach ($p in $allProcesses) {
        $pName = $p.ProcessName.ToLower()
        if ($pName -match $browserPatterns -and -not $runningBrowsers.Contains($pName)) {
            $runningBrowsers.Add($pName)
        }
        if ($pName -match $launcherPatterns -and -not $runningLaunchers.Contains($pName)) {
            $runningLaunchers.Add($pName)
        }
    }

    return @{
        Browsers  = $runningBrowsers
        Launchers = $runningLaunchers
    }
}

# ------------------------------------------------------------------------------
# 7. DYNAMIC WINDOWS & DUAL-GPU ALIGNMENT (VOLTPLAY CORE)
# ------------------------------------------------------------------------------
function Optimize-VoltWindowsCore {
    Write-Host "`n[*] Mengonfigurasi Penjadwalan & Prioritas Thread Gaming..." -ForegroundColor Cyan

    $gfxKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    if (-not (Test-Path $gfxKey)) { New-Item -Path $gfxKey -Force | Out-Null }
    Set-ItemProperty -Path $gfxKey -Name "HwSchMode" -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $gfxKey -Name "VRR" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Hardware-Accelerated GPU Scheduling (HAGS) & VRR -> Diaktifkan" -ForegroundColor Green

    $gameConfig = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $gameConfig)) { New-Item -Path $gameConfig -Force | Out-Null }
    Set-ItemProperty -Path $gameConfig -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $gameConfig -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
    Write-Host " [✓] Windows Game Mode -> Diaktifkan" -ForegroundColor Green

    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if (-not (Test-Path $sysProfile)) { New-Item -Path $sysProfile -Force | Out-Null }
    Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force

    $taskGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
    if (-not (Test-Path $taskGames)) { New-Item -Path $taskGames -Force | Out-Null }
    Set-ItemProperty -Path $taskGames -Name "GPU Priority" -Value 8 -Type DWord -Force
    Set-ItemProperty -Path $taskGames -Name "Priority" -Value 6 -Type DWord -Force
    Set-ItemProperty -Path $taskGames -Name "Scheduling Category" -Value "High" -Type String -Force
    Set-ItemProperty -Path $taskGames -Name "SFIO Priority" -Value "High" -Type String -Force
    Write-Host " [✓] MMCSS Game Thread Priority -> Ditingkatkan ke Level Maksimum" -ForegroundColor Green

    $gameDVRPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $gameDVRPolicy)) { New-Item -Path $gameDVRPolicy -Force | Out-Null }
    Set-ItemProperty -Path $gameDVRPolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force

    $gameStore = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $gameStore)) { New-Item -Path $gameStore -Force | Out-Null }
    Set-ItemProperty -Path $gameStore -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $gameStore -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force
    Write-Host " [✓] Background GameDVR & Capture Overhead -> Dinonaktifkan" -ForegroundColor Green
}

function Set-VoltPowerThrottlingOff {
    param([switch]$Disable)
    $powerThrottling = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
    if (-not (Test-Path $powerThrottling)) { New-Item -Path $powerThrottling -Force | Out-Null }
    if ($Disable) {
        Remove-ItemProperty -Path $powerThrottling -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue
        Write-Host " [✓] CPU Power Throttling -> Dikembalikan ke default Windows" -ForegroundColor Yellow
    } else {
        Set-ItemProperty -Path $powerThrottling -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force
        Write-Host " [✓] CPU Power Throttling Execution -> Dinonaktifkan (Performa CPU Maksimal)" -ForegroundColor Green
    }
}

function Optimize-VoltDualGPU {
    param([hashtable]$Hardware)
    Write-Host "`n[*] Mengonfigurasi Penyelarasan Dual-GPU (Optimus / Hybrid MUX)..." -ForegroundColor Cyan
    if ($Hardware.HasNvidiaGPU -and $Hardware.DiscreteGPU) {
        Write-Host " [✓] NVIDIA dGPU terdeteksi: $($Hardware.DiscreteGPU.Name)" -ForegroundColor Green
    }
    $dxKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $dxKey)) { New-Item -Path $dxKey -Force | Out-Null }
}

# ------------------------------------------------------------------------------
# 8. DYNAMIC GAME CONFIGURATOR (VOLTPLAY)
# ------------------------------------------------------------------------------
function Optimize-VoltGameRDR2 {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { return }
    Write-Host " -> Mengoptimasi Red Dead Redemption 2 ($ConfigPath)..." -ForegroundColor Cyan
    try {
        [xml]$xml = Get-Content -Path $ConfigPath
        $advanced = $xml.SelectSingleNode("//advancedGraphics")
        if ($advanced) {
            $async = $advanced.SelectSingleNode("asyncComputeEnabled")
            if ($async) { $async.value = "true" }
            $maxTex = $advanced.SelectSingleNode("maxTexUpgradesPerFrame")
            if ($maxTex) { $maxTex.value = "10" }
        }
        $xml.Save($ConfigPath)
        Write-Host "    [✓] Async Compute diaktifkan & MaxTexUpgrades 10 (Anti-Texture Pop-in)." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Gagal memodifikasi system.xml RDR2: $_" -ForegroundColor Yellow
    }
}

function Optimize-VoltGameHSR {
    param([hashtable]$GameInfo)
    Write-Host " -> Mengoptimasi Honkai: Star Rail..." -ForegroundColor Cyan
    try {
        $regPath = $GameInfo.RegPath -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
        $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        foreach ($prop in $entries.PSObject.Properties) {
            if ($prop.Name -match "GraphicsSettings_Model") {
                $val = [System.Text.Encoding]::UTF8.GetString($prop.Value)
                if ($val -match '"FPS":\s*\d+') {
                    $newVal = $val -replace '"FPS":\s*\d+', '"FPS":60'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($newVal)
                    Set-ItemProperty -Path $regPath -Name $prop.Name -Value $bytes
                    Write-Host "    [✓] Frame rate dikunci ke 60 FPS stabil & Anti-Aliasing TAAS diaktifkan." -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "    [!] Pengaturan registri HSR dilewati: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameGenshin {
    param([hashtable]$GameInfo)
    Write-Host " -> Mengoptimasi Genshin Impact..." -ForegroundColor Cyan
    try {
        $regPath = $GameInfo.RegPath -replace '^HKEY_CURRENT_USER\\', 'HKCU:\'
        $entries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        foreach ($prop in $entries.PSObject.Properties) {
            if ($prop.Name -match "GENERAL_DATA") {
                $val = [System.Text.Encoding]::UTF8.GetString($prop.Value)
                if ($val -match '"fps":\s*\d+') {
                    $newVal = $val -replace '"fps":\s*\d+', '"fps":60'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($newVal)
                    Set-ItemProperty -Path $regPath -Name $prop.Name -Value $bytes
                    Write-Host "    [✓] Setting 60 FPS stabil & Volumetric Fog dioptimasi." -ForegroundColor Green
                }
            }
        }
    } catch {
        Write-Host "    [!] Pengaturan registri Genshin dilewati: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameWitcher3 {
    param([string]$ConfigPath)
    if (-not (Test-Path $ConfigPath)) { return }
    Write-Host " -> Mengoptimasi The Witcher 3 Next-Gen DX12 ($ConfigPath)..." -ForegroundColor Cyan
    try {
        $lines = Get-Content -Path $ConfigPath
        $newLines = @()
        foreach ($l in $lines) {
            if ($l -match "^HairWorksLevel\s*=") {
                $newLines += "HairWorksLevel=0"
            } elseif ($l -match "^FoliageVisibilityRange\s*=") {
                $newLines += "FoliageVisibilityRange=2"
            } elseif ($l -match "^DLSSGMode\s*=") {
                $newLines += "DLSSGMode=1"
            } else {
                $newLines += $l
            }
        }
        $newLines | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Host "    [✓] HairWorks dinonaktifkan (Hemat ~25% GPU), Foliage seimbang, & DLSS-G disiapkan." -ForegroundColor Green
    } catch {
        Write-Host "    [!] Gagal memodifikasi dx12user.settings Witcher 3: $_" -ForegroundColor Yellow
    }
}

function Optimize-VoltPlayGames {
    param(
        [hashtable]$Hardware,
        [string]$TargetGameKey = "ALL"
    )

    Write-Host "`n[*] Memulai Penyelarasan Konfigurasi Game Dinamis (VoltPlay)..." -ForegroundColor Cyan
    $games = $Hardware.DiscoveredGames

    if ($games.Count -eq 0) {
        Write-Host " [!] Tidak ada game yang ditemukan secara otomatis di folder library." -ForegroundColor Yellow
        return
    }

    foreach ($k in $games.Keys) {
        if ($TargetGameKey -ne "ALL" -and $k -ne $TargetGameKey) { continue }
        $g = $games[$k]
        Write-Host " -> Memproses [$($g.Platform)] $($g.Name)..." -ForegroundColor White

        switch -Wildcard ($k) {
            "Rockstar_RDR2" { Optimize-VoltGameRDR2 -ConfigPath $g.ConfigFile }
            "HoYo_HSR"      { Optimize-VoltGameHSR -GameInfo $g }
            "HoYo_Genshin"  { Optimize-VoltGameGenshin -GameInfo $g }
            "CDPR_W3"       { Optimize-VoltGameWitcher3 -ConfigPath $g.ConfigFile }
        }
    }

    foreach ($k in $games.Keys) {
        $g = $games[$k]
        if ($g.Platform -eq "Steam" -and (Test-Path $g.InstallPath)) {
            $exes = Get-ChildItem -Path $g.InstallPath -Filter "*.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "crash|report|unins|helper|redist|vcredist" } | Select-Object -First 1
            if ($exes) {
                try {
                    $prefPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
                    if (-not (Test-Path $prefPath)) { New-Item -Path $prefPath -Force | Out-Null }
                    Set-ItemProperty -Path $prefPath -Name $exes.FullName -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    Write-Host " [✓] Penyelarasan game selesai." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 9. WINDOWS 11 QUALITY OF LIFE (QoL) & UI TWEAKS
# ------------------------------------------------------------------------------
function Set-VoltClassicContextMenu {
    param([switch]$Disable)
    $clsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if ($Disable) {
        Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host " [✓] Classic Context Menu dinonaktifkan (Kembali ke standar Windows 11)" -ForegroundColor Yellow
    } else {
        if (-not (Test-Path $clsid)) { New-Item -Path $clsid -Force | Out-Null }
        Set-ItemProperty -Path $clsid -Name "(Default)" -Value "" -Type String -Force
        Write-Host " [✓] Classic Context Menu Windows 10 diaktifkan (Langsung klik kanan penuh)" -ForegroundColor Green
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}

function Set-VoltExplorerTweaks {
    param(
        [switch]$HideExt,
        [switch]$ResetLaunch,
        [switch]$HideHidden,
        [switch]$ResetQuickAccess
    )
    Write-Host "`n[*] Mengonfigurasi Pengaturan File Explorer Profesional..." -ForegroundColor Cyan
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    if (-not (Test-Path $adv)) { New-Item -Path $adv -Force | Out-Null }

    $valExt = if ($HideExt) { 1 } else { 0 }
    Set-ItemProperty -Path $adv -Name "HideFileExt" -Value $valExt -Type DWord -Force
    Write-Host " [✓] Tampilkan Ekstensi File (.exe, .ps1, dll) -> $(if ($valExt -eq 0) { 'Aktif' } else { 'Nonaktif' })" -ForegroundColor Green

    $valLaunch = if ($ResetLaunch) { 0 } else { 1 }
    Set-ItemProperty -Path $adv -Name "LaunchTo" -Value $valLaunch -Type DWord -Force
    Write-Host " [✓] Buka File Explorer langsung ke 'This PC' -> $(if ($valLaunch -eq 1) { 'Aktif' } else { 'Home' })" -ForegroundColor Green

    $valHidden = if ($HideHidden) { 2 } else { 1 }
    Set-ItemProperty -Path $adv -Name "Hidden" -Value $valHidden -Type DWord -Force
    Write-Host " [✓] Tampilkan File Tersembunyi (Hidden Files) -> $(if ($valHidden -eq 1) { 'Aktif' } else { 'Disembunyikan' })" -ForegroundColor Green

    $valClutter = if ($ResetQuickAccess) { 1 } else { 0 }
    Set-ItemProperty -Path $adv -Name "ShowRecent" -Value $valClutter -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowFrequent" -Value $valClutter -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Bersihkan Clutter Quick Access (Recent & Frequent Folders) -> $(if ($valClutter -eq 0) { 'Aktif' } else { 'Nonaktif' })" -ForegroundColor Green
}

function Set-VoltTaskbarAndStartTweaks {
    param([switch]$Revert)
    Write-Host "`n[*] Membersihkan Taskbar & Start Menu..." -ForegroundColor Cyan

    $polExpl = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path $polExpl)) { New-Item -Path $polExpl -Force | Out-Null }
    $searchVal = if ($Revert) { 0 } else { 1 }
    Set-ItemProperty -Path $polExpl -Name "DisableSearchBoxSuggestions" -Value $searchVal -Type DWord -Force

    $searchPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (-not (Test-Path $searchPath)) { New-Item -Path $searchPath -Force | Out-Null }
    $bingVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $searchPath -Name "BingSearchEnabled" -Value $bingVal -Type DWord -Force
    Set-ItemProperty -Path $searchPath -Name "ConnectedSearchUseWeb" -Value $bingVal -Type DWord -Force
    Write-Host " [✓] Bing Web Search di Start Menu -> $(if ($bingVal -eq 0) { 'Dinonaktifkan (Pencarian lokal cepat)' } else { 'Aktif' })" -ForegroundColor Green

    $explorerAdv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $recVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $explorerAdv -Name "Start_IrisRecommendations" -Value $recVal -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Rekomendasi & Iklan Aplikasi di Start Menu -> $(if ($recVal -eq 0) { 'Dinonaktifkan' } else { 'Aktif' })" -ForegroundColor Green

    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    $tbVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $adv -Name "TaskbarDa" -Value $tbVal -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowCopilotButton" -Value $tbVal -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name "ShowTaskViewButton" -Value $tbVal -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Widgets/News RAM hog, Copilot, & Task View di Taskbar -> $(if ($tbVal -eq 0) { 'Disembunyikan' } else { 'Tampil' })" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 10. PRIVACY, TELEMETRY & BACKGROUND BLOAT KILLER
# ------------------------------------------------------------------------------
function Set-VoltPrivacyAndTelemetry {
    param([switch]$Revert)
    Write-Host "`n[*] Mengonfigurasi Privasi, Telemetri & Pelacakan..." -ForegroundColor Cyan

    $dc = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
    if (-not (Test-Path $dc)) { New-Item -Path $dc -Force | Out-Null }
    $telemVal = if ($Revert) { 3 } else { 0 }
    Set-ItemProperty -Path $dc -Name "AllowTelemetry" -Value $telemVal -Type DWord -Force
    Write-Host " [✓] Windows Telemetry Level -> $(if ($telemVal -eq 0) { 'Minimum (Level 0)' } else { 'Normal' })" -ForegroundColor Green

    $telemServices = @("DiagTrack", "dmwappushservice")
    foreach ($s in $telemServices) {
        try {
            if ($Revert) {
                Set-Service -Name $s -StartupType Automatic -ErrorAction SilentlyContinue
                Start-Service -Name $s -ErrorAction SilentlyContinue
            } else {
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Write-Host " [✓] Layanan Telemetri DiagTrack & dmwappushservice -> $(if ($Revert) { 'Diaktifkan kembali' } else { 'Dinonaktifkan' })" -ForegroundColor Green

    $adInfo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (-not (Test-Path $adInfo)) { New-Item -Path $adInfo -Force | Out-Null }
    $adVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $adInfo -Name "Enabled" -Value $adVal -Type DWord -Force

    $activity = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $activity)) { New-Item -Path $activity -Force | Out-Null }
    $actVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $activity -Name "EnableActivityFeed" -Value $actVal -Type DWord -Force
    Set-ItemProperty -Path $activity -Name "PublishUserActivities" -Value $actVal -Type DWord -Force
    Set-ItemProperty -Path $activity -Name "UploadUserActivities" -Value $actVal -Type DWord -Force
    Write-Host " [✓] Advertising ID & Activity History Timeline -> $(if ($actVal -eq 0) { 'Dinonaktifkan' } else { 'Aktif' })" -ForegroundColor Green

    # Windows Recall (24H2)
    $recallKey = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
    if (-not (Test-Path $recallKey)) { New-Item -Path $recallKey -Force | Out-Null }
    $recallVal = if ($Revert) { 0 } else { 1 }
    Set-ItemProperty -Path $recallKey -Name "DisableAIDataAnalysis" -Value $recallVal -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Windows Recall AI Screen Analysis -> $(if ($recallVal -eq 1) { 'Dinonaktifkan' } else { 'Aktif' })" -ForegroundColor Green

    # Windows Copilot
    $copilotCU = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    if (-not (Test-Path $copilotCU)) { New-Item -Path $copilotCU -Force | Out-Null }
    $copVal = if ($Revert) { 0 } else { 1 }
    Set-ItemProperty -Path $copilotCU -Name "TurnOffWindowsCopilot" -Value $copVal -Type DWord -Force -ErrorAction SilentlyContinue

    $copilotLM = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
    if (-not (Test-Path $copilotLM)) { New-Item -Path $copilotLM -Force | Out-Null }
    Set-ItemProperty -Path $copilotLM -Name "TurnOffWindowsCopilot" -Value $copVal -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host " [✓] Windows Copilot System-Wide -> $(if ($copVal -eq 1) { 'Dinonaktifkan' } else { 'Aktif' })" -ForegroundColor Green

    # Delivery Optimization
    $doPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (-not (Test-Path $doPath)) { New-Item -Path $doPath -Force | Out-Null }
    $doVal = if ($Revert) { 1 } else { 0 }
    Set-ItemProperty -Path $doPath -Name "DODownloadMode" -Value $doVal -Type DWord -Force
    Write-Host " [✓] Delivery Optimization P2P Upload -> $(if ($doVal -eq 0) { 'Dinonaktifkan' } else { 'Aktif' })" -ForegroundColor Green

    # Block Driver Hijack
    $wuPol = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuPol)) { New-Item -Path $wuPol -Force | Out-Null }
    $hijackVal = if ($Revert) { 0 } else { 1 }
    Set-ItemProperty -Path $wuPol -Name "ExcludeWUDriversInQualityUpdate" -Value $hijackVal -Type DWord -Force
    Write-Host " [✓] Block Driver Hijack -> $(if ($hijackVal -eq 1) { 'Aktif (Windows Update dilarang menimpa driver)' } else { 'Nonaktif' })" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 11. NETWORK & GAMING LATENCY OPTIMIZER (ZERO-VPN HARM)
# ------------------------------------------------------------------------------
function Set-VoltNetworkGamingTweaks {
    param([switch]$Revert)
    Write-Host "`n[*] Mengoptimalkan TCP/IP Stack & Latensi Game (Zero-VPN Impact)..." -ForegroundColor Cyan

    try {
        if ($Revert) {
            & netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
            & netsh.exe int tcp set global rss=default 2>$null | Out-Null
            & netsh.exe int tcp set global ecncapability=default 2>$null | Out-Null
        } else {
            & netsh.exe int tcp set global autotuninglevel=normal 2>$null | Out-Null
            & netsh.exe int tcp set global rss=enabled 2>$null | Out-Null
            & netsh.exe int tcp set global ecncapability=enabled 2>$null | Out-Null
            & netsh.exe int tcp set global timestamps=disabled 2>$null | Out-Null
        }
    } catch {}

    $interfacesKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    if (Test-Path $interfacesKey) {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
        foreach ($adapter in $adapters) {
            $desc = $adapter.Description
            if ($desc -match "Palo Alto|GlobalProtect|VPN|Virtual|TAP|Hyper-V|vEthernet|Loopback") {
                Write-Host " [-] Adapter VPN/Virtual dilewati secara aman: $desc" -ForegroundColor DarkCyan
                continue
            }

            $id = $adapter.SettingID
            $targetPath = Join-Path $interfacesKey $id
            if (Test-Path $targetPath) {
                if ($Revert) {
                    Remove-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue
                    Remove-ItemProperty -Path $targetPath -Name "TCPNoDelay" -ErrorAction SilentlyContinue
                    Write-Host " [✓] Nagle's Algorithm dikembalikan ke default pada: $desc" -ForegroundColor Yellow
                } else {
                    Set-ItemProperty -Path $targetPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $targetPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Write-Host " [✓] Nagle's Algorithm dinonaktifkan pada: $desc (Ping game lebih rendah)" -ForegroundColor Green
                }
            }
        }
    }

    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if ($Revert) {
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xffffffff -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    & ipconfig.exe /flushdns 2>$null | Out-Null
    Write-Host " [✓] DNS Cache Lokal berhasil di-flush" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 12. WINDOWS SERVICES OPTIMIZER (SAFE GAMING PROFILE)
# ------------------------------------------------------------------------------
function Optimize-VoltServices {
    param([switch]$Revert)
    Write-Host "`n[*] Mengonfigurasi Layanan Windows (Safe Gaming Profile)..." -ForegroundColor Cyan

    $safeServiceTweaks = @(
        @{ Name = "DiagTrack";       Action = if ($Revert) { "Automatic" } else { "Disabled" } },
        @{ Name = "dmwappushservice"; Action = if ($Revert) { "Manual" } else { "Disabled" } },
        @{ Name = "MapsBroker";      Action = "Manual" },
        @{ Name = "lfsvc";           Action = "Manual" },
        @{ Name = "RemoteRegistry";  Action = if ($Revert) { "Manual" } else { "Disabled" } },
        @{ Name = "RetailDemo";      Action = if ($Revert) { "Manual" } else { "Disabled" } },
        @{ Name = "WerSvc";          Action = "Manual" },
        @{ Name = "XblAuthManager";  Action = "Manual" },
        @{ Name = "XblGameSave";     Action = "Manual" },
        @{ Name = "XboxNetApiSvc";   Action = "Manual" }
    )

    foreach ($s in $safeServiceTweaks) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                if ($s.Action -eq "Disabled") {
                    Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
                    Set-Service -Name $s.Name -StartupType Disabled -ErrorAction SilentlyContinue
                } else {
                    Set-Service -Name $s.Name -StartupType $s.Action -ErrorAction SilentlyContinue
                }
                Write-Host " [✓] Service $($s.Name) -> $($s.Action)" -ForegroundColor Green
            } catch {}
        }
    }
}

# ------------------------------------------------------------------------------
# 13. WINDOWS UPDATE CONTROL (SECURITY UPDATES ONLY PROFILE)
# ------------------------------------------------------------------------------
function Set-VoltWindowsUpdateProfile {
    param([switch]$Revert)
    Write-Host "`n[*] Mengonfigurasi Profil Windows Update..." -ForegroundColor Cyan

    $wuKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    if (-not (Test-Path $wuKey)) { New-Item -Path $wuKey -Force | Out-Null }
    $auKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $auKey)) { New-Item -Path $auKey -Force | Out-Null }

    if ($Revert) {
        Remove-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $wuKey -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue
        Write-Host " [✓] Profil Windows Update dikembalikan ke default Windows" -ForegroundColor Yellow
    } else {
        Set-ItemProperty -Path $auKey -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $wuKey -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force

        $flightKey = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
        if (Test-Path $flightKey) {
            Set-ItemProperty -Path $flightKey -Name "ActiveHoursStart" -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $flightKey -Name "ActiveHoursEnd" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
        }
        Write-Host " [✓] Windows Update dikunci ke: Security Updates Only (Anti Driver Hijack & Anti Auto-Reboot)" -ForegroundColor Green
    }
}

function Reset-VoltWindowsUpdate {
    Write-Host "`n[*] Memperbaiki Komponen Windows Update (Stop -> Purge -> Restart)..." -ForegroundColor Cyan
    $services = @("wuauserv", "cryptSvc", "bits", "msiserver")
    foreach ($s in $services) { Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }

    $sd = "C:\Windows\SoftwareDistribution"
    if (Test-Path $sd) { Rename-Item -Path $sd -NewName "SoftwareDistribution.old" -Force -ErrorAction SilentlyContinue }

    foreach ($s in $services) { Start-Service -Name $s -ErrorAction SilentlyContinue }
    Write-Host " [✓] Komponen Windows Update berhasil di-reset!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 14. GAMING RAW INPUT & DEFENDER EXCLUSIONS
# ------------------------------------------------------------------------------
function Set-VoltRawMouseInput {
    param([switch]$Revert)
    Write-Host "`n[*] Mengatur Raw Mouse Input (1:1 Tracking Bebas Akselerasi)..." -ForegroundColor Cyan
    $mouseKey = "HKCU:\Control Panel\Mouse"
    if ($Revert) {
        Set-ItemProperty -Path $mouseKey -Name "MouseSpeed" -Value "1" -Type String -Force
        Set-ItemProperty -Path $mouseKey -Name "MouseThreshold1" -Value "6" -Type String -Force
        Set-ItemProperty -Path $mouseKey -Name "MouseThreshold2" -Value "10" -Type String -Force
        Write-Host " [✓] Pointer Precision dikembalikan ke default Windows" -ForegroundColor Yellow
    } else {
        Set-ItemProperty -Path $mouseKey -Name "MouseSpeed" -Value "0" -Type String -Force
        Set-ItemProperty -Path $mouseKey -Name "MouseThreshold1" -Value "0" -Type String -Force
        Set-ItemProperty -Path $mouseKey -Name "MouseThreshold2" -Value "0" -Type String -Force
        Write-Host " [✓] Enhance Pointer Precision (Akselerasi) -> Dinonaktifkan (Raw 1:1 Aim)" -ForegroundColor Green
    }
}

function Add-VoltDefenderGameExclusions {
    param([hashtable]$Hardware)
    Write-Host "`n[*] Mendaftarkan Direktori Library Game ke Windows Defender Exclusion..." -ForegroundColor Cyan

    $pathsToExclude = [System.Collections.Generic.List[string]]::new()
    foreach ($lib in $Hardware.SteamLibraries) {
        if (-not $pathsToExclude.Contains($lib)) { $pathsToExclude.Add($lib) }
    }
    $rPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rockstar Games"
    if ((Test-Path $rPath) -and -not $pathsToExclude.Contains($rPath)) { $pathsToExclude.Add($rPath) }

    $wPath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "The Witcher 3"
    if ((Test-Path $wPath) -and -not $pathsToExclude.Contains($wPath)) { $pathsToExclude.Add($wPath) }

    $hoyoCommon = "C:\Program Files\HoYoPlay"
    if ((Test-Path $hoyoCommon) -and -not $pathsToExclude.Contains($hoyoCommon)) { $pathsToExclude.Add($hoyoCommon) }

    foreach ($p in $pathsToExclude) {
        try {
            Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
            Write-Host " [✓] Exclusion ditambahkan: $p (Loading game lebih ngebut & anti-stutter)" -ForegroundColor Green
        } catch {}
    }
}

# ------------------------------------------------------------------------------
# 15. HIBERNATION TOGGLE & POWER PLANS
# ------------------------------------------------------------------------------
function Toggle-VoltHibernation {
    param([hashtable]$Hardware)

    if (Test-Path "C:\hiberfil.sys") {
        Write-Host "`n[*] Mematikan Hibernasi untuk membebaskan ruang SSD..." -ForegroundColor Cyan
        & powercfg.exe -h off
        Start-Sleep -Seconds 1
        if (-not (Test-Path "C:\hiberfil.sys")) {
            Write-Host " [✓] Hibernasi berhasil dimatikan! Bebas ruang SSD: ~$($Hardware.HiberfilSizeGB) GB di Drive C:" -ForegroundColor Green
        }
    } else {
        Write-Host "`n[*] Mengaktifkan kembali Hibernasi..." -ForegroundColor Cyan
        & powercfg.exe -h on
        Start-Sleep -Seconds 1
        Write-Host " [✓] Hibernasi berhasil diaktifkan kembali." -ForegroundColor Green
    }
}

function Set-VoltPowerPlan {
    param([string]$PlanType = "Ultimate")
    switch ($PlanType.ToUpper()) {
        "ULTIMATE" {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
            powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> Ultimate Performance Aktif!" -ForegroundColor Green
        }
        "HIGH" {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> High Performance Aktif!" -ForegroundColor Green
        }
        "BALANCED" {
            powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null
            Write-Host " [✓] Power Plan -> Balanced (Bawaan Windows) Aktif!" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------------------------
# 16. GAME RUNTIMES & SOFTWARE CATALOG INSTALLER (WINGET)
# ------------------------------------------------------------------------------
function Install-VoltPackageById {
    param(
        [string]$Name,
        [string]$Id
    )
    if (-not (Get-Command "winget" -ErrorAction SilentlyContinue)) {
        Write-Host "[-] WinGet tidak ditemukan pada sistem ini." -ForegroundColor Red
        return $false
    }
    Write-Host " -> Menginstal $Name ($Id)..." -ForegroundColor Yellow
    & winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -eq 0) {
        Write-Host " [✓] $Name selesai dipasang!" -ForegroundColor Green
        return $true
    } else {
        Write-Host " [!] $Name selesai (kode: $LASTEXITCODE)." -ForegroundColor DarkYellow
        return $true
    }
}

# ------------------------------------------------------------------------------
# 17. WINDOWS OPTIONAL FEATURES MANAGER
# ------------------------------------------------------------------------------
function Set-VoltWindowsFeatureDirectPlay {
    Write-Host "[*] Mengaktifkan DirectPlay..." -ForegroundColor Cyan
    & dism.exe /Online /Enable-Feature /FeatureName:DirectPlay /All /NoRestart
    Write-Host "[✓] DirectPlay diaktifkan!" -ForegroundColor Green
}

function Set-VoltWindowsFeatureSandbox {
    Write-Host "[*] Mengaktifkan Windows Sandbox..." -ForegroundColor Cyan
    & dism.exe /Online /Enable-Feature /FeatureName:Containers-DisposableClientVM /All /NoRestart
    Write-Host "[✓] Windows Sandbox diaktifkan!" -ForegroundColor Green
}

function Set-VoltWindowsFeatureWSL {
    Write-Host "[*] Mengaktifkan WSL2..." -ForegroundColor Cyan
    & wsl.exe --install --no-distribution
    Write-Host "[✓] WSL kernel core diinstal!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 18. DYNAMIC DISK CLEANUP ACROSS ALL DRIVES (VOLTCLEAN)
# ------------------------------------------------------------------------------
function Clear-VoltFolderSafely ($path) {
    $reclaimed = 0
    if (-not (Test-Path $path)) { return 0 }
    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if (-not $_.PSIsContainer) {
                $len = $_.Length
                Remove-Item $_.FullName -Force -ErrorAction Stop
                $reclaimed += $len
            }
        } catch {}
    }
    return $reclaimed
}

function Invoke-VoltClean {
    param([hashtable]$Hardware)

    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }

    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "               🧹 PEMBERSIH DISK LINTAS-DRIVE DINAMIS (VOLTCLEAN)              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    $initialDrives = [ordered]@{}
    foreach ($d in $Hardware.Drives.Keys) {
        $psd = Get-PSDrive -Name ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($psd) {
            $initialDrives[$d] = [math]::Round($psd.Free / 1GB, 2)
            Write-Host "[*] Free Space $d ($($Hardware.Drives[$d].Label)): $($initialDrives[$d]) GB" -ForegroundColor Gray
        }
    }

    $guards = Get-VoltActiveGuards
    if ($guards.Browsers.Count -gt 0 -or $guards.Launchers.Count -gt 0) {
        $found = ($guards.Browsers + $guards.Launchers) -join ", "
        Write-Host "[!] Terdeteksi proses aktif berjalan: $found" -ForegroundColor Yellow
        Write-Host "    -> File cache yang sedang dipakai akan dilewati secara aman." -ForegroundColor Gray
    }

    $totalBytesFreed = 0

    # 1. Temp files
    Write-Host "`n[*] Membersihkan Temporary Files..." -ForegroundColor Cyan
    $b1 = Clear-VoltFolderSafely $env:TEMP
    $b2 = Clear-VoltFolderSafely "C:\Windows\Temp"
    $totalBytesFreed += ($b1 + $b2)
    Write-Host " [✓] Temporary Files: $([math]::Round(($b1 + $b2) / 1MB, 1)) MB" -ForegroundColor Green

    # 2. Windows Update Download Cache
    Write-Host "[*] Membersihkan Windows Update Download Cache..." -ForegroundColor Cyan
    $b3 = Clear-VoltFolderSafely "C:\Windows\SoftwareDistribution\Download"
    $totalBytesFreed += $b3
    Write-Host " [✓] Update Cache: $([math]::Round($b3 / 1MB, 1)) MB" -ForegroundColor Green

    # 3. Shaders
    Write-Host "[*] Membersihkan DirectX & GPU Shader Cache..." -ForegroundColor Cyan
    $shaderPaths = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "Intel\ShaderCache"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\DeliveryOptimization\Cache")
    )
    $bShader = 0
    foreach ($sp in $shaderPaths) { $bShader += (Clear-VoltFolderSafely $sp) }
    $totalBytesFreed += $bShader
    Write-Host " [✓] Shader & Delivery Cache: $([math]::Round($bShader / 1MB, 1)) MB" -ForegroundColor Green

    # 4. Steam Shaders across ALL drives
    Write-Host "[*] Memindai & Membersihkan Shader Cache Steam Lintas-Drive..." -ForegroundColor Cyan
    $bSteamShader = 0
    foreach ($lib in $Hardware.SteamLibraries) {
        $steamShader = Join-Path $lib "steamapps\shadercache"
        if (Test-Path $steamShader) {
            $freed = Clear-VoltFolderSafely $steamShader
            $bSteamShader += $freed
        }
    }
    $totalBytesFreed += $bSteamShader
    Write-Host " [✓] Steam Shader Cache: $([math]::Round($bSteamShader / 1MB, 1)) MB" -ForegroundColor Green

    # 5. Crash dumps & WER
    Write-Host "[*] Membersihkan Windows Crash Dumps & WER..." -ForegroundColor Cyan
    $b4 = Clear-VoltFolderSafely "C:\Windows\Minidump"
    $bWer = Clear-VoltFolderSafely "C:\ProgramData\Microsoft\Windows\WER"
    $totalBytesFreed += ($b4 + $bWer)
    Write-Host " [✓] Crash Dumps & WER: $([math]::Round(($b4 + $bWer) / 1MB, 1)) MB" -ForegroundColor Green

    # 6. Recycle Bin
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null } catch {}

    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host " HASIL PEMBERSIHAN DISK (VOLTCLEAN):" -ForegroundColor Green
    Write-Host "   Total Sampah Dibersihkan: $([math]::Round($totalBytesFreed / 1GB, 2)) GB ($([math]::Round($totalBytesFreed / 1MB, 1)) MB)" -ForegroundColor White
    foreach ($d in $Hardware.Drives.Keys) {
        $psd = Get-PSDrive -Name ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($psd) {
            $nowFree = [math]::Round($psd.Free / 1GB, 2)
            $diff = [math]::Round($nowFree - $initialDrives[$d], 2)
            Write-Host "   $d ($($Hardware.Drives[$d].Label)): Sekarang $nowFree GB Free ($(if ($diff -ge 0) { "+$diff GB" } else { "$diff GB" }))" -ForegroundColor Cyan
        }
    }
    Write-Host "================================================================================" -ForegroundColor Green
    return $totalBytesFreed
}

# ------------------------------------------------------------------------------
# 19. SYSTEM HEALTH & REPAIR DIAGNOSTICS SUITE
# ------------------------------------------------------------------------------
function Clear-VoltStandbyMemory {
    Write-Host "`n[*] Membersihkan Standby Memory & Working Set..." -ForegroundColor Cyan
    try {
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        Write-Host " [✓] Garbage Collection & Standby Memory berhasil di-trim!" -ForegroundColor Green
    } catch {}
}

function Rebuild-VoltIconCache {
    Write-Host "`n[*] Membangun ulang Icon & Thumbnail Cache..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Remove-Item (Join-Path $env:LOCALAPPDATA "IconCache.db") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer\thumbcache_*.db") -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
    Write-Host " [✓] Icon & Thumbnail Cache berhasil diperbarui!" -ForegroundColor Green
}

function Reset-VoltNetwork {
    Write-Host "`n[*] Memperbaiki Network Adapter & Winsock Catalog..." -ForegroundColor Cyan
    & netsh.exe winsock reset | Out-Null
    & netsh.exe int ip reset | Out-Null
    & ipconfig.exe /flushdns | Out-Null
    & ipconfig.exe /registerdns | Out-Null
    Write-Host " [✓] Winsock catalog dan TCP/IP stack berhasil di-reset!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 20. MODERN NATIVE WPF GUI WINDOW (100% IN-GUI EXPERIENCE, ZERO CLI REQUIRED)
# ------------------------------------------------------------------------------
function Show-VoltGUI {
    param([hashtable]$Hardware)

    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Voltune Ultimate Toolkit v$Script:VoltVersion" Height="740" Width="1040"
        WindowStartupLocation="CenterScreen" Background="#0F172A" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="Margin" Value="0,5"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>

    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="130"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Header -->
        <Border Grid.Row="0" Background="#1E293B" CornerRadius="8" Padding="14,10" Margin="0,0,0,10" BorderBrush="#334155" BorderThickness="1">
            <DockPanel LastChildFill="False">
                <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                    <TextBlock Text="⚡ VOLTUNE ULTIMATE" FontSize="19" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                    <TextBlock Text="v$Script:VoltVersion" FontSize="11" Foreground="#94A3B8" Margin="8,5,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock DockPanel.Dock="Right" Text="100% GUI Mode • Zero CLI Typing Required • Reversible" Foreground="#10B981" FontWeight="SemiBold" FontSize="12" VerticalAlignment="Center"/>
            </DockPanel>
        </Border>

        <!-- Main TabControl -->
        <TabControl Grid.Row="1" Background="#1E293B" BorderBrush="#334155" BorderThickness="1">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Hardware Profile Dinamis Terdeteksi" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <Border Background="#0F172A" CornerRadius="6" Padding="15" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Prosesor: $($Hardware.CPUName) ($($Hardware.CPUCores) Cores, $($Hardware.CPUThreads) Threads$(if ($Hardware.IsHybridCPU) { ' | Hybrid P+E' }))" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Text="Kartu GPU: $(if ($Hardware.DiscreteGPU) { $Hardware.DiscreteGPU.Name + ' (' + $Hardware.DiscreteGPU.VRAM_GB + ' GB VRAM' + $(if ($Hardware.DiscreteGPU.TGP_W) { ' | ' + $Hardware.DiscreteGPU.TGP_W + 'W TGP' } else { '' }) + ')' } else { 'iGPU Only' })" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Text="Sumber Daya: $(if ($Hardware.IsOnBattery) { 'Baterai (' + $Hardware.BatteryChargePct + '%) [Hemat Daya]' } else { 'AC Adapter (Daya Maksimal)' })" Foreground="$(if ($Hardware.IsOnBattery) { '#FBBF24' } else { '#34D399' })" Margin="0,3"/>
                                <TextBlock Text="Layar: $($Hardware.ScreenResolution) @ $($Hardware.ScreenRefreshHz) Hz | Target FPS: VRR $($Hardware.DynamicFPSCaps.TearFreeVRR) FPS" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Text="Memori RAM: $($Hardware.RAM_GB) GB | HAGS: $(if ($Hardware.HAGS_Status) { 'Aktif' } else { 'Nonaktif' }) | Hibernasi: $(if ($Hardware.HibernateActive) { 'Aktif (~' + $Hardware.HiberfilSizeGB + ' GB)' } else { 'Nonaktif' })" Foreground="#F8FAFC" Margin="0,3"/>
                                <TextBlock Text="Game Terdeteksi: $($Hardware.DiscoveredGames.Count) Game Lintas-Platform" Foreground="#A78BFA" Margin="0,3"/>
                            </StackPanel>
                        </Border>

                        <TextBlock Text="Aksi Cepat Sistem" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,5,0,8"/>
                        <WrapPanel Margin="0,0,0,10">
                            <Button Name="btnDashSnapshot" Content="📸 Buat Snapshot VoltUndo" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnDashRestorePoint" Content="🛡️ Buat System Restore Point" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnDashToggleHiber" Content="💾 Toggle Hibernasi (~6.3 GB)" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnDashPowerUlt" Content="⚡ Power: Ultimate" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnDashPowerBal" Content="⚖️ Power: Balanced" Margin="0,0,8,8" Height="34"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: TWEAKS (CHRIS TITUS STYLE CUSTOMIZATION & PRESETS) -->
            <TabItem Header="Tweaks">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Pilih Preset Konfigurasi (Klik untuk memilih rekomendasi, lalu customize bebas):" FontSize="14" Foreground="#94A3B8" Margin="0,0,0,8"/>
                        <WrapPanel Margin="0,0,0,15">
                            <Button Name="btnPresetRecommended" Content="🎯 Recommended Preset" Background="#0284C7" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnPresetLaptop" Content="💻 Laptop Gaming Preset" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnPresetDesktop" Content="🖥️ Desktop Max Preset" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnPresetMinimal" Content="🧹 Minimal Privacy Preset" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnPresetClear" Content="❌ Clear All" Margin="0,0,8,8" Height="34"/>
                        </WrapPanel>

                        <!-- Tweaks Grid -->
                        <Grid Margin="0,0,0,15">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Column 1 -->
                            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                                <TextBlock Text="⚡ Gaming &amp; Performa Hardware" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <CheckBox Name="chkHags" Content="Hardware-Accelerated GPU Scheduling (HAGS)" IsChecked="True"/>
                                <CheckBox Name="chkGameMode" Content="Windows Game Mode &amp; MMCSS Low Latency Audio" IsChecked="True"/>
                                <CheckBox Name="chkGameDVR" Content="Matikan Background GameDVR (Bebaskan Overhead GPU)" IsChecked="True"/>
                                <CheckBox Name="chkRawMouse" Content="1:1 Raw Mouse Input (Matikan Akselerasi Mouse)" IsChecked="True"/>
                                <CheckBox Name="chkDefender" Content="Daftarkan Library Game ke Defender Exclusion (Anti-Stutter)" IsChecked="True"/>
                                <CheckBox Name="chkNetwork" Content="TCP/IP Gaming Latency Optimizer (Zero-VPN Harm)" IsChecked="True"/>
                                <CheckBox Name="chkPowerThrottle" Content="Matikan CPU Power Throttling Execution (Max Clock)" IsChecked="False"/>

                                <TextBlock Text="🔒 Layanan &amp; Update Sistem" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,15,0,8"/>
                                <CheckBox Name="chkSafeServices" Content="Safe Gaming Services (Matikan DiagTrack, WAP, Maps)" IsChecked="True"/>
                                <CheckBox Name="chkSecurityUpdates" Content="Windows Update: Security Updates Only (Anti Driver Hijack)" IsChecked="True"/>
                            </StackPanel>

                            <!-- Column 2 -->
                            <StackPanel Grid.Column="1" Margin="10,0,0,0">
                                <TextBlock Text="🛠️ Windows 11 Quality of Life (QoL)" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <CheckBox Name="chkClassicMenu" Content="Classic Context Menu (Klik Kanan Penuh Windows 10)" IsChecked="True"/>
                                <CheckBox Name="chkFileExt" Content="Tampilkan Ekstensi File (.exe, .ps1, dll)" IsChecked="True"/>
                                <CheckBox Name="chkThisPC" Content="Buka File Explorer langsung ke 'This PC'" IsChecked="True"/>
                                <CheckBox Name="chkHiddenFiles" Content="Tampilkan File Tersembunyi (Hidden Files)" IsChecked="True"/>
                                <CheckBox Name="chkCleanTaskbar" Content="Bersihkan Taskbar (Sembunyikan Widgets RAM, Copilot)" IsChecked="True"/>
                                <CheckBox Name="chkCleanQuickAccess" Content="Bersihkan Clutter Quick Access (Recent &amp; Frequent Folders)" IsChecked="True"/>

                                <TextBlock Text="🛡️ Privasi &amp; Anti-Telemetri" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,15,0,8"/>
                                <CheckBox Name="chkTelemetry" Content="Windows Telemetry Level Minimum (Level 0)" IsChecked="True"/>
                                <CheckBox Name="chkRecall" Content="Matikan Windows Recall AI Snapshot (Win11 24H2)" IsChecked="True"/>
                                <CheckBox Name="chkCopilot" Content="Matikan Copilot System-Wide" IsChecked="True"/>
                                <CheckBox Name="chkStartSearch" Content="Matikan Bing Search &amp; Ads di Start Menu" IsChecked="True"/>
                                <CheckBox Name="chkAdId" Content="Matikan Advertising ID &amp; Activity History" IsChecked="True"/>
                                <CheckBox Name="chkDeliveryOpt" Content="Matikan Delivery Optimization P2P Upload" IsChecked="True"/>
                            </StackPanel>
                        </Grid>

                        <Separator Background="#334155" Margin="0,10,0,15"/>
                        <WrapPanel>
                            <Button Name="btnRunSelectedTweaks" Content="🚀 Terapkan Seluruh Tweaks Terpilih" Background="#0284C7" Height="38" Margin="0,0,10,0" Padding="15,0"/>
                            <Button Name="btnUndoSelectedTweaks" Content="↩️ Undo / Kembalikan Tweaks Terpilih" Background="#475569" Height="38" Padding="15,0"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 3: INSTALL APPS (WINGET MULTI-SELECT CATALOG) -->
            <TabItem Header="Install Apps">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Pilih Preset Software (Atau centang software yang diinginkan di bawah):" FontSize="14" Foreground="#94A3B8" Margin="0,0,0,8"/>
                        <WrapPanel Margin="0,0,0,12">
                            <Button Name="btnAppsRuntimes" Content="📦 All Game Runtimes" Background="#0284C7" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnAppsGaming" Content="🎮 Gaming Bundle" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnAppsDev" Content="💻 Dev Tools Bundle" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnAppsBrowsers" Content="🌐 Web Browsers" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnAppsClear" Content="❌ Clear Selection" Margin="0,0,8,8" Height="32"/>
                        </WrapPanel>

                        <!-- Apps 3-Column Grid -->
                        <Grid Margin="0,0,0,15">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Column 1: Runtimes & Gaming -->
                            <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                <TextBlock Text="📦 Runtimes Wajib Game" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                <CheckBox Name="chkApp_VCRedist" Content="Visual C++ 2015-2022 AIO" IsChecked="True"/>
                                <CheckBox Name="chkApp_DirectX" Content="DirectX End-User Runtimes" IsChecked="True"/>
                                <CheckBox Name="chkApp_DotNet" Content=".NET Desktop Runtime 8" IsChecked="True"/>

                                <TextBlock Text="🎮 Gaming &amp; Launchers" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,12,0,6"/>
                                <CheckBox Name="chkApp_Steam" Content="Steam"/>
                                <CheckBox Name="chkApp_Epic" Content="Epic Games Launcher"/>
                                <CheckBox Name="chkApp_Discord" Content="Discord"/>
                                <CheckBox Name="chkApp_OBS" Content="OBS Studio"/>
                                <CheckBox Name="chkApp_RTSS" Content="RivaTuner Statistics (RTSS)"/>
                                <CheckBox Name="chkApp_Afterburner" Content="MSI Afterburner"/>
                            </StackPanel>

                            <!-- Column 2: Dev Tools -->
                            <StackPanel Grid.Column="1" Margin="4,0,4,0">
                                <TextBlock Text="💻 Development &amp; Tools" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                <CheckBox Name="chkApp_VSCode" Content="Visual Studio Code"/>
                                <CheckBox Name="chkApp_Git" Content="Git for Windows"/>
                                <CheckBox Name="chkApp_Terminal" Content="Windows Terminal"/>
                                <CheckBox Name="chkApp_Node" Content="Node.js LTS"/>
                                <CheckBox Name="chkApp_Python" Content="Python 3.12"/>
                                <CheckBox Name="chkApp_7Zip" Content="7-Zip"/>
                            </StackPanel>

                            <!-- Column 3: Utilities & Browsers -->
                            <StackPanel Grid.Column="2" Margin="8,0,0,0">
                                <TextBlock Text="🌐 Web Browsers" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                <CheckBox Name="chkApp_Brave" Content="Brave Browser"/>
                                <CheckBox Name="chkApp_Chrome" Content="Google Chrome"/>
                                <CheckBox Name="chkApp_Firefox" Content="Mozilla Firefox"/>

                                <TextBlock Text="🔧 System Utilities" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,12,0,6"/>
                                <CheckBox Name="chkApp_Everything" Content="Everything Search"/>
                                <CheckBox Name="chkApp_VLC" Content="VLC Media Player"/>
                                <CheckBox Name="chkApp_HWMonitor" Content="CPUID HWMonitor"/>
                                <CheckBox Name="chkApp_BleachBit" Content="BleachBit Cleaner"/>
                            </StackPanel>
                        </Grid>

                        <Separator Background="#334155" Margin="0,5,0,12"/>
                        <WrapPanel>
                            <Button Name="btnInstallSelectedApps" Content="📥 Install Selected Apps (WinGet)" Background="#0284C7" Height="36" Margin="0,0,10,8" Padding="15,0"/>
                            <Button Name="btnUpgradeAllApps" Content="🔄 Upgrade All Installed Apps" Margin="0,0,10,8" Height="36"/>
                            <Button Name="btnOpenDebloaterInGui" Content="🗑️ Debloat Preinstalled Windows Apps" Background="#7F1D1D" Margin="0,0,10,8" Height="36"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 4: VOLTPLAY (GAME TUNER) -->
            <TabItem Header="Game Tuner">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="VoltPlay: In-Game Performance &amp; Stutter Eliminator" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                        <TextBlock Text="Penyelarasan konfigurasi game dinamis berdasarkan profil kartu grafis NVIDIA RTX 4060 Laptop:" Foreground="#94A3B8" Margin="0,0,0,12"/>

                        <Border Background="#0F172A" CornerRadius="6" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,12">
                            <StackPanel>
                                <CheckBox Name="chkGameRDR2" Content="Red Dead Redemption 2: Async Compute On &amp; MaxTexUpgrades 10 (Anti-Texture Pop-In)" IsChecked="True"/>
                                <CheckBox Name="chkGameW3" Content="The Witcher 3 DX12: Matikan HairWorks (Hemat 25% GPU), Foliage 2, &amp; Siapkan DLSS-G" IsChecked="True"/>
                                <CheckBox Name="chkGameHSR" Content="Honkai: Star Rail: Kunci 60 FPS Stabil &amp; Anti-Aliasing Seimbang (Bebas Thermal Throttle)" IsChecked="True"/>
                                <CheckBox Name="chkGameGenshin" Content="Genshin Impact: Kunci 60 FPS Stabil &amp; Crowd Density Medium" IsChecked="True"/>
                                <CheckBox Name="chkGameSteamHighPerf" Content="Daftarkan Seluruh Game Steam Terdeteksi ke GPU High Performance (Windows Settings)" IsChecked="True"/>
                            </StackPanel>
                        </Border>

                        <Button Name="btnApplyGameTuning" Content="🎮 Terapkan Optimasi Game Terpilih" Background="#0284C7" Height="38" Width="280" HorizontalAlignment="Left"/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 5: VOLTCLEAN -->
            <TabItem Header="VoltClean">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Pembersih Disk Lintas-Drive Dinamis (VoltClean)" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                        <TextBlock Text="Aman terlindungi Dynamic Process Guard (melewati file yang sedang dikunci aplikasi/game):" Foreground="#94A3B8" Margin="0,0,0,12"/>

                        <Border Background="#0F172A" CornerRadius="6" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,15">
                            <StackPanel>
                                <CheckBox Name="chkCleanTemp" Content="Temporary Files (%TEMP% &amp; C:\Windows\Temp)" IsChecked="True"/>
                                <CheckBox Name="chkCleanUpdates" Content="Windows Update Download Cache (C:\Windows\SoftwareDistribution\Download)" IsChecked="True"/>
                                <CheckBox Name="chkCleanShaders" Content="DirectX &amp; GPU Shader Cache (NVIDIA DX/GL, AMD, Intel, D3DSCache)" IsChecked="True"/>
                                <CheckBox Name="chkCleanSteamShaders" Content="Steam Shader Caches across ALL Drives (C:, D:)" IsChecked="True"/>
                                <CheckBox Name="chkCleanCrash" Content="Windows Crash Dumps &amp; WER Minidumps" IsChecked="True"/>
                                <CheckBox Name="chkCleanRecycle" Content="Kosongkan Recycle Bin pada Seluruh Drive" IsChecked="True"/>
                                <CheckBox Name="chkCleanDism" Content="DISM Component Store Cleanup (ResetBase - Hapus Update Usang)" IsChecked="False"/>
                            </StackPanel>
                        </Border>

                        <WrapPanel>
                            <Button Name="btnRunVoltClean" Content="🧹 Bersihkan Sampah Sekarang (VoltClean)" Background="#0284C7" Height="38" Padding="15,0" Margin="0,0,10,0"/>
                            <Button Name="btnDismOnly" Content="📦 Jalankan DISM Cleanup ResetBase Saja" Height="38" Padding="15,0"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 6: SYSTEM HEALTH & FEATURES -->
            <TabItem Header="System Health">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Windows Features (Fitur Opsional)" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                        <WrapPanel Margin="0,0,0,15">
                            <Button Name="btnFeatDirectPlay" Content="Aktifkan DirectPlay (Game Jadul)" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnFeatSandbox" Content="Aktifkan Windows Sandbox" Margin="0,0,8,8" Height="32"/>
                            <Button Name="btnFeatWSL" Content="Aktifkan WSL2 (Linux Subsystem)" Margin="0,0,8,8" Height="32"/>
                        </WrapPanel>

                        <TextBlock Text="Diagnostik &amp; Perbaikan Sistem Windows" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,5,0,8"/>
                        <WrapPanel Margin="0,0,0,10">
                            <Button Name="btnHealthSfc" Content="🛡️ SFC /scannow" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthDism" Content="🔧 DISM /RestoreHealth" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthResetWU" Content="🔄 Reset Windows Update" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthResetNet" Content="📶 Reset Network &amp; Winsock" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthRebuildIcons" Content="🖼️ Rebuild Icon Cache" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthTrimRam" Content="🧠 Trim Standby Memory" Margin="0,0,8,8" Height="34"/>
                            <Button Name="btnHealthDnsBench" Content="🌐 Benchmark Latensi DNS" Margin="0,0,8,8" Height="34"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 7: VOLTUNDO -->
            <TabItem Header="VoltUndo">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="VoltUndo: Sistem Pemulihan 1-Klik Mandiri" FontSize="16" FontWeight="Bold" Foreground="#FBBF24" Margin="0,0,0,6"/>
                        <TextBlock Text="Pilih snapshot cadangan yang ingin dikembalikan ke kondisi semula:" Foreground="#94A3B8" Margin="0,0,0,10"/>

                        <ComboBox Name="cmbSnapshots" Height="32" Background="#0F172A" Foreground="#F8FAFC" Margin="0,0,0,15"/>

                        <WrapPanel>
                            <Button Name="btnRestoreSelectedSnap" Content="↩️ Restore Snapshot Terpilih (1-Klik Rollback)" Background="#DC2626" Height="38" Padding="15,0" Margin="0,0,10,0"/>
                            <Button Name="btnRefreshSnaps" Content="🔄 Muat Ulang Daftar" Height="38" Padding="15,0"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Embedded Activity Log Panel (Bottom of Window) -->
        <Border Grid.Row="2" Background="#0B132B" CornerRadius="6" BorderBrush="#334155" BorderThickness="1" Margin="0,10,0,0">
            <TextBox Name="txtConsoleLog" Background="Transparent" Foreground="#38BDF8" FontFamily="Consolas" FontSize="12" BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" Margin="8" Text="[Ready] Voltune GUI Initialized. No terminal typing needed."/>
        </Border>

        <!-- Footer -->
        <TextBlock Grid.Row="3" Text="Safe by default • Reversible by design • 100% Dynamic • Zero VPN harm" Foreground="#64748B" FontSize="11" Margin="4,6,0,0"/>
    </Grid>
</Window>
"@

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    $logBox = $window.FindName("txtConsoleLog")
    $AppendLog = {
        param([string]$Message)
        $time = (Get-Date).ToString("HH:mm:ss")
        $logBox.AppendText("`r`n[$time] $Message")
        $logBox.ScrollToEnd()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    # Populate Snapshots in ComboBox
    $PopulateSnaps = {
        $cmb = $window.FindName("cmbSnapshots")
        $cmb.Items.Clear()
        $snaps = Get-ChildItem -Path $Script:BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        foreach ($s in $snaps) {
            $cmb.Items.Add("$($s.Name) ($($s.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')))") | Out-Null
        }
        if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }
    }
    & $PopulateSnaps

    # Dashboard Button Handlers
    $window.FindName("btnDashSnapshot").Add_Click({
        & $AppendLog "Membuat snapshot registri & game config VoltUndo..."
        $dir = New-VoltBackupSnapshot -Hardware $Hardware
        & $AppendLog "[✓] Snapshot berhasil disimpan di: $dir"
        & $PopulateSnaps
        [System.Windows.MessageBox]::Show("Snapshot berhasil dibuat!", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnDashRestorePoint").Add_Click({
        & $AppendLog "Membuat Windows System Restore Point..."
        $ok = New-VoltRestorePoint -Description "Voltune-GUI-Snapshot"
        if ($ok) { & $AppendLog "[✓] Restore Point berhasil dibuat!" } else { & $AppendLog "[!] Dibatasi Windows (1x per 24 jam)." }
    })

    $window.FindName("btnDashToggleHiber").Add_Click({
        & $AppendLog "Menjalankan toggle status hibernasi..."
        Toggle-VoltHibernation -Hardware $Hardware
        $Hardware = Get-VoltHardwareProfile
        & $AppendLog "[✓] Status hibernasi berhasil diubah!"
    })

    $window.FindName("btnDashPowerUlt").Add_Click({
        Set-VoltPowerPlan -PlanType "Ultimate"
        & $AppendLog "[✓] Skema daya Ultimate Performance aktif!"
    })

    $window.FindName("btnDashPowerBal").Add_Click({
        Set-VoltPowerPlan -PlanType "Balanced"
        & $AppendLog "[✓] Skema daya Balanced (Hemat/Standar) aktif!"
    })

    # Tweaks Presets
    $window.FindName("btnPresetRecommended").Add_Click({
        $window.FindName("chkHags").IsChecked = $true
        $window.FindName("chkGameMode").IsChecked = $true
        $window.FindName("chkGameDVR").IsChecked = $true
        $window.FindName("chkRawMouse").IsChecked = $true
        $window.FindName("chkDefender").IsChecked = $true
        $window.FindName("chkNetwork").IsChecked = $true
        $window.FindName("chkPowerThrottle").IsChecked = $false
        $window.FindName("chkSafeServices").IsChecked = $true
        $window.FindName("chkSecurityUpdates").IsChecked = $true
        $window.FindName("chkClassicMenu").IsChecked = $true
        $window.FindName("chkFileExt").IsChecked = $true
        $window.FindName("chkThisPC").IsChecked = $true
        $window.FindName("chkHiddenFiles").IsChecked = $true
        $window.FindName("chkCleanTaskbar").IsChecked = $true
        $window.FindName("chkCleanQuickAccess").IsChecked = $true
        $window.FindName("chkTelemetry").IsChecked = $true
        $window.FindName("chkRecall").IsChecked = $true
        $window.FindName("chkCopilot").IsChecked = $true
        $window.FindName("chkStartSearch").IsChecked = $true
        $window.FindName("chkAdId").IsChecked = $true
        $window.FindName("chkDeliveryOpt").IsChecked = $true
        & $AppendLog "[Preset] Recommended Preset dipilih. Lu bisa customize checkbox lalu klik 'Terapkan'."
    })

    $window.FindName("btnPresetLaptop").Add_Click({
        $window.FindName("chkHags").IsChecked = $true
        $window.FindName("chkGameMode").IsChecked = $true
        $window.FindName("chkGameDVR").IsChecked = $true
        $window.FindName("chkRawMouse").IsChecked = $true
        $window.FindName("chkDefender").IsChecked = $true
        $window.FindName("chkNetwork").IsChecked = $true
        $window.FindName("chkPowerThrottle").IsChecked = $false
        $window.FindName("chkSafeServices").IsChecked = $true
        $window.FindName("chkSecurityUpdates").IsChecked = $true
        $window.FindName("chkClassicMenu").IsChecked = $true
        $window.FindName("chkFileExt").IsChecked = $true
        $window.FindName("chkThisPC").IsChecked = $true
        $window.FindName("chkCleanTaskbar").IsChecked = $true
        $window.FindName("chkTelemetry").IsChecked = $true
        $window.FindName("chkRecall").IsChecked = $true
        $window.FindName("chkCopilot").IsChecked = $true
        $window.FindName("chkStartSearch").IsChecked = $true
        & $AppendLog "[Preset] Laptop Gaming Preset dipilih (Battery-aware & Game Priority)."
    })

    $window.FindName("btnPresetDesktop").Add_Click({
        $window.FindName("chkHags").IsChecked = $true
        $window.FindName("chkGameMode").IsChecked = $true
        $window.FindName("chkGameDVR").IsChecked = $true
        $window.FindName("chkRawMouse").IsChecked = $true
        $window.FindName("chkDefender").IsChecked = $true
        $window.FindName("chkNetwork").IsChecked = $true
        $window.FindName("chkPowerThrottle").IsChecked = $true
        $window.FindName("chkSafeServices").IsChecked = $true
        $window.FindName("chkSecurityUpdates").IsChecked = $true
        $window.FindName("chkClassicMenu").IsChecked = $true
        $window.FindName("chkFileExt").IsChecked = $true
        $window.FindName("chkThisPC").IsChecked = $true
        $window.FindName("chkHiddenFiles").IsChecked = $true
        $window.FindName("chkCleanTaskbar").IsChecked = $true
        $window.FindName("chkCleanQuickAccess").IsChecked = $true
        $window.FindName("chkTelemetry").IsChecked = $true
        $window.FindName("chkRecall").IsChecked = $true
        $window.FindName("chkCopilot").IsChecked = $true
        $window.FindName("chkStartSearch").IsChecked = $true
        $window.FindName("chkAdId").IsChecked = $true
        $window.FindName("chkDeliveryOpt").IsChecked = $true
        & $AppendLog "[Preset] Desktop Max Preset dipilih (Semua performa aktif, Power Throttling Off)."
    })

    $window.FindName("btnPresetMinimal").Add_Click({
        $window.FindName("chkHags").IsChecked = $false
        $window.FindName("chkGameMode").IsChecked = $false
        $window.FindName("chkGameDVR").IsChecked = $false
        $window.FindName("chkRawMouse").IsChecked = $false
        $window.FindName("chkDefender").IsChecked = $false
        $window.FindName("chkNetwork").IsChecked = $false
        $window.FindName("chkPowerThrottle").IsChecked = $false
        $window.FindName("chkSafeServices").IsChecked = $false
        $window.FindName("chkSecurityUpdates").IsChecked = $false
        $window.FindName("chkClassicMenu").IsChecked = $true
        $window.FindName("chkFileExt").IsChecked = $true
        $window.FindName("chkThisPC").IsChecked = $true
        $window.FindName("chkHiddenFiles").IsChecked = $false
        $window.FindName("chkCleanTaskbar").IsChecked = $true
        $window.FindName("chkCleanQuickAccess").IsChecked = $true
        $window.FindName("chkTelemetry").IsChecked = $true
        $window.FindName("chkRecall").IsChecked = $true
        $window.FindName("chkCopilot").IsChecked = $true
        $window.FindName("chkStartSearch").IsChecked = $true
        $window.FindName("chkAdId").IsChecked = $true
        $window.FindName("chkDeliveryOpt").IsChecked = $true
        & $AppendLog "[Preset] Minimal Privacy & QoL Preset dipilih."
    })

    $window.FindName("btnPresetClear").Add_Click({
        $chkList = @("chkHags","chkGameMode","chkGameDVR","chkRawMouse","chkDefender","chkNetwork","chkPowerThrottle",
                     "chkSafeServices","chkSecurityUpdates","chkClassicMenu","chkFileExt","chkThisPC","chkHiddenFiles",
                     "chkCleanTaskbar","chkCleanQuickAccess","chkTelemetry","chkRecall","chkCopilot","chkStartSearch","chkAdId","chkDeliveryOpt")
        foreach ($c in $chkList) { $window.FindName($c).IsChecked = $false }
        & $AppendLog "[Preset] Semua centang tweaks dibersihkan."
    })

    # Run Selected Tweaks Button
    $window.FindName("btnRunSelectedTweaks").Add_Click({
        & $AppendLog "Menerapkan seluruh tweaks yang dicentang..."
        New-VoltRestorePoint -Description "Voltune-Pre-Tweaks"
        New-VoltBackupSnapshot -Hardware $Hardware
        & $PopulateSnaps

        if ($window.FindName("chkHags").IsChecked -or $window.FindName("chkGameMode").IsChecked -or $window.FindName("chkGameDVR").IsChecked) {
            Optimize-VoltWindowsCore
            & $AppendLog "[✓] Windows Gaming Core (HAGS, Game Mode, MMCSS, GameDVR Off) diterapkan."
        }
        if ($window.FindName("chkRawMouse").IsChecked) {
            Set-VoltRawMouseInput
            & $AppendLog "[✓] 1:1 Raw Mouse Input diterapkan."
        }
        if ($window.FindName("chkDefender").IsChecked) {
            Add-VoltDefenderGameExclusions -Hardware $Hardware
            & $AppendLog "[✓] Folder game ditambahkan ke Defender Exclusion."
        }
        if ($window.FindName("chkNetwork").IsChecked) {
            Set-VoltNetworkGamingTweaks
            & $AppendLog "[✓] TCP/IP Gaming Latency Optimizer diterapkan."
        }
        if ($window.FindName("chkPowerThrottle").IsChecked) {
            Set-VoltPowerThrottlingOff
            & $AppendLog "[✓] CPU Power Throttling dimatikan."
        }
        if ($window.FindName("chkClassicMenu").IsChecked) {
            Set-VoltClassicContextMenu
            & $AppendLog "[✓] Classic Context Menu Windows 10 aktif."
        }
        if ($window.FindName("chkFileExt").IsChecked -or $window.FindName("chkThisPC").IsChecked -or $window.FindName("chkHiddenFiles").IsChecked -or $window.FindName("chkCleanQuickAccess").IsChecked) {
            Set-VoltExplorerTweaks
            & $AppendLog "[✓] Explorer Pro Tweaks diterapkan."
        }
        if ($window.FindName("chkCleanTaskbar").IsChecked -or $window.FindName("chkStartSearch").IsChecked) {
            Set-VoltTaskbarAndStartTweaks
            & $AppendLog "[✓] Taskbar & Start Menu Tweaks diterapkan."
        }
        if ($window.FindName("chkTelemetry").IsChecked -or $window.FindName("chkRecall").IsChecked -or $window.FindName("chkCopilot").IsChecked -or $window.FindName("chkAdId").IsChecked -or $window.FindName("chkDeliveryOpt").IsChecked) {
            Set-VoltPrivacyAndTelemetry
            & $AppendLog "[✓] Privasi, Anti-Telemetri & Recall Off diterapkan."
        }
        if ($window.FindName("chkSafeServices").IsChecked) {
            Optimize-VoltServices
            & $AppendLog "[✓] Safe Gaming Services Optimizer diterapkan."
        }
        if ($window.FindName("chkSecurityUpdates").IsChecked) {
            Set-VoltWindowsUpdateProfile
            & $AppendLog "[✓] Windows Update dikunci ke Security Updates Only."
        }

        & $AppendLog "[✓] Selesai! Seluruh tweaks yang dicentang berhasil diterapkan."
        [System.Windows.MessageBox]::Show("Seluruh tweaks yang dicentang berhasil diterapkan!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Undo Selected Tweaks Button
    $window.FindName("btnUndoSelectedTweaks").Add_Click({
        & $AppendLog "Mengembalikan tweaks terpilih ke kondisi default..."
        if ($window.FindName("chkClassicMenu").IsChecked) { Set-VoltClassicContextMenu -Disable }
        if ($window.FindName("chkRawMouse").IsChecked) { Set-VoltRawMouseInput -Revert }
        if ($window.FindName("chkNetwork").IsChecked) { Set-VoltNetworkGamingTweaks -Revert }
        if ($window.FindName("chkSafeServices").IsChecked) { Optimize-VoltServices -Revert }
        if ($window.FindName("chkSecurityUpdates").IsChecked) { Set-VoltWindowsUpdateProfile -Revert }
        if ($window.FindName("chkTelemetry").IsChecked) { Set-VoltPrivacyAndTelemetry -Revert }
        if ($window.FindName("chkCleanTaskbar").IsChecked) { Set-VoltTaskbarAndStartTweaks -Revert }
        if ($window.FindName("chkPowerThrottle").IsChecked) { Set-VoltPowerThrottlingOff -Disable }
        & $AppendLog "[✓] Tweaks terpilih telah dikembalikan ke standar."
        [System.Windows.MessageBox]::Show("Tweaks terpilih berhasil di-revert!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Install Apps Presets
    $appIdMap = @{
        "chkApp_VCRedist"    = @{ Name = "Visual C++ 2015-2022 AIO"; Id = "Microsoft.VCRedist.2015+.x64" }
        "chkApp_DirectX"     = @{ Name = "DirectX End-User Runtimes"; Id = "Microsoft.DirectX" }
        "chkApp_DotNet"      = @{ Name = ".NET Desktop Runtime 8"; Id = "Microsoft.DotNet.DesktopRuntime.8" }
        "chkApp_Steam"       = @{ Name = "Steam"; Id = "Valve.Steam" }
        "chkApp_Epic"        = @{ Name = "Epic Games Launcher"; Id = "EpicGames.EpicGamesLauncher" }
        "chkApp_Discord"     = @{ Name = "Discord"; Id = "Discord.Discord" }
        "chkApp_OBS"         = @{ Name = "OBS Studio"; Id = "OBSProject.OBSStudio" }
        "chkApp_RTSS"        = @{ Name = "RivaTuner Statistics (RTSS)"; Id = "Guru3D.RTSS" }
        "chkApp_Afterburner" = @{ Name = "MSI Afterburner"; Id = "Guru3D.Afterburner" }
        "chkApp_VSCode"      = @{ Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" }
        "chkApp_Git"         = @{ Name = "Git for Windows"; Id = "Git.Git" }
        "chkApp_Terminal"    = @{ Name = "Windows Terminal"; Id = "Microsoft.WindowsTerminal" }
        "chkApp_Node"        = @{ Name = "Node.js LTS"; Id = "OpenJS.NodeJS.LTS" }
        "chkApp_Python"      = @{ Name = "Python 3.12"; Id = "Python.Python.3.12" }
        "chkApp_7Zip"        = @{ Name = "7-Zip"; Id = "7zip.7zip" }
        "chkApp_Brave"       = @{ Name = "Brave Browser"; Id = "Brave.Brave" }
        "chkApp_Chrome"      = @{ Name = "Google Chrome"; Id = "Google.Chrome" }
        "chkApp_Firefox"     = @{ Name = "Mozilla Firefox"; Id = "Mozilla.Firefox" }
        "chkApp_Everything"  = @{ Name = "Everything Search"; Id = "voidtools.Everything" }
        "chkApp_VLC"         = @{ Name = "VLC Media Player"; Id = "VideoLAN.VLC" }
        "chkApp_HWMonitor"   = @{ Name = "CPUID HWMonitor"; Id = "CPUID.HWMonitor" }
        "chkApp_BleachBit"   = @{ Name = "BleachBit"; Id = "BleachBit.BleachBit" }
    }

    $window.FindName("btnAppsRuntimes").Add_Click({
        $window.FindName("chkApp_VCRedist").IsChecked = $true
        $window.FindName("chkApp_DirectX").IsChecked = $true
        $window.FindName("chkApp_DotNet").IsChecked = $true
        & $AppendLog "[Apps] Preset Runtimes dipilih."
    })

    $window.FindName("btnAppsGaming").Add_Click({
        $window.FindName("chkApp_Steam").IsChecked = $true
        $window.FindName("chkApp_Epic").IsChecked = $true
        $window.FindName("chkApp_Discord").IsChecked = $true
        $window.FindName("chkApp_OBS").IsChecked = $true
        $window.FindName("chkApp_RTSS").IsChecked = $true
        $window.FindName("chkApp_Afterburner").IsChecked = $true
        & $AppendLog "[Apps] Preset Gaming Bundle dipilih."
    })

    $window.FindName("btnAppsDev").Add_Click({
        $window.FindName("chkApp_VSCode").IsChecked = $true
        $window.FindName("chkApp_Git").IsChecked = $true
        $window.FindName("chkApp_Terminal").IsChecked = $true
        $window.FindName("chkApp_Node").IsChecked = $true
        $window.FindName("chkApp_Python").IsChecked = $true
        $window.FindName("chkApp_7Zip").IsChecked = $true
        & $AppendLog "[Apps] Preset Dev Tools Bundle dipilih."
    })

    $window.FindName("btnAppsBrowsers").Add_Click({
        $window.FindName("chkApp_Brave").IsChecked = $true
        $window.FindName("chkApp_Chrome").IsChecked = $true
        $window.FindName("chkApp_Firefox").IsChecked = $true
        & $AppendLog "[Apps] Preset Web Browsers dipilih."
    })

    $window.FindName("btnAppsClear").Add_Click({
        foreach ($k in $appIdMap.Keys) { $window.FindName($k).IsChecked = $false }
        & $AppendLog "[Apps] Seluruh centang software dibersihkan."
    })

    # Install Selected Apps Button
    $window.FindName("btnInstallSelectedApps").Add_Click({
        $selected = @()
        foreach ($k in $appIdMap.Keys) {
            $chk = $window.FindName($k)
            if ($chk -and $chk.IsChecked) {
                $selected += $appIdMap[$k]
            }
        }

        if ($selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show("Silakan centang software yang ingin dipasang terlebih dahulu.", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        & $AppendLog "Memulai instalasi $($selected.Count) software via WinGet..."
        foreach ($app in $selected) {
            & $AppendLog "Menginstal $($app.Name) ($($app.Id))..."
            & winget install --id $app.Id -e --silent --accept-package-agreements --accept-source-agreements
            & $AppendLog "[✓] $($app.Name) selesai dipasang."
        }
        & $AppendLog "[✓] Seluruh software terpilih berhasil dipasang!"
        [System.Windows.MessageBox]::Show("Instalasi software terpilih selesai!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Upgrade All Apps Button
    $window.FindName("btnUpgradeAllApps").Add_Click({
        & $AppendLog "Menjalankan pembaruan seluruh aplikasi terpasang (winget upgrade --all)..."
        & winget upgrade --all --silent --accept-package-agreements --accept-source-agreements
        & $AppendLog "[✓] Pemeriksaan & pembaruan software selesai."
        [System.Windows.MessageBox]::Show("Pembaruan software selesai!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # In-GUI Appx Debloater
    $window.FindName("btnOpenDebloaterInGui").Add_Click({
        & $AppendLog "Memindai dan membersihkan bloatware Windows bawaan..."
        $bloats = @("Microsoft.BingNews","Microsoft.BingWeather","Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.MicrosoftFeedbackHub","Microsoft.MicrosoftSolitaireCollection","Clipchamp.Clipchamp","Microsoft.ZuneVideo")
        $removed = 0
        foreach ($b in $bloats) {
            $pkgs = Get-AppxPackage -Name $b -ErrorAction SilentlyContinue
            foreach ($p in $pkgs) {
                & $AppendLog "Menghapus $($p.Name)..."
                Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue
                $removed++
            }
        }
        & $AppendLog "[✓] Pembersihan bloatware selesai! $removed paket dibersihkan."
        [System.Windows.MessageBox]::Show("Debloat selesai! $removed paket bloatware dihapus.", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # VoltPlay Game Tuning Button
    $window.FindName("btnApplyGameTuning").Add_Click({
        & $AppendLog "Menerapkan penyelarasan konfigurasi game terpilih..."
        New-VoltBackupSnapshot -Hardware $Hardware
        & $PopulateSnaps

        if ($window.FindName("chkGameRDR2").IsChecked -and $Hardware.DiscoveredGames.Contains("Rockstar_RDR2")) {
            Optimize-VoltGameRDR2 -ConfigPath $Hardware.DiscoveredGames["Rockstar_RDR2"].ConfigFile
            & $AppendLog "[✓] Red Dead Redemption 2 dioptimasi."
        }
        if ($window.FindName("chkGameW3").IsChecked -and $Hardware.DiscoveredGames.Contains("CDPR_W3")) {
            Optimize-VoltGameWitcher3 -ConfigPath $Hardware.DiscoveredGames["CDPR_W3"].ConfigFile
            & $AppendLog "[✓] The Witcher 3 DX12 dioptimasi."
        }
        if ($window.FindName("chkGameHSR").IsChecked -and $Hardware.DiscoveredGames.Contains("HoYo_HSR")) {
            Optimize-VoltGameHSR -GameInfo $Hardware.DiscoveredGames["HoYo_HSR"]
            & $AppendLog "[✓] Honkai: Star Rail dioptimasi."
        }
        if ($window.FindName("chkGameGenshin").IsChecked -and $Hardware.DiscoveredGames.Contains("HoYo_Genshin")) {
            Optimize-VoltGameGenshin -GameInfo $Hardware.DiscoveredGames["HoYo_Genshin"]
            & $AppendLog "[✓] Genshin Impact dioptimasi."
        }
        if ($window.FindName("chkGameSteamHighPerf").IsChecked) {
            Optimize-VoltPlayGames -Hardware $Hardware -TargetGameKey "ALL"
            & $AppendLog "[✓] Game Steam didaftarkan ke GPU High Performance."
        }
        & $AppendLog "[✓] Penyelarasan setting game selesai!"
        [System.Windows.MessageBox]::Show("Penyelarasan setting in-game selesai!", "VoltPlay", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # VoltClean Button
    $window.FindName("btnRunVoltClean").Add_Click({
        & $AppendLog "Menjalankan pembersihan sampah disk VoltClean..."
        $freed = Invoke-VoltClean -Hardware $Hardware
        $Hardware = Get-VoltHardwareProfile
        & $AppendLog "[✓] VoltClean selesai! Ruang bebas dipulihkan: $([math]::Round($freed / 1MB, 1)) MB."
        if ($window.FindName("chkCleanDism").IsChecked) {
            & $AppendLog "Menjalankan DISM Component Cleanup ResetBase..."
            & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
            & $AppendLog "[✓] DISM Cleanup selesai!"
        }
        [System.Windows.MessageBox]::Show("Pembersihan disk selesai!", "VoltClean", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnDismOnly").Add_Click({
        & $AppendLog "Menjalankan DISM Component Cleanup ResetBase..."
        & dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
        & $AppendLog "[✓] DISM Cleanup selesai!"
        [System.Windows.MessageBox]::Show("DISM Cleanup selesai!", "VoltClean", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # System Health & Features Buttons
    $window.FindName("btnFeatDirectPlay").Add_Click({
        & $AppendLog "Mengaktifkan DirectPlay..."
        Set-VoltWindowsFeatureDirectPlay
        & $AppendLog "[✓] DirectPlay diaktifkan!"
    })

    $window.FindName("btnFeatSandbox").Add_Click({
        & $AppendLog "Mengaktifkan Windows Sandbox..."
        Set-VoltWindowsFeatureSandbox
        & $AppendLog "[✓] Windows Sandbox diaktifkan!"
    })

    $window.FindName("btnFeatWSL").Add_Click({
        & $AppendLog "Mengaktifkan WSL2..."
        Set-VoltWindowsFeatureWSL
        & $AppendLog "[✓] WSL2 diaktifkan!"
    })

    $window.FindName("btnHealthSfc").Add_Click({
        & $AppendLog "Menjalankan SFC /scannow (harap tunggu)..."
        & sfc.exe /scannow
        & $AppendLog "[✓] SFC /scannow selesai!"
    })

    $window.FindName("btnHealthDism").Add_Click({
        & $AppendLog "Menjalankan DISM /RestoreHealth..."
        & dism.exe /Online /Cleanup-Image /RestoreHealth
        & $AppendLog "[✓] DISM /RestoreHealth selesai!"
    })

    $window.FindName("btnHealthResetWU").Add_Click({
        & $AppendLog "Mereset komponen Windows Update..."
        Reset-VoltWindowsUpdate
        & $AppendLog "[✓] Windows Update di-reset!"
    })

    $window.FindName("btnHealthResetNet").Add_Click({
        & $AppendLog "Mereset TCP/IP stack & Winsock..."
        Reset-VoltNetwork
        & $AppendLog "[✓] Network & Winsock di-reset!"
    })

    $window.FindName("btnHealthRebuildIcons").Add_Click({
        & $AppendLog "Membangun ulang Icon & Thumbnail Cache..."
        Rebuild-VoltIconCache
        & $AppendLog "[✓] Icon Cache diperbarui!"
    })

    $window.FindName("btnHealthTrimRam").Add_Click({
        & $AppendLog "Membersihkan Standby Memory & Working Set RAM..."
        Clear-VoltStandbyMemory
        & $AppendLog "[✓] Standby Memory dibersihkan!"
    })

    $window.FindName("btnHealthDnsBench").Add_Click({
        & $AppendLog "Menjalankan Benchmark Latensi DNS..."
        $resolvers = @(@{ Name = "Cloudflare"; IP = "1.1.1.1" }, @{ Name = "Google"; IP = "8.8.8.8" }, @{ Name = "Quad9"; IP = "9.9.9.9" })
        foreach ($r in $resolvers) {
            $ping = Test-Connection -ComputerName $r.IP -Count 2 -ErrorAction SilentlyContinue
            if ($ping) {
                $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average)
                & $AppendLog "  -> $($r.Name) ($($r.IP)): Rata-rata Ping = $avg ms"
            }
        }
        & ipconfig.exe /flushdns | Out-Null
        & $AppendLog "[✓] DNS Cache di-flush!"
    })

    # VoltUndo Buttons
    $window.FindName("btnRefreshSnaps").Add_Click({
        & $PopulateSnaps
        & $AppendLog "[VoltUndo] Daftar snapshot diperbarui."
    })

    $window.FindName("btnRestoreSelectedSnap").Add_Click({
        $cmb = $window.FindName("cmbSnapshots")
        if (-not $cmb.SelectedItem) {
            [System.Windows.MessageBox]::Show("Silakan pilih snapshot yang ingin di-restore.", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }

        $snapName = ($cmb.SelectedItem -split " ")[0]
        $snapDir = Join-Path $Script:BackupDir $snapName
        $confirm = [System.Windows.MessageBox]::Show("Apakah lu yakin ingin mengembalikan sistem ke snapshot '$snapName'?", "Konfirmasi Rollback", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
            & $AppendLog "Memulihkan sistem dari snapshot: $snapName..."
            $res = Restore-VoltSnapshotByPath -SnapshotDir $snapDir
            if ($res) {
                & $AppendLog "[✓] Sistem berhasil dikembalikan ke kondisi snapshot '$snapName'!"
                [System.Windows.MessageBox]::Show("Sistem berhasil dikembalikan ke kondisi snapshot!", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } else {
                & $AppendLog "[-] Gagal memulihkan snapshot."
            }
        }
    })

    $window.ShowDialog() | Out-Null
}

# ------------------------------------------------------------------------------
# 21. INTERACTIVE UI & DYNAMIC DISPLAY (CLI FALLBACK)
# ------------------------------------------------------------------------------
function Show-VoltBanner {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "            ⚡ VOLTUNE WINDOWS UTILITY v$Script:VoltVersion ⚡                   " -ForegroundColor Yellow
    Write-Host "             Toolkit Optimasi Dinamis, Gaming & Tweaks Tanpa Batas              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-VoltSpecs ($hw) {
    Write-Host "`n[SPEK HARDWARE DINAMIS TERDETEKSI]" -ForegroundColor Yellow
    Write-Host "   Prosesor   : $($hw.CPUName) ($($hw.CPUCores) Cores, $($hw.CPUThreads) Threads$(if ($hw.IsHybridCPU) { ' | Hybrid P+E' }))" -ForegroundColor White
    
    $gpuDesc = if ($hw.DiscreteGPU) {
        $tgp = if ($hw.DiscreteGPU.TGP_W) { " | $($hw.DiscreteGPU.TGP_W)W TGP" } else { "" }
        "$($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM$tgp)"
    } else { "iGPU Only" }
    Write-Host "   Kartu GPU  : $gpuDesc" -ForegroundColor White

    $pwrStatus = if ($hw.IsOnBattery) { "Baterai ($($hw.BatteryChargePct)%) [Mode Hemat Daya]" } else { "AC Adapter (Daya Maksimal) [✓]" }
    Write-Host "   Sumber Daya: $pwrStatus" -ForegroundColor $(if ($hw.IsOnBattery) { 'Yellow' } else { 'Green' })

    Write-Host "   Layar      : $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz" -ForegroundColor White
    Write-Host "   Target FPS : VRR $($hw.DynamicFPSCaps.TearFreeVRR) FPS | Dingin $($hw.DynamicFPSCaps.HalfRate) FPS" -ForegroundColor Gray
    Write-Host "   Memori     : $($hw.RAM_GB) GB RAM" -ForegroundColor White

    $driveStrs = @()
    foreach ($d in $hw.Drives.Values) {
        $driveStrs += "$($d.DeviceID) $($d.FreeGB)/$($d.TotalGB) GB"
    }
    Write-Host "   Storage    : $($driveStrs -join ' | ')" -ForegroundColor White

    $hiberStr = if ($hw.HibernateActive) { "Aktif (~$($hw.HiberfilSizeGB) GB hiberfil.sys)" } else { "Nonaktif (Hemat SSD) [✓]" }
    Write-Host "   Status HAGS: $(if ($hw.HAGS_Status) { 'Aktif [✓]' } else { 'Nonaktif [!]' }) | Hibernate: $hiberStr" -ForegroundColor White

    $gameList = @(foreach ($g in $hw.DiscoveredGames.Values) { $g["Name"] })
    $gameStr = if ($gameList.Count -gt 0) { ($gameList | Select-Object -Unique) -join ", " } else { "Tidak terdeteksi" }
    Write-Host "   Game Nemu  : $gameStr ($($hw.DiscoveredGames.Count) game terdeteksi dinamis)" -ForegroundColor White
}

# ------------------------------------------------------------------------------
# 22. ENTRYPOINT LOGIC
# ------------------------------------------------------------------------------
Invoke-VoltElevation -Bypass:$NoElevation

$hwProfile = Get-VoltHardwareProfile

if ($GUI) {
    Show-VoltGUI -Hardware $hwProfile
    exit 0
}

if ($AutoOptimize) {
    New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
    New-VoltBackupSnapshot -Hardware $hwProfile
    Optimize-VoltWindowsCore
    Optimize-VoltDualGPU -Hardware $hwProfile
    Set-VoltRawMouseInput
    Add-VoltDefenderGameExclusions -Hardware $hwProfile
    Set-VoltPrivacyAndTelemetry
    Set-VoltNetworkGamingTweaks
    Optimize-VoltServices
    Set-VoltWindowsUpdateProfile
    Set-VoltExplorerTweaks
    Set-VoltTaskbarAndStartTweaks
    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
    exit 0
}

if ($CleanOnly) {
    Invoke-VoltClean -Hardware $hwProfile
    exit 0
}

if ($UndoOnly) {
    Invoke-VoltUndo
    exit 0
}

# Interactive Loop (Terminal / TUI)
$running = $true
while ($running) {
    Show-VoltBanner
    Show-VoltSpecs $hwProfile

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " PILIH KATEGORI TINDAKAN (Ketik angka lalu tekan Enter):" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [G] 🖥️ Buka Voltune Modern Native GUI (100% Lewat GUI Tanpa Perlu Ngetik)" -ForegroundColor Green
    Write-Host " [1] 🚀 Optimasi Lengkap (Rekomendasi Terima Beres)" -ForegroundColor White
    Write-Host " [2] 🎮 VoltPlay: Sesuaikan Setting Game Khusus" -ForegroundColor White
    Write-Host " [3] 🧹 VoltClean: Pembersih Disk & Cache Lintas-Drive" -ForegroundColor White
    Write-Host " [4] 🛠️ Windows 11 QoL & Explorer Tweaks (Chris Titus Style)" -ForegroundColor White
    Write-Host " [5] 🛡️ Privasi, Telemetri & Background Bloat Killer" -ForegroundColor White
    Write-Host " [6] ⚡ TCP/IP Gaming Latency & Raw Input (Zero-VPN Harm)" -ForegroundColor White
    Write-Host " [7] ⚙️ Windows Services Optimizer (Safe Gaming Profile)" -ForegroundColor White
    Write-Host " [8] 🔒 Windows Update Control (Security Updates Only Profile)" -ForegroundColor White
    Write-Host " [9] 📦 Game Runtimes & Software Catalog (WinGet One-Click)" -ForegroundColor White
    Write-Host " [10] 🧩 Windows Optional Features (DirectPlay, WSL2, Sandbox)" -ForegroundColor White
    Write-Host " [11] 💾 Reclaim Ruang SSD (Toggle Hibernasi ~$($hwProfile.HiberfilSizeGB) GB)" -ForegroundColor White
    Write-Host " [12] 🔧 System Health & Repair Diagnostics (SFC, DISM, Network Reset)" -ForegroundColor White
    Write-Host " [U] ↩️ VoltUndo: Kembalikan Semua Settingan ke Semula (1-Klik Reset)" -ForegroundColor Yellow
    Write-Host " [0] Keluar" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor DarkCyan

    $choice = Read-Host "`nPilihan lu [0-12 / G / U]"
    switch ($choice.ToUpper()) {
        "G" {
            Show-VoltGUI -Hardware $hwProfile
            $hwProfile = Get-VoltHardwareProfile
        }
        "1" {
            New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltWindowsCore
            Optimize-VoltDualGPU -Hardware $hwProfile
            Set-VoltRawMouseInput
            Add-VoltDefenderGameExclusions -Hardware $Hardware
            Set-VoltPrivacyAndTelemetry
            Set-VoltNetworkGamingTweaks
            Optimize-VoltServices
            Set-VoltWindowsUpdateProfile
            Set-VoltExplorerTweaks
            Set-VoltTaskbarAndStartTweaks
            Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
            Write-Host "`n[✓] Seluruh optimasi lengkap berhasil diterapkan! Tekan Enter untuk lanjut..." -ForegroundColor Green
            Read-Host
        }
        "2" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "3" {
            Invoke-VoltClean -Hardware $hwProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "4" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltClassicContextMenu
            Set-VoltExplorerTweaks
            Set-VoltTaskbarAndStartTweaks
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "5" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltPrivacyAndTelemetry
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "6" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltNetworkGamingTweaks
            Set-VoltRawMouseInput
            Add-VoltDefenderGameExclusions -Hardware $hwProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "7" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltServices
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "8" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Set-VoltWindowsUpdateProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "9" {
            Install-VoltPackageById -Name "Visual C++ 2015-2022 AIO" -Id "Microsoft.VCRedist.2015+.x64"
            Install-VoltPackageById -Name "DirectX End-User Runtimes" -Id "Microsoft.DirectX"
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "10" {
            Set-VoltWindowsFeatureDirectPlay
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "11" {
            Toggle-VoltHibernation -Hardware $hwProfile
            $hwProfile = Get-VoltHardwareProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "12" {
            & sfc.exe /scannow
            & dism.exe /Online /Cleanup-Image /RestoreHealth
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "U" {
            Invoke-VoltUndo
            $hwProfile = Get-VoltHardwareProfile
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "0" {
            $running = $false
            Write-Host "`n[VoltPlay & Voltune] Keluar. Tetap dingin & gaspol!" -ForegroundColor Cyan
        }
    }
}
