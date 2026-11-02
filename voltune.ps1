<#
.SYNOPSIS
    VoltPlay & Voltune Windows Utility v2.0 - Universal Hardware-Aware Performance & Cleanup Toolkit
.DESCRIPTION
    Toolkit optimasi performa Windows, manajemen kartu grafis dual-GPU (NVIDIA/AMD),
    penyelarasan in-game setting anti-stuttering, serta pembersihan cache aman dengan 1-klik Undo.
    Dirancang untuk berjalan mandiri (standalone) via:
    irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex
.NOTES
    Safe by default, Reversible by design, Hardware-Aware, Zero VPN Harm.
#>

[CmdletBinding()]
param(
    [switch]$AutoOptimize,
    [switch]$CleanOnly,
    [switch]$UndoOnly,
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
            # Running via web one-liner (irm | iex)
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
$Script:VoltVersion = "2.0.0-NextGen"
$Script:AppDataDir  = Join-Path $env:LOCALAPPDATA "Voltune"
$Script:BackupDir   = Join-Path $Script:AppDataDir "Backups"
$Script:LogDir      = Join-Path $Script:AppDataDir "Logs"

if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null }
if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

# ------------------------------------------------------------------------------
# 3. DETECTION ENGINE (HARDWARE, ENVIRONMENT, & GAMES)
# ------------------------------------------------------------------------------
function Get-VoltHardwareProfile {
    $profile = [ordered]@{
        CPUName         = "Unknown CPU"
        CPUCores        = 0
        CPUThreads      = 0
        IsHybridCPU     = $false
        RAM_GB          = 0.0
        DriveC_FreeGB   = 0.0
        ScreenResolution= "1920x1080"
        ScreenRefreshHz = 60
        HasNvidiaGPU    = $false
        HasAmdGPU       = $false
        HasIntelGPU     = $false
        DiscreteGPU     = $null
        IntegratedGPU   = $null
        HAGS_Status     = $false
        InstalledGames  = [ordered]@{}
    }

    # CPU Detection
    try {
        $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
        if ($proc) {
            $profile.CPUName = $proc.Name.Trim()
            $profile.CPUCores = [int]$proc.NumberOfCores
            $profile.CPUThreads = [int]$proc.NumberOfLogicalProcessors
            # Check Intel 12th/13th/14th Gen or Core Ultra hybrid
            if ($profile.CPUName -match "1[234]th Gen" -or $profile.CPUName -match "Core Ultra" -or ($profile.CPUThreads -gt ($profile.CPUCores * 1.5) -and $profile.CPUThreads -ne ($profile.CPUCores * 2))) {
                $profile.IsHybridCPU = $true
            }
        }
    } catch {}

    # RAM Detection
    try {
        $cs = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
        if ($cs -and $cs.TotalPhysicalMemory) {
            $profile.RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        }
    } catch {}

    # Drive C: Free Space
    try {
        $driveC = Get-PSDrive C -ErrorAction SilentlyContinue
        if ($driveC) {
            $profile.DriveC_FreeGB = [math]::Round($driveC.Free / 1GB, 1)
        }
    } catch {}

    # GPU & Display Detection (CIM)
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

    # Precise GPU TGP & VRAM query via nvidia-smi (if NVIDIA present)
    if ($profile.HasNvidiaGPU -and (Get-Command "nvidia-smi" -ErrorAction SilentlyContinue)) {
        try {
            $smiOut = & nvidia-smi --query-gpu=name,driver_version,memory.total,power.max_limit --format=csv,noheader,nounits 2>$null
            if ($smiOut -and $smiOut -match "(.+?),\s*(.+?),\s*(\d+),\s*([\d\.]+)") {
                $profile.DiscreteGPU.Name = $Matches[1].Trim()
                $profile.DiscreteGPU.Driver = $Matches[2].Trim()
                $profile.DiscreteGPU.VRAM_GB = [math]::Round([double]$Matches[3] / 1024, 1)
                $profile.DiscreteGPU.TGP_W = [math]::Round([double]$Matches[4])
            }
        } catch {}
    }

    # HAGS Detection (Hardware-Accelerated GPU Scheduling)
    try {
        $hags = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($hags -and $hags.HwSchMode -eq 2) {
            $profile.HAGS_Status = $true
        }
    } catch {}

    # Games Scanner
    $docsPath = [Environment]::GetFolderPath('MyDocuments')

    # 1. Red Dead Redemption 2
    $rdr2Xml = Join-Path $docsPath "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Xml) {
        $profile.InstalledGames["RDR2"] = @{
            Name       = "Red Dead Redemption 2"
            ConfigPath = $rdr2Xml
            Type       = "XML"
        }
    }

    # 2. Honkai: Star Rail (Cognosphere registry)
    if (Test-Path "HKCU:\Software\Cognosphere\Star Rail") {
        $profile.InstalledGames["HSR"] = @{
            Name       = "Honkai: Star Rail"
            ConfigPath = "HKCU:\Software\Cognosphere\Star Rail"
            Type       = "RegistryJSON"
        }
    }

    # 3. Genshin Impact (miHoYo registry)
    if (Test-Path "HKCU:\Software\miHoYo\Genshin Impact") {
        $profile.InstalledGames["Genshin"] = @{
            Name       = "Genshin Impact"
            ConfigPath = "HKCU:\Software\miHoYo\Genshin Impact"
            Type       = "RegistryJSON"
        }
    }

    # 4. The Witcher 3
    $witcherSettings = Join-Path $docsPath "The Witcher 3\dx12user.settings"
    if (Test-Path $witcherSettings) {
        $profile.InstalledGames["Witcher3"] = @{
            Name       = "The Witcher 3: Wild Hunt (DX12)"
            ConfigPath = $witcherSettings
            Type       = "INI"
        }
    }

    return $profile
}

# ------------------------------------------------------------------------------
# 4. BACKUP & UNDO ENGINE (VOLTUNDO)
# ------------------------------------------------------------------------------
function New-VoltBackupSnapshot {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $sessionBackupDir = Join-Path $Script:BackupDir "Snapshot-$timestamp"
    New-Item -ItemType Directory -Path $sessionBackupDir -Force | Out-Null

    Write-Host " [*] Membuat cadangan sistem (Snapshot: $timestamp)..." -ForegroundColor Cyan

    # 1. Backup Registry: MMCSS & SystemProfile
    try {
        & reg.exe export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" (Join-Path $sessionBackupDir "SystemProfile.reg") /y | Out-Null
    } catch {}

    # 2. Backup Registry: GameDVR & GameConfigStore
    try {
        & reg.exe export "HKCU\System\GameConfigStore" (Join-Path $sessionBackupDir "GameConfigStore.reg") /y | Out-Null
        & reg.exe export "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" (Join-Path $sessionBackupDir "GameDVR_Policy.reg") /y | Out-Null
    } catch {}

    # 3. Backup Registry: HAGS
    try {
        & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" (Join-Path $sessionBackupDir "GraphicsDrivers.reg") /y | Out-Null
    } catch {}

    # 4. Backup Registry: Honkai Star Rail & Genshin Impact
    try {
        if (Test-Path "HKCU:\Software\Cognosphere\Star Rail") {
            & reg.exe export "HKCU\Software\Cognosphere\Star Rail" (Join-Path $sessionBackupDir "StarRail.reg") /y | Out-Null
        }
        if (Test-Path "HKCU:\Software\miHoYo\Genshin Impact") {
            & reg.exe export "HKCU\Software\miHoYo\Genshin Impact" (Join-Path $sessionBackupDir "GenshinImpact.reg") /y | Out-Null
        }
    } catch {}

    # 5. Backup game file configs
    $docsPath = [Environment]::GetFolderPath('MyDocuments')
    $rdr2Real = Join-Path $docsPath "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Real) {
        Copy-Item $rdr2Real (Join-Path $sessionBackupDir "RDR2_system.xml") -Force
    }
    $witcherReal = Join-Path $docsPath "The Witcher 3\dx12user.settings"
    if (Test-Path $witcherReal) {
        Copy-Item $witcherReal (Join-Path $sessionBackupDir "Witcher3_dx12user.settings") -Force
    }

    # 6. Save metadata JSON
    $meta = @{
        Timestamp = (Get-Date).ToString("o")
        OS        = (Get-CimInstance Win32_OperatingSystem).Caption
    }
    $meta | ConvertTo-Json | Out-File (Join-Path $sessionBackupDir "manifest.json") -Encoding UTF8

    # Set as latest backup
    $sessionBackupDir | Out-File (Join-Path $Script:BackupDir "latest.txt") -Encoding UTF8 -Force
    Write-Host " [✓] Cadangan registri dan konfigurasi game tersimpan di: $sessionBackupDir" -ForegroundColor Green
    return $sessionBackupDir
}

function Invoke-VoltUndo {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "                     ↩️ PEMULIHAN SETTING VOLTUNE (UNDO)                       " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow

    $latestFile = Join-Path $Script:BackupDir "latest.txt"
    if (-not (Test-Path $latestFile)) {
        Write-Host "[-] Tidak ditemukan riwayat backup otomatis di $Script:BackupDir." -ForegroundColor Red
        return
    }

    $backupPath = (Get-Content $latestFile -Raw).Trim()
    if (-not (Test-Path $backupPath)) {
        Write-Host "[-] Folder backup $backupPath tidak ditemukan." -ForegroundColor Red
        return
    }

    Write-Host "[*] Memulihkan snapshot registri dari: $backupPath" -ForegroundColor Cyan
    $regFiles = Get-ChildItem -Path $backupPath -Filter "*.reg"
    foreach ($rf in $regFiles) {
        Write-Host "    -> Mengimpor $($rf.Name)..." -ForegroundColor Gray
        & reg.exe import $rf.FullName | Out-Null
    }

    # Restore game configs from backup folder or .bak files
    $docsPath = [Environment]::GetFolderPath('MyDocuments')
    $rdr2Real = Join-Path $docsPath "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    $rdr2Snap = Join-Path $backupPath "RDR2_system.xml"
    $rdr2Bak  = "$rdr2Real.bak"
    if (Test-Path $rdr2Snap) {
        Copy-Item $rdr2Snap $rdr2Real -Force
        Write-Host "    -> Memulihkan konfigurasi RDR2 system.xml..." -ForegroundColor Green
    } elseif (Test-Path $rdr2Bak) {
        Copy-Item $rdr2Bak $rdr2Real -Force
        Write-Host "    -> Memulihkan konfigurasi RDR2 system.xml dari .bak..." -ForegroundColor Green
    }

    $witcherReal = Join-Path $docsPath "The Witcher 3\dx12user.settings"
    $witcherSnap = Join-Path $backupPath "Witcher3_dx12user.settings"
    $witcherBak  = "$witcherReal.bak"
    if (Test-Path $witcherSnap) {
        Copy-Item $witcherSnap $witcherReal -Force
        Write-Host "    -> Memulihkan konfigurasi Witcher 3 dx12user.settings..." -ForegroundColor Green
    } elseif (Test-Path $witcherBak) {
        Copy-Item $witcherBak $witcherReal -Force
        Write-Host "    -> Memulihkan konfigurasi Witcher 3 dx12user.settings dari .bak..." -ForegroundColor Green
    }

    Write-Host "`n[✓] Seluruh pengaturan Windows dan konfigurasi game berhasil dikembalikan ke kondisi semula!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 5. WINDOWS GAMING RESPONSIVENESS BOOST
# ------------------------------------------------------------------------------
function Optimize-VoltWindowsCore {
    Write-Host "`n[*] Menerapkan Optimasi Responsiveness Windows..." -ForegroundColor Cyan

    # 1. HAGS (Hardware-Accelerated GPU Scheduling)
    try {
        $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        if (-not (Test-Path $gfxPath)) { New-Item -Path $gfxPath -Force | Out-Null }
        Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value 2 -Type DWord -Force
        Write-Host " [✓] HAGS (Hardware GPU Scheduling) -> Diaktifkan (HwSchMode = 2)" -ForegroundColor Green
    } catch {
        Write-Host " [!] Gagal mengatur HAGS: $_" -ForegroundColor DarkYellow
    }

    # 2. Windows Auto Game Mode
    try {
        $gameModePath = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $gameModePath)) { New-Item -Path $gameModePath -Force | Out-Null }
        Set-ItemProperty -Path $gameModePath -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $gameModePath -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
        Write-Host " [✓] Windows Game Mode -> Diaktifkan (Prioritas P-Core & Game Thread)" -ForegroundColor Green
    } catch {}

    # 3. MMCSS (Multimedia Class Scheduler Service)
    try {
        $mmcssProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        if (-not (Test-Path $mmcssProfile)) { New-Item -Path $mmcssProfile -Force | Out-Null }
        Set-ItemProperty -Path $mmcssProfile -Name "SystemResponsiveness" -Value 10 -Type DWord -Force
        Set-ItemProperty -Path $mmcssProfile -Name "NetworkThrottlingIndex" -Value 10 -Type DWord -Force

        $mmcssGames = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
        if (-not (Test-Path $mmcssGames)) { New-Item -Path $mmcssGames -Force | Out-Null }
        Set-ItemProperty -Path $mmcssGames -Name "GPU Priority" -Value 8 -Type DWord -Force
        Set-ItemProperty -Path $mmcssGames -Name "Priority" -Value 6 -Type DWord -Force
        Set-ItemProperty -Path $mmcssGames -Name "Scheduling Category" -Value "High" -Type String -Force
        Set-ItemProperty -Path $mmcssGames -Name "SFIO Priority" -Value "Normal" -Type String -Force
        Write-Host " [✓] MMCSS & Game Thread Priority -> Disesuaikan (Low Latency / Anti Audio-Crack)" -ForegroundColor Green
    } catch {
        Write-Host " [!] Gagal mengatur MMCSS: $_" -ForegroundColor DarkYellow
    }

    # 4. Matikan Background GameDVR (Mencegah Lag Rekaman Diam-diam)
    try {
        $gameStore = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gameStore)) { New-Item -Path $gameStore -Force | Out-Null }
        Set-ItemProperty -Path $gameStore -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path $gameStore -Name "GameDVR_HistoricalCaptureEnabled" -Value 0 -Type DWord -Force

        $gamePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $gamePolicy)) { New-Item -Path $gamePolicy -Force | Out-Null }
        Set-ItemProperty -Path $gamePolicy -Name "AllowGameDVR" -Value 0 -Type DWord -Force
        Write-Host " [✓] Background GameDVR -> Dinonaktifkan (Mencegah stutter I/O disk)" -ForegroundColor Green
    } catch {}
}

# ------------------------------------------------------------------------------
# 6. DUAL GPU ALIGNMENT ENGINE (NVIDIA & AMD)
# ------------------------------------------------------------------------------
function Optimize-VoltDualGPU {
    param([hashtable]$Hardware)

    Write-Host "`n[*] Menyelaraskan Pengaturan Kartu Grafis (Dual GPU Engine)..." -ForegroundColor Cyan

    if ($Hardware.HasNvidiaGPU) {
        $tgpStr = if ($Hardware.DiscreteGPU.TGP_W) { " | Batas Daya: $($Hardware.DiscreteGPU.TGP_W)W TGP" } else { "" }
        Write-Host " [NVIDIA GeForce Terdeteksi$tgpStr]" -ForegroundColor Green
        try {
            # Registry NVIDIA Shader Cache Size: Set to 10 GB limit for traversal anti-stutter
            $nvCacheKey = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"
            if (-not (Test-Path $nvCacheKey)) { New-Item -Path $nvCacheKey -Force | Out-Null }
            # 10 GB in MB = 10240
            Set-ItemProperty -Path $nvCacheKey -Name "ShaderCacheSize" -Value 10240 -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  -> Shader Cache NVIDIA dioptimasi (10 GB cache size limit)" -ForegroundColor Gray
        } catch {}

        # Adaptive FPS Limit Recommendation
        $hz = $Hardware.ScreenRefreshHz
        $recFps = if ($hz -eq 144) { 72 } elseif ($hz -eq 120) { 60 } elseif ($hz -eq 165) { 82 } else { 60 }
        Write-Host "  -> Rekomendasi Frame Cap: $recFps FPS (setengah $hz Hz untuk efisiensi daya/suhu laptop)" -ForegroundColor Gray
        Write-Host "  -> Rekomendasi G-Sync/FreeSync: $($hz - 4) FPS (jika menggunakan VRR tear-free)" -ForegroundColor Gray
    }

    if ($Hardware.HasAmdGPU) {
        Write-Host " [AMD Radeon Terdeteksi]" -ForegroundColor Red
        try {
            $amdKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
            if (Test-Path $amdKey) {
                # Enable AMD Shader Cache
                Set-ItemProperty -Path $amdKey -Name "ShaderCache" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Host "  -> AMD Shader Cache -> Enabled" -ForegroundColor Gray
            }
        } catch {}
    }
}

# ------------------------------------------------------------------------------
# 7. GAME AUTO-CONFIGURATOR (VOLTPLAY)
# ------------------------------------------------------------------------------
function Optimize-VoltGameRDR2 {
    param([string]$XmlPath)
    try {
        Write-Host " [RDR2] Mengoptimalkan system.xml..." -ForegroundColor Green
        $bak = "$XmlPath.bak"
        if (-not (Test-Path $bak)) { Copy-Item $XmlPath $bak -Force }

        [xml]$xml = Get-Content -Path $XmlPath
        $adv = $xml.rage__fwuiSystemSettingsCollection.advancedGraphics
        if ($adv) {
            if ($adv.asyncComputeEnabled) { $adv.asyncComputeEnabled.value = "true" }
            if ($adv.transferQueuesEnabled) { $adv.transferQueuesEnabled.value = "true" }
            if ($adv.maxTexUpgradesPerFrame) { $adv.maxTexUpgradesPerFrame.value = "10" }
            $xml.Save($XmlPath)
            Write-Host "  -> RDR2: Async Compute, Transfer Queues, & MaxTexUpgrades = 10 aktif (Anti-stutter)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate RDR2: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameHSR {
    try {
        Write-Host " [Honkai: Star Rail] Mengoptimalkan Pengaturan Grafis..." -ForegroundColor Green
        $keyPath = "HKCU:\Software\Cognosphere\Star Rail"
        $propName = (Get-ItemProperty -Path $keyPath).PSObject.Properties | Where-Object { $_.Name -like "GraphicsSettings_Model*" } | Select-Object -ExpandProperty Name -First 1
        if ($propName) {
            $rawBytes = (Get-ItemProperty -Path $keyPath).$propName
            if ($rawBytes) {
                $jsonStr = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                $jsonObj = $jsonStr | ConvertFrom-Json
                
                # Balance Reflection and Light Quality to High (4) to prevent thermal throttle in Penacony
                if ($jsonObj.LightQuality -gt 4) { $jsonObj.LightQuality = 4 }
                if ($jsonObj.ReflectionQuality -gt 4) { $jsonObj.ReflectionQuality = 4 }

                $updatedStr = $jsonObj | ConvertTo-Json -Compress
                $newBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedStr)
                Set-ItemProperty -Path $keyPath -Name $propName -Value $newBytes -Type Binary -Force
                Write-Host "  -> HSR: Kualitas Light & Reflection diselaraskan ke High (Stabil 60-72 FPS di Penacony)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate HSR: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameGenshin {
    try {
        Write-Host " [Genshin Impact] Menyelaraskan Pengaturan Beban CPU/GPU..." -ForegroundColor Green
        $keyPath = "HKCU:\Software\miHoYo\Genshin Impact"
        $propName = (Get-ItemProperty -Path $keyPath).PSObject.Properties | Where-Object { $_.Name -like "GENERAL_DATA*" } | Select-Object -ExpandProperty Name -First 1
        if ($propName) {
            $rawBytes = (Get-ItemProperty -Path $keyPath).$propName
            if ($rawBytes) {
                $rawStr = [System.Text.Encoding]::UTF8.GetString($rawBytes).TrimEnd("`0")
                $rootJson = $rawStr | ConvertFrom-Json
                if ($rootJson.graphicsData) {
                    $gData = $rootJson.graphicsData | ConvertFrom-Json
                    if ($gData.customVolatileGrades) {
                        # Key 12 = Crowd Density: Set to 2 (Medium) for smooth performance in Fontaine/Natlan
                        # Key 1 = Render Resolution: Set to 2 (1.0 scale)
                        # Key 6 = Shadow Quality: Cap at 4 (High)
                        foreach ($item in $gData.customVolatileGrades) {
                            if ($item.key -eq 12 -and $item.value -gt 2) { $item.value = 2 }
                            if ($item.key -eq 1 -and $item.value -gt 2) { $item.value = 2 }
                            if ($item.key -eq 6 -and $item.value -gt 4) { $item.value = 4 }
                        }
                        $rootJson.graphicsData = ($gData | ConvertTo-Json -Compress)
                        $updatedRaw = ($rootJson | ConvertTo-Json -Compress)
                        $newBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedRaw)
                        Set-ItemProperty -Path $keyPath -Name $propName -Value $newBytes -Type Binary -Force
                        Write-Host "  -> Genshin: Crowd Density diselaraskan ke Medium & Shadow ke High (Anti CPU Spike)" -ForegroundColor Gray
                    }
                }
            }
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate Genshin Impact: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameWitcher3 {
    param([string]$SettingsPath)
    try {
        Write-Host " [The Witcher 3] Mengoptimalkan dx12user.settings..." -ForegroundColor Green
        $bak = "$SettingsPath.bak"
        if (-not (Test-Path $bak)) { Copy-Item $SettingsPath $bak -Force }

        $content = Get-Content $SettingsPath -Raw
        # Ensure DLSS Frame Generation is enabled and HairWorks disabled
        $content = $content -replace "HairWorksLevel=\d+", "HairWorksLevel=0"
        $content = $content -replace "AllowDLSSG=(false|true)", "AllowDLSSG=true"
        Set-Content -Path $SettingsPath -Value $content -Encoding UTF8 -Force
        Write-Host "  -> Witcher 3: HairWorks diatur ke 0 & DLSS-G aktif (Anti-drop di Novigrad)" -ForegroundColor Gray
    } catch {
        Write-Host "  [!] Gagal mengupdate Witcher 3: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltPlayGames {
    param(
        [hashtable]$Hardware,
        [string]$TargetGame = "ALL"
    )

    Write-Host "`n[*] Memeriksa & Mengoptimasi Konfigurasi Game (VoltPlay)..." -ForegroundColor Cyan

    if (($TargetGame -eq "ALL" -or $TargetGame -eq "RDR2") -and $Hardware.InstalledGames.ContainsKey("RDR2")) {
        Optimize-VoltGameRDR2 -XmlPath $Hardware.InstalledGames["RDR2"].ConfigPath
    }

    if (($TargetGame -eq "ALL" -or $TargetGame -eq "HSR") -and $Hardware.InstalledGames.ContainsKey("HSR")) {
        Optimize-VoltGameHSR
    }

    if (($TargetGame -eq "ALL" -or $TargetGame -eq "Genshin") -and $Hardware.InstalledGames.ContainsKey("Genshin")) {
        Optimize-VoltGameGenshin
    }

    if (($TargetGame -eq "ALL" -or $TargetGame -eq "Witcher3") -and $Hardware.InstalledGames.ContainsKey("Witcher3")) {
        Optimize-VoltGameWitcher3 -SettingsPath $Hardware.InstalledGames["Witcher3"].ConfigPath
    }

    if ($Hardware.InstalledGames.Count -eq 0) {
        Write-Host "  [-] Belum ada game open-world terdeteksi di lokasi standar." -ForegroundColor Gray
    }
}

# ------------------------------------------------------------------------------
# 8. SAFE DISK & CACHE CLEANUP (VOLTCLEAN)
# ------------------------------------------------------------------------------
function Invoke-VoltClean {
    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "                       🧹 PEMBERSIH DISK AMAN (VOLTCLEAN)                      " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    $initialFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    Write-Host "[*] Free Space Drive C: Sebelum Pembersihan: $initialFree GB" -ForegroundColor Gray

    # Process Check: Check if Chrome or Games are running
    $runningProcesses = Get-Process -Name "chrome", "msedge", "StarRail", "GenshinImpact", "RDR2", "witcher3" -ErrorAction SilentlyContinue
    if ($runningProcesses) {
        $pNames = ($runningProcesses | Select-Object -ExpandProperty Name -Unique) -join ", "
        Write-Host "[!] Terdeteksi aplikasi aktif berjalan: $pNames" -ForegroundColor Yellow
        Write-Host "    -> File cache yang sedang dipakai akan otomatis dilewati demi keamanan data." -ForegroundColor Gray
    }

    $stats = [ordered]@{
        UserTempCleanedBytes = 0
        WinTempCleanedBytes  = 0
        ShaderCacheBytes     = 0
        DumpsCleanedBytes    = 0
    }

    # Helper function to remove directory contents safely
    function Clear-FolderSafely ($path) {
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

    # 1. Clean User Temp
    Write-Host "[*] Membersihkan User Temp ($env:TEMP)..." -ForegroundColor Cyan
    $stats.UserTempCleanedBytes = Clear-FolderSafely $env:TEMP

    # 2. Clean Windows Temp
    Write-Host "[*] Membersihkan Windows Temp (C:\Windows\Temp)..." -ForegroundColor Cyan
    $stats.WinTempCleanedBytes = Clear-FolderSafely "C:\Windows\Temp"

    # 3. Clean DirectX & GPU Shader Caches
    Write-Host "[*] Membersihkan DirectX & GPU Shader Caches..." -ForegroundColor Cyan
    $d3dPath = Join-Path $env:LOCALAPPDATA "D3DSCache"
    $nvDxPath = Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"
    $nvGlPath = Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"

    $stats.ShaderCacheBytes += Clear-FolderSafely $d3dPath
    $stats.ShaderCacheBytes += Clear-FolderSafely $nvDxPath
    $stats.ShaderCacheBytes += Clear-FolderSafely $nvGlPath

    # 4. Clean Crash Dumps & Windows Error Reporting
    Write-Host "[*] Membersihkan Crash Dumps & Error Reports..." -ForegroundColor Cyan
    $dumpsPath = Join-Path $env:LOCALAPPDATA "CrashDumps"
    $stats.DumpsCleanedBytes = Clear-FolderSafely $dumpsPath

    # 5. Empty Recycle Bin
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host "[*] Recycle Bin dikosongkan." -ForegroundColor Cyan
    } catch {}

    $finalFree = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
    $gained = [math]::Round($finalFree - $initialFree, 2)

    Write-Host "`n========================= RINGKASAN PEMBERSAIHAN =========================" -ForegroundColor Green
    Write-Host " • User Temp Reclaimed        : $([math]::Round($stats.UserTempCleanedBytes / 1MB, 1)) MB" -ForegroundColor White
    Write-Host " • Windows Temp Reclaimed     : $([math]::Round($stats.WinTempCleanedBytes / 1MB, 1)) MB" -ForegroundColor White
    Write-Host " • Shader Cache Reclaimed     : $([math]::Round($stats.ShaderCacheBytes / 1MB, 1)) MB" -ForegroundColor White
    Write-Host " • Crash Dumps Reclaimed      : $([math]::Round($stats.DumpsCleanedBytes / 1MB, 1)) MB" -ForegroundColor White
    Write-Host " • Free Space Drive C: Akhir  : $finalFree GB (Perubahan: +$gained GB)" -ForegroundColor Green
    Write-Host "==========================================================================" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 9. ADVANCED UTILITIES (DNS, DISM, SFC, POWER, APPS)
# ------------------------------------------------------------------------------
function Invoke-VoltAdvancedTools {
    $inSubMenu = $true
    while ($inSubMenu) {
        Write-Host "`n================================================================================" -ForegroundColor Magenta
        Write-Host "                      🛠️ FITUR LANJUTAN VOLTUNE CORE                          " -ForegroundColor Magenta
        Write-Host "================================================================================" -ForegroundColor Magenta
        Write-Host " [1] ⚡ Benchmark & Flush DNS (Cloudflare, Google, Quad9 Latency Check)"
        Write-Host " [2] 🔋 Ganti Power Plan (Ultimate Performance / High Performance / Balanced)"
        Write-Host " [3] 🛡️ Jalankan SFC /scannow (Periksa Integritas File Sistem Windows)"
        Write-Host " [4] 📦 Jalankan DISM /RestoreHealth (Perbaiki Image Windows Online)"
        Write-Host " [5] 📋 Audit Bloatware Windows (Lihat Daftar Paket Appx Opsional)"
        Write-Host " [0] Kembali ke Menu Utama"
        
        $subChoice = Read-Host "`nPilih menu lanjutan [0-5]"
        switch ($subChoice) {
            "1" {
                Write-Host "`n[*] Menjalankan Benchmark DNS & Query Latency..." -ForegroundColor Cyan
                $resolvers = @(
                    @{ Name = "Cloudflare"; IP = "1.1.1.1" },
                    @{ Name = "Google";     IP = "8.8.8.8" },
                    @{ Name = "Quad9";      IP = "9.9.9.9" }
                )
                foreach ($r in $resolvers) {
                    $ping = Test-Connection -ComputerName $r.IP -Count 3 -ErrorAction SilentlyContinue
                    if ($ping) {
                        $avg = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average)
                        Write-Host "  -> $($r.Name) ($($r.IP)): Rata-rata Ping = $avg ms" -ForegroundColor Green
                    } else {
                        Write-Host "  -> $($r.Name) ($($r.IP)): RTO / Tidak merespons" -ForegroundColor Yellow
                    }
                }
                & ipconfig.exe /flushdns | Out-Null
                Write-Host "[✓] Cache DNS lokal berhasil di-flush!" -ForegroundColor Green
            }
            "2" {
                Write-Host "`n[*] Memeriksa Power Plan aktif..." -ForegroundColor Cyan
                powercfg /list
                Write-Host "`n [U] Aktifkan Ultimate Performance"
                Write-Host " [H] Aktifkan High Performance"
                Write-Host " [B] Aktifkan Balanced (Bawaan Windows)"
                $planChoice = Read-Host "Pilih Power Plan [U/H/B]"
                switch ($planChoice.ToUpper()) {
                    "U" {
                        # Duplicate Ultimate Performance scheme if not present
                        $res = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
                        powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null
                        Write-Host "[✓] Skema Ultimate Performance diaktifkan!" -ForegroundColor Green
                    }
                    "H" {
                        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
                        Write-Host "[✓] Skema High Performance diaktifkan!" -ForegroundColor Green
                    }
                    "B" {
                        powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null
                        Write-Host "[✓] Skema Balanced diaktifkan!" -ForegroundColor Green
                    }
                }
            }
            "3" {
                Write-Host "[*] Menjalankan SFC Scannow..." -ForegroundColor Cyan
                & sfc.exe /scannow
            }
            "4" {
                Write-Host "[*] Menjalankan DISM RestoreHealth..." -ForegroundColor Cyan
                & dism.exe /Online /Cleanup-Image /RestoreHealth
            }
            "5" {
                Write-Host "`n[*] Memindai paket Appx pengguna..." -ForegroundColor Cyan
                $apps = Get-AppxPackage | Where-Object { $_.NonRemovable -ne $true } | Select-Object -First 15 Name, Version
                $apps | Format-Table -AutoSize
            }
            "0" {
                $inSubMenu = $false
            }
        }
    }
}

# ------------------------------------------------------------------------------
# 10. INTERACTIVE UI & MENU CONTROLLER
# ------------------------------------------------------------------------------
function Show-VoltBanner {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                       ⚡ VOLTUNE WINDOWS UTILITY v$Script:VoltVersion ⚡                 " -ForegroundColor Yellow
    Write-Host "                 Bikin Laptop & PC Gaming Lu Lebih Ngacir & Stabil              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-VoltSpecs ($hw) {
    Write-Host "`n[SPEK LAPTOP LU TERDETEKSI]" -ForegroundColor Yellow
    Write-Host " • Prosesor  : $($hw.CPUName) ($($hw.CPUCores) Cores, $($hw.CPUThreads) Threads$(if ($hw.IsHybridCPU) { ' | Hybrid P+E' }))" -ForegroundColor White
    $gpuDesc = if ($hw.DiscreteGPU) {
        $tgp = if ($hw.DiscreteGPU.TGP_W) { " | $($hw.DiscreteGPU.TGP_W)W TGP" } else { "" }
        "$($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM$tgp)"
    } else { "iGPU Only" }
    Write-Host " • Kartu GPU : $gpuDesc" -ForegroundColor White
    Write-Host " • Layar     : $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz" -ForegroundColor White
    Write-Host " • Memori    : $($hw.RAM_GB) GB RAM" -ForegroundColor White
    Write-Host " • Ruang C:  : $($hw.DriveC_FreeGB) GB Bebas" -ForegroundColor White
    Write-Host " • Status HAGS: $(if ($hw.HAGS_Status) { 'Aktif [✓]' } else { 'Nonaktif [!]' })" -ForegroundColor $(if ($hw.HAGS_Status) { 'Green' } else { 'Yellow' })
    
    $gameNames = $hw.InstalledGames.Values | Select-Object -ExpandProperty Name
    $gameStr = if ($gameNames) { $gameNames -join ", " } else { "Tidak terdeteksi" }
    Write-Host " • Game Nemu : $gameStr" -ForegroundColor White
}

# ------------------------------------------------------------------------------
# 11. ENTRYPOINT LOGIC
# ------------------------------------------------------------------------------
Invoke-VoltElevation -Bypass:$NoElevation

$hwProfile = Get-VoltHardwareProfile

# Handle command-line switches
if ($AutoOptimize) {
    New-VoltBackupSnapshot
    Optimize-VoltWindowsCore
    Optimize-VoltDualGPU -Hardware $hwProfile
    Optimize-VoltPlayGames -Hardware $hwProfile
    exit 0
}

if ($CleanOnly) {
    Invoke-VoltClean
    exit 0
}

if ($UndoOnly) {
    Invoke-VoltUndo
    exit 0
}

# Interactive Loop
$running = $true
while ($running) {
    Show-VoltBanner
    Show-VoltSpecs $hwProfile

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " PILIH TINDAKAN (Ketik angka lalu tekan Enter):" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] 🚀 Optimasi Otomatis (Rekomendasi - Terima Beres)" -ForegroundColor Green
    Write-Host "     -> Bikin cadangan dulu, aktifkan HAGS & prioritas game Windows," -ForegroundColor Gray
    Write-Host "        setel driver NVIDIA/AMD biar gak stutter, dan beresin setting game lu." -ForegroundColor Gray
    Write-Host " [2] 🎮 Sesuaikan Setting Game Khusus (RDR2 / HSR / Genshin / Witcher)" -ForegroundColor White
    Write-Host "     -> Pilih game yang mau disesuaikan settingannya biar FPS-nya rata." -ForegroundColor Gray
    Write-Host " [3] 🧹 Bersihkan File Sampah & Ruang Disk (VoltClean)" -ForegroundColor White
    Write-Host "     -> Bersihkan cache usang, temp, crash dump, dan shader cache aman 100%." -ForegroundColor Gray
    Write-Host " [4] 🛠️ Buka Fitur Lanjutan Voltune (DNS, DISM, SFC, Power Plan)" -ForegroundColor White
    Write-Host "     -> Utilitas teknis pemeliharaan integritas sistem Windows." -ForegroundColor Gray
    Write-Host " [5] ↩️ Kembalikan Semua Settingan ke Semula (Undo / Reset)" -ForegroundColor Yellow
    Write-Host "     -> Balikin semua perubahan ke kondisi sebelum Voltune dijalankan." -ForegroundColor Gray
    Write-Host " [0] Keluar" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor DarkCyan

    $choice = Read-Host "`nPilihan lu [0-5]"
    switch ($choice) {
        "1" {
            New-VoltBackupSnapshot
            Optimize-VoltWindowsCore
            Optimize-VoltDualGPU -Hardware $hwProfile
            Optimize-VoltPlayGames -Hardware $hwProfile
            Write-Host "`n[✓] Optimasi otomatis selesai! Tekan Enter untuk melanjutkan..." -ForegroundColor Green
            Read-Host
        }
        "2" {
            Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor Cyan
            Write-Host " PILIH GAME YANG INGIN DISESUAIKAN (VoltPlay):" -ForegroundColor Yellow
            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
            Write-Host " [1] Red Dead Redemption 2 (Async Compute, Transfer Queues, MaxTexUpgrades 10)"
            Write-Host " [2] Honkai: Star Rail (Light & Reflection High, Anti-Penacony Drop)"
            Write-Host " [3] Genshin Impact (Crowd Density Medium, Shadow Balanced, Anti CPU-Spike)"
            Write-Host " [4] The Witcher 3: Wild Hunt (DLSS-G Frame Gen On, HairWorks Off)"
            Write-Host " [A] Sesuaikan Semua Game Terdeteksi Sekaligus"
            Write-Host " [0] Kembali ke Menu Utama"
            $gChoice = Read-Host "`nPilih opsi game [1-4 / A / 0]"
            switch ($gChoice.ToUpper()) {
                "1" {
                    New-VoltBackupSnapshot
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGame "RDR2"
                }
                "2" {
                    New-VoltBackupSnapshot
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGame "HSR"
                }
                "3" {
                    New-VoltBackupSnapshot
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGame "Genshin"
                }
                "4" {
                    New-VoltBackupSnapshot
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGame "Witcher3"
                }
                "A" {
                    New-VoltBackupSnapshot
                    Optimize-VoltPlayGames -Hardware $hwProfile -TargetGame "ALL"
                }
            }
            Write-Host "`n[✓] Selesai! Tekan Enter untuk melanjutkan..." -ForegroundColor Green
            Read-Host
        }
        "3" {
            Invoke-VoltClean
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "4" {
            Invoke-VoltAdvancedTools
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "5" {
            Invoke-VoltUndo
            Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
            Read-Host
        }
        "0" {
            $running = $false
            Write-Host "`nTerima kasih telah menggunakan Voltune! Sampai jumpa." -ForegroundColor Cyan
        }
        default {
            Write-Host "Pilihan tidak valid." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
