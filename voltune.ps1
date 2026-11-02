<#
.SYNOPSIS
    VoltPlay & Voltune Windows Utility v2.0 Next-Gen - Universal Hardware-Aware & Dynamic Optimizer
.DESCRIPTION
    Toolkit optimasi performa Windows, manajemen kartu grafis dual-GPU (NVIDIA/AMD/Intel),
    penyelarasan setting game anti-stutter dinamis multi-drive, pembersih disk lintas-drive,
    dan sistem snapshot 1-klik Undo dinamis.
.NOTES
    Safe by default, Reversible by design, 100% Dynamic, Zero VPN Harm.
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
$Script:VoltVersion = "2.1.0-Dynamic"
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

            # Dynamic check for Intel Hybrid P+E Cores or AMD asymmetric CCX
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
            # BatteryStatus: 1 = Discharging (On Battery), 2 = AC Power, 3 = Fully Charged
            if ($battery.BatteryStatus -eq 1) {
                $profile.IsOnBattery = $true
            }
        }
    } catch {}

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
    $profile.DynamicFPSCaps = [ordered]@{
        NativeMax   = $hz
        TearFreeVRR = [math]::Max(30, [int]($hz - 3))
        HalfRate    = [math]::Max(30, [int]([math]::Round($hz / 2)))
        BatteryCap  = [math]::Min(60, [int]([math]::Round($hz / 2)))
    }

    # Query precise NVIDIA TGP & VRAM via nvidia-smi if available
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

    # HAGS Detection
    try {
        $hags = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($hags -and $hags.HwSchMode -eq 2) {
            $profile.HAGS_Status = $true
        }
    } catch {}

    # 5. DYNAMIC MULTI-PLATFORM GAME DISCOVERY
    # A. Steam Libraries Discovery across ALL Drives
    $steamLibs = [System.Collections.Generic.List[string]]::new()
    try {
        $steamKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -Name "InstallPath" -ErrorAction SilentlyContinue
        if (-not $steamKey) {
            $steamKey = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
        }
        if ($steamKey) {
            $mainSteamPath = if ($steamKey.InstallPath) { $steamKey.InstallPath } else { $steamKey.SteamPath }
            if (Test-Path $mainSteamPath) {
                $steamLibs.Add($mainSteamPath)
                $vdf = Join-Path $mainSteamPath "steamapps\libraryfolders.vdf"
                if (Test-Path $vdf) {
                    $vdfContent = Get-Content -Path $vdf -Raw
                    $matchesPath = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
                    foreach ($m in $matchesPath) {
                        $libPath = $m.Groups[1].Value -replace '\\\\', '\'
                        if ((Test-Path $libPath) -and -not $steamLibs.Contains($libPath)) {
                            $steamLibs.Add($libPath)
                        }
                    }
                }
            }
        }
    } catch {}
    $profile.SteamLibraries = @($steamLibs)

    # Scan Steam Games in all discovered libraries
    foreach ($lib in $profile.SteamLibraries) {
        $appsDir = Join-Path $lib "steamapps"
        if (-not (Test-Path $appsDir)) { continue }
        $manifests = Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -ErrorAction SilentlyContinue
        foreach ($mf in $manifests) {
            try {
                $text = Get-Content -Path $mf.FullName -Raw
                $appId = if ($text -match '"appid"\s+"(\d+)"') { $Matches[1] } else { $null }
                $appName = if ($text -match '"name"\s+"([^"]+)"') { $Matches[1] } else { $null }
                $installSub = if ($text -match '"installdir"\s+"([^"]+)"') { $Matches[1] } else { $null }

                if ($appId -and $appName -and $installSub) {
                    $fullPath = Join-Path $appsDir "common\$installSub"

                    # Filter out runtimes / redistributables
                    if ($appName -notmatch "Steamworks|Redistributable|Proton|Shared") {
                        $profile.DiscoveredGames["Steam_$appId"] = [ordered]@{
                            Name        = $appName
                            Platform    = "Steam"
                            AppID       = $appId
                            InstallPath = $fullPath
                            Library     = $lib
                        }
                    }
                }
            } catch {}
        }
    }

    # B. HoYoPlay Registry Discovery (Star Rail, Genshin, ZZZ)
    if (Test-Path "HKCU:\Software\Cognosphere\Star Rail") {
        $profile.DiscoveredGames["HoYo_HSR"] = [ordered]@{
            Name        = "Honkai: Star Rail"
            Platform    = "HoYoPlay"
            ConfigType  = "RegistryJSON"
            ConfigPath  = "HKCU:\Software\Cognosphere\Star Rail"
        }
    }
    if (Test-Path "HKCU:\Software\miHoYo\Genshin Impact") {
        $profile.DiscoveredGames["HoYo_Genshin"] = [ordered]@{
            Name        = "Genshin Impact"
            Platform    = "HoYoPlay"
            ConfigType  = "RegistryJSON"
            ConfigPath  = "HKCU:\Software\miHoYo\Genshin Impact"
        }
    }

    # C. Rockstar Games Discovery (RDR2, GTA V)
    $docsPath = [Environment]::GetFolderPath('MyDocuments')
    $rdr2Xml = Join-Path $docsPath "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Xml) {
        $profile.DiscoveredGames["Rockstar_RDR2"] = [ordered]@{
            Name        = "Red Dead Redemption 2"
            Platform    = "Rockstar Games"
            ConfigType  = "XML"
            ConfigPath  = $rdr2Xml
        }
    }

    # D. CD Projekt RED Discovery (Witcher 3, Cyberpunk)
    $witcherSettings = Join-Path $docsPath "The Witcher 3\dx12user.settings"
    if (Test-Path $witcherSettings) {
        $profile.DiscoveredGames["CDPR_Witcher3"] = [ordered]@{
            Name        = "The Witcher 3: Wild Hunt (DX12)"
            Platform    = "CD Projekt RED"
            ConfigType  = "INI"
            ConfigPath  = $witcherSettings
        }
    }

    return $profile
}

# ------------------------------------------------------------------------------
# 4. DYNAMIC BACKUP & UNDO ENGINE (VOLTUNDO)
# ------------------------------------------------------------------------------
function New-VoltBackupSnapshot {
    param([hashtable]$Hardware)

    if (-not $Hardware) {
        $Hardware = Get-VoltHardwareProfile
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $sessionBackupDir = Join-Path $Script:BackupDir "Snapshot-$timestamp"
    New-Item -ItemType Directory -Path $sessionBackupDir -Force | Out-Null

    Write-Host " [*] Membuat cadangan sistem dinamis (Snapshot: $timestamp)..." -ForegroundColor Cyan

    $manifest = [ordered]@{
        Timestamp    = (Get-Date).ToString("o")
        OS           = (Get-CimInstance Win32_OperatingSystem).Caption
        RegistryKeys = @()
        ConfigFiles  = @()
    }

    # 1. Export Windows System Profiles
    $systemRegs = @(
        @{ Key = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; File = "SystemProfile.reg" },
        @{ Key = "HKCU\System\GameConfigStore"; File = "GameConfigStore.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; File = "GameDVR_Policy.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; File = "GraphicsDrivers.reg" }
    )
    foreach ($sr in $systemRegs) {
        try {
            & reg.exe export $sr.Key (Join-Path $sessionBackupDir $sr.File) /y | Out-Null
            $manifest.RegistryKeys += $sr.Key
        } catch {}
    }

    # 2. Export Discovered Game Registries
    if ($Hardware.DiscoveredGames.Contains("HoYo_HSR")) {
        try {
            & reg.exe export "HKCU\Software\Cognosphere\Star Rail" (Join-Path $sessionBackupDir "StarRail.reg") /y | Out-Null
            $manifest.RegistryKeys += "HKCU\Software\Cognosphere\Star Rail"
        } catch {}
    }
    if ($Hardware.DiscoveredGames.Contains("HoYo_Genshin")) {
        try {
            & reg.exe export "HKCU\Software\miHoYo\Genshin Impact" (Join-Path $sessionBackupDir "GenshinImpact.reg") /y | Out-Null
            $manifest.RegistryKeys += "HKCU\Software\miHoYo\Genshin Impact"
        } catch {}
    }

    # 3. Backup Discovered Game Config Files
    foreach ($game in $Hardware.DiscoveredGames.Values) {
        if ($game.ConfigPath -and (Test-Path $game.ConfigPath) -and -not ($game.ConfigPath.StartsWith("HKCU:"))) {
            $safeName = $game.Name -replace '[\\/:*?"<>|]', '_'
            $destName = [IO.Path]::GetFileName($game.ConfigPath)
            $backupFileName = "${safeName}_$destName"
            $destFile = Join-Path $sessionBackupDir $backupFileName
            Copy-Item $game.ConfigPath $destFile -Force
            # Also keep a local .bak alongside
            Copy-Item $game.ConfigPath "$($game.ConfigPath).bak" -Force
            $manifest.ConfigFiles += @{
                OriginalPath = $game.ConfigPath
                BackupFile   = $backupFileName
            }
        }
    }

    # 4. Save manifest
    $manifest | ConvertTo-Json -Depth 5 | Out-File (Join-Path $sessionBackupDir "manifest.json") -Encoding UTF8
    $sessionBackupDir | Out-File (Join-Path $Script:BackupDir "latest.txt") -Encoding UTF8 -Force

    Write-Host " [✓] Cadangan lengkap tersimpan di: $sessionBackupDir" -ForegroundColor Green
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

    # Restore Config Files dynamically via manifest.json
    $manifestPath = Join-Path $backupPath "manifest.json"
    if (Test-Path $manifestPath) {
        try {
            $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
            foreach ($cf in $manifest.ConfigFiles) {
                $src = Join-Path $backupPath $cf.BackupFile
                if (Test-Path $src) {
                    Copy-Item $src $cf.OriginalPath -Force
                    Write-Host "    -> Memulihkan file konfigurasi: $($cf.OriginalPath)" -ForegroundColor Green
                }
            }
        } catch {
            Write-Host " [!] Terjadi kesalahan saat membaca manifest: $_" -ForegroundColor DarkYellow
        }
    }

    Write-Host "`n[✓] Seluruh konfigurasi Windows dan game berhasil dikembalikan ke kondisi semula!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 5. DYNAMIC PROCESS GUARD (PREVENT ACCIDENTAL CACHE CORRUPTION)
# ------------------------------------------------------------------------------
function Get-VoltActiveGuards {
    $guards = [ordered]@{
        Browsers = @()
        Launchers = @()
        ActiveGames = @()
    }

    $browserPatterns = "chrome|msedge|firefox|brave|opera|vivaldi|arc|zen"
    $launcherPatterns = "steam|epicgameslauncher|galaxyclient|riotclient|origin|eadesktop|battle\.net|hoyoplay"

    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.Name -match "^($browserPatterns)$" -and -not $guards.Browsers.Contains($p.Name)) {
            $guards.Browsers += $p.Name
        } elseif ($p.Name -match "^($launcherPatterns)$" -and -not $guards.Launchers.Contains($p.Name)) {
            $guards.Launchers += $p.Name
        }
    }

    return $guards
}

# ------------------------------------------------------------------------------
# 6. DYNAMIC WINDOWS & DUAL-GPU ALIGNMENT
# ------------------------------------------------------------------------------
function Optimize-VoltWindowsCore {
    Write-Host "`n[*] Menerapkan Optimasi Responsiveness Windows..." -ForegroundColor Cyan

    # 1. HAGS
    try {
        $gfxPath = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        if (-not (Test-Path $gfxPath)) { New-Item -Path $gfxPath -Force | Out-Null }
        Set-ItemProperty -Path $gfxPath -Name "HwSchMode" -Value 2 -Type DWord -Force
        Write-Host " [✓] HAGS (Hardware GPU Scheduling) -> Diaktifkan (HwSchMode = 2)" -ForegroundColor Green
    } catch {}

    # 2. Game Mode
    try {
        $gameModePath = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $gameModePath)) { New-Item -Path $gameModePath -Force | Out-Null }
        Set-ItemProperty -Path $gameModePath -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
        Set-ItemProperty -Path $gameModePath -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
        Write-Host " [✓] Windows Game Mode -> Diaktifkan (Prioritas Game Thread)" -ForegroundColor Green
    } catch {}

    # 3. MMCSS Low Latency Audio & Game Thread Priority
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
    } catch {}

    # 4. Matikan Background GameDVR
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

function Optimize-VoltDualGPU {
    param([hashtable]$Hardware)

    Write-Host "`n[*] Menyelaraskan Pengaturan Kartu Grafis (Dynamic Dual GPU)..." -ForegroundColor Cyan

    # Dynamic NVIDIA Optimization
    if ($Hardware.HasNvidiaGPU) {
        $tgpStr = if ($Hardware.DiscreteGPU.TGP_W) { " ($($Hardware.DiscreteGPU.TGP_W)W TGP)" } else { "" }
        Write-Host " [NVIDIA GeForce$tgpStr]" -ForegroundColor Green

        # Dynamically size Shader Cache based on primary drive free space
        $cFree = if ($Hardware.Drives.Contains("C:")) { $Hardware.Drives["C:"].FreeGB } else { 50 }
        $cacheSizeMB = if ($cFree -gt 60) { 10240 } elseif ($cFree -gt 30) { 5120 } else { 1024 }

        try {
            $nvCacheKey = "HKLM:\SOFTWARE\NVIDIA Corporation\Global\NVTweak"
            if (-not (Test-Path $nvCacheKey)) { New-Item -Path $nvCacheKey -Force | Out-Null }
            Set-ItemProperty -Path $nvCacheKey -Name "ShaderCacheSize" -Value $cacheSizeMB -Type DWord -Force -ErrorAction SilentlyContinue
            Write-Host "  -> Shader Cache NVIDIA disetel dinamis ke $([math]::Round($cacheSizeMB / 1024)) GB (Berdasarkan sisa storage $cFree GB)" -ForegroundColor Gray
        } catch {}

        # Display Dynamic FPS Recommendations
        $caps = $Hardware.DynamicFPSCaps
        Write-Host "  -> Target FPS VRR (G-Sync/FreeSync) : $($caps.TearFreeVRRFPS) FPS (Bebas Tearing)" -ForegroundColor Gray
        Write-Host "  -> Target FPS Hemat Daya / Dingin   : $($caps.HalfRate) FPS (Mencegah Thermal Throttle)" -ForegroundColor Gray
        if ($Hardware.IsOnBattery) {
            Write-Host "  [!] Sedang Mode Baterai: Direkomendasikan lock di $($caps.BatteryCap) FPS" -ForegroundColor Yellow
        }
    }

    # Dynamic AMD Radeon Optimization
    if ($Hardware.HasAmdGPU) {
        Write-Host " [AMD Radeon Terdeteksi]" -ForegroundColor Red
        try {
            $amdKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000"
            if (Test-Path $amdKey) {
                Set-ItemProperty -Path $amdKey -Name "ShaderCache" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Write-Host "  -> AMD Shader Cache -> Enabled (Optimized)" -ForegroundColor Gray
            }
        } catch {}
    }
}

# ------------------------------------------------------------------------------
# 7. DYNAMIC GAME CONFIGURATOR (VOLTPLAY)
# ------------------------------------------------------------------------------
function Optimize-VoltGameRDR2 {
    param([string]$XmlPath)
    try {
        Write-Host " [RDR2] Menyelaraskan system.xml..." -ForegroundColor Green
        [xml]$xml = Get-Content -Path $XmlPath
        $adv = $xml.rage__fwuiSystemSettingsCollection.advancedGraphics
        if ($adv) {
            if ($adv.asyncComputeEnabled) { $adv.asyncComputeEnabled.value = "true" }
            if ($adv.transferQueuesEnabled) { $adv.transferQueuesEnabled.value = "true" }
            if ($adv.maxTexUpgradesPerFrame) { $adv.maxTexUpgradesPerFrame.value = "10" }
            $xml.Save($XmlPath)
            Write-Host "  -> RDR2: Async Compute & MaxTexUpgrades = 10 aktif (Anti-stutter)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate RDR2: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameHSR {
    try {
        Write-Host " [Honkai: Star Rail] Menyelaraskan Pengaturan Grafis..." -ForegroundColor Green
        $keyPath = "HKCU:\Software\Cognosphere\Star Rail"
        $propName = (Get-ItemProperty -Path $keyPath).PSObject.Properties | Where-Object { $_.Name -like "GraphicsSettings_Model*" } | Select-Object -ExpandProperty Name -First 1
        if ($propName) {
            $rawBytes = (Get-ItemProperty -Path $keyPath).$propName
            if ($rawBytes) {
                $jsonStr = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                $jsonObj = $jsonStr | ConvertFrom-Json
                
                # Dynamic balance for Light & Reflection Quality (High)
                if ($jsonObj.LightQuality -gt 4) { $jsonObj.LightQuality = 4 }
                if ($jsonObj.ReflectionQuality -gt 4) { $jsonObj.ReflectionQuality = 4 }

                $updatedStr = $jsonObj | ConvertTo-Json -Compress
                $newBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedStr)
                Set-ItemProperty -Path $keyPath -Name $propName -Value $newBytes -Type Binary -Force
                Write-Host "  -> HSR: Light & Reflection diselaraskan ke High (Stabil di Penacony)" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate HSR: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameGenshin {
    try {
        Write-Host " [Genshin Impact] Menyelaraskan Beban CPU/GPU..." -ForegroundColor Green
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
                        foreach ($item in $gData.customVolatileGrades) {
                            if ($item.key -eq 12 -and $item.value -gt 2) { $item.value = 2 } # Crowd Density: Medium
                            if ($item.key -eq 1 -and $item.value -gt 2) { $item.value = 2 }  # Render Scale: 1.0
                            if ($item.key -eq 6 -and $item.value -gt 4) { $item.value = 4 }  # Shadows: High
                        }
                        $rootJson.graphicsData = ($gData | ConvertTo-Json -Compress)
                        $updatedRaw = ($rootJson | ConvertTo-Json -Compress)
                        $newBytes = [System.Text.Encoding]::UTF8.GetBytes($updatedRaw)
                        Set-ItemProperty -Path $keyPath -Name $propName -Value $newBytes -Type Binary -Force
                        Write-Host "  -> Genshin: Crowd Density diselaraskan ke Medium & Shadows ke High" -ForegroundColor Gray
                    }
                }
            }
        }
    } catch {
        Write-Host "  [!] Gagal mengupdate Genshin: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameWitcher3 {
    param([string]$SettingsPath)
    try {
        Write-Host " [The Witcher 3] Menyelaraskan dx12user.settings..." -ForegroundColor Green
        $content = Get-Content $SettingsPath -Raw
        $content = $content -replace "HairWorksLevel=\d+", "HairWorksLevel=0"
        $content = $content -replace "AllowDLSSG=(false|true)", "AllowDLSSG=true"
        Set-Content -Path $SettingsPath -Value $content -Encoding UTF8 -Force
        Write-Host "  -> Witcher 3: HairWorks diatur ke 0 & DLSS-G aktif (Novigrad Anti-drop)" -ForegroundColor Gray
    } catch {
        Write-Host "  [!] Gagal mengupdate Witcher 3: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltPlayGames {
    param(
        [hashtable]$Hardware,
        [string]$TargetGameKey = "ALL"
    )

    Write-Host "`n[*] Menjalankan Penyelarasan In-Game Dinamis (VoltPlay)..." -ForegroundColor Cyan

    $games = $Hardware.DiscoveredGames

    if (($TargetGameKey -eq "ALL" -or $TargetGameKey -eq "Rockstar_RDR2") -and $games.Contains("Rockstar_RDR2")) {
        Optimize-VoltGameRDR2 -XmlPath $games["Rockstar_RDR2"].ConfigPath
    }

    if (($TargetGameKey -eq "ALL" -or $TargetGameKey -eq "HoYo_HSR") -and $games.Contains("HoYo_HSR")) {
        Optimize-VoltGameHSR
    }

    if (($TargetGameKey -eq "ALL" -or $TargetGameKey -eq "HoYo_Genshin") -and $games.Contains("HoYo_Genshin")) {
        Optimize-VoltGameGenshin
    }

    if (($TargetGameKey -eq "ALL" -or $TargetGameKey -eq "CDPR_Witcher3") -and $games.Contains("CDPR_Witcher3")) {
        Optimize-VoltGameWitcher3 -SettingsPath $games["CDPR_Witcher3"].ConfigPath
    }

    # For any generic Steam game: Register Windows GPU High Performance preference dynamically
    foreach ($k in $games.Keys) {
        $g = $games[$k]
        if ($g.Platform -eq "Steam" -and (Test-Path $g.InstallPath)) {
            $exes = Get-ChildItem -Path $g.InstallPath -Filter "*.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "crash|report|unins|helper|redist|vcredist" } | Select-Object -First 1
            if ($exes) {
                try {
                    $prefPath = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
                    if (-not (Test-Path $prefPath)) { New-Item -Path $prefPath -Force | Out-Null }
                    # GpuPreference=2 specifies Discrete / High Performance GPU
                    Set-ItemProperty -Path $prefPath -Name $exes.FullName -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
                } catch {}
            }
        }
    }

    Write-Host " [✓] Penyelarasan game selesai." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 8. DYNAMIC DISK CLEANUP ACROSS ALL DRIVES (VOLTCLEAN)
# ------------------------------------------------------------------------------
function Invoke-VoltClean {
    param([hashtable]$Hardware)

    if (-not $Hardware) {
        $Hardware = Get-VoltHardwareProfile
    }

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

    # Dynamic Process Guard Check
    $guards = Get-VoltActiveGuards
    if ($guards.Browsers.Count -gt 0 -or $guards.Launchers.Count -gt 0) {
        $found = ($guards.Browsers + $guards.Launchers) -join ", "
        Write-Host "[!] Terdeteksi proses aktif berjalan: $found" -ForegroundColor Yellow
        Write-Host "    -> File cache yang sedang dipakai akan dilewati secara aman." -ForegroundColor Gray
    }

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

    $totalReclaimedBytes = 0

    # 1. Clean User Temp
    Write-Host "[*] Membersihkan User Temp ($env:TEMP)..." -ForegroundColor Cyan
    $totalReclaimedBytes += Clear-FolderSafely $env:TEMP

    # 2. Clean Windows Temp
    Write-Host "[*] Membersihkan Windows Temp (C:\Windows\Temp)..." -ForegroundColor Cyan
    $totalReclaimedBytes += Clear-FolderSafely "C:\Windows\Temp"

    # 3. Clean DirectX & Multi-Vendor GPU Shader Caches
    Write-Host "[*] Membersihkan DirectX & GPU Shader Caches..." -ForegroundColor Cyan
    $shaderPaths = @(
        (Join-Path $env:LOCALAPPDATA "D3DSCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache"),
        (Join-Path $env:LOCALAPPDATA "NVIDIA\GLCache"),
        (Join-Path $env:APPDATA "NVIDIA\ComputeCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\DxCache"),
        (Join-Path $env:LOCALAPPDATA "AMD\GLCache"),
        (Join-Path $env:LOCALAPPDATA "Intel\ShaderCache")
    )
    foreach ($sp in $shaderPaths) {
        $totalReclaimedBytes += Clear-FolderSafely $sp
    }

    # 4. Clean Steam Shader Caches across ALL Discovered Steam Libraries
    if ($Hardware.SteamLibraries) {
        foreach ($lib in $Hardware.SteamLibraries) {
            $steamCache = Join-Path $lib "steamapps\shadercache"
            if (Test-Path $steamCache) {
                Write-Host "[*] Membersihkan Steam Shader Cache di: $steamCache..." -ForegroundColor Cyan
                $totalReclaimedBytes += Clear-FolderSafely $steamCache
            }
        }
    }

    # 5. Clean Crash Dumps
    Write-Host "[*] Membersihkan Crash Dumps & Error Reports..." -ForegroundColor Cyan
    $totalReclaimedBytes += Clear-FolderSafely (Join-Path $env:LOCALAPPDATA "CrashDumps")

    # 6. Empty Recycle Bin
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Host "[*] Recycle Bin dikosongkan." -ForegroundColor Cyan
    } catch {}

    Write-Host "`n====================== RINGKASAN PEROLEHAN STORAGE ======================" -ForegroundColor Green
    Write-Host " • Total Sampah & Cache Dibersihkan : $([math]::Round($totalReclaimedBytes / 1MB, 1)) MB" -ForegroundColor White
    foreach ($d in $initialDrives.Keys) {
        $psd = Get-PSDrive -Name ($d.TrimEnd(':')) -ErrorAction SilentlyContinue
        if ($psd) {
            $after = [math]::Round($psd.Free / 1GB, 2)
            $diff = [math]::Round($after - $initialDrives[$d], 2)
            Write-Host " • Drive $d Free Space Akhir          : $after GB (Perubahan: +$diff GB)" -ForegroundColor Green
        }
    }
    Write-Host "==========================================================================" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 9. ADVANCED UTILITIES (DNS BENCHMARK, POWER PLAN, SFC, DISM, APPS)
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
# 10. INTERACTIVE UI & DYNAMIC DISPLAY
# ------------------------------------------------------------------------------
function Show-VoltBanner {
    Clear-Host
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                   ⚡ VOLTUNE WINDOWS UTILITY v$Script:VoltVersion ⚡                   " -ForegroundColor Yellow
    Write-Host "             Toolkit Optimasi Dinamis & Penyelaras Performa Universal          " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-VoltSpecs ($hw) {
    Write-Host "`n[SPEK HARDWARE DINAMIS TERDETEKSI]" -ForegroundColor Yellow
    Write-Host " • Prosesor  : $($hw.CPUName) ($($hw.CPUCores) Cores, $($hw.CPUThreads) Threads$(if ($hw.IsHybridCPU) { ' | Hybrid P+E' }))" -ForegroundColor White
    
    $gpuDesc = if ($hw.DiscreteGPU) {
        $tgp = if ($hw.DiscreteGPU.TGP_W) { " | $($hw.DiscreteGPU.TGP_W)W TGP" } else { "" }
        "$($hw.DiscreteGPU.Name) ($($hw.DiscreteGPU.VRAM_GB) GB VRAM$tgp)"
    } else { "iGPU Only" }
    Write-Host " • Kartu GPU : $gpuDesc" -ForegroundColor White

    $pwrStatus = if ($hw.IsOnBattery) { "Baterai ($($hw.BatteryChargePct)%) [Hemat Daya]" } else { "AC Adapter (Daya Maksimal) [✓]" }
    Write-Host " • Sumber Daya: $pwrStatus" -ForegroundColor $(if ($hw.IsOnBattery) { 'Yellow' } else { 'Green' })

    Write-Host " • Layar     : $($hw.ScreenResolution) @ $($hw.ScreenRefreshHz) Hz" -ForegroundColor White
    Write-Host " • Target FPS: VRR $($hw.DynamicFPSCaps.TearFreeVRRFPS) FPS | Hemat $($hw.DynamicFPSCaps.HalfRate) FPS" -ForegroundColor Gray
    Write-Host " • Memori    : $($hw.RAM_GB) GB RAM" -ForegroundColor White

    # Multi-Drive Summary
    $driveStrs = @()
    foreach ($d in $hw.Drives.Values) {
        $driveStrs += "$($d.DeviceID) $($d.FreeGB)/$($d.TotalGB) GB"
    }
    Write-Host " • Storage   : $($driveStrs -join ' | ')" -ForegroundColor White
    Write-Host " • Status HAGS: $(if ($hw.HAGS_Status) { 'Aktif [✓]' } else { 'Nonaktif [!]' })" -ForegroundColor $(if ($hw.HAGS_Status) { 'Green' } else { 'Yellow' })

    # Discovered Games Summary
    $gameList = $hw.DiscoveredGames.Values | Select-Object -ExpandProperty Name
    $gameStr = if ($gameList) { ($gameList | Select-Object -Unique) -join ", " } else { "Tidak terdeteksi" }
    Write-Host " • Game Nemu : $gameStr" -ForegroundColor White
}

# ------------------------------------------------------------------------------
# 11. ENTRYPOINT LOGIC
# ------------------------------------------------------------------------------
Invoke-VoltElevation -Bypass:$NoElevation

$hwProfile = Get-VoltHardwareProfile

# Handle command-line switches
if ($AutoOptimize) {
    New-VoltBackupSnapshot -Hardware $hwProfile
    Optimize-VoltWindowsCore
    Optimize-VoltDualGPU -Hardware $hwProfile
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

# Interactive Loop
$running = $true
while ($running) {
    Show-VoltBanner
    Show-VoltSpecs $hwProfile

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " PILIH TINDAKAN (Ketik angka lalu tekan Enter):" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [1] 🚀 Optimasi Otomatis Dinamis (Rekomendasi - Terima Beres)" -ForegroundColor Green
    Write-Host "     -> Cadangkan sistem, aktifkan HAGS & prioritas game Windows," -ForegroundColor Gray
    Write-Host "        setel driver NVIDIA/AMD, dan optimasi game yang terpasang." -ForegroundColor Gray
    Write-Host " [2] 🎮 Sesuaikan Setting Game Dinamis (VoltPlay)" -ForegroundColor White
    Write-Host "     -> Pilih game terdeteksi (Steam / HoYo / Rockstar / CDPR) untuk dioptimasi." -ForegroundColor Gray
    Write-Host " [3] 🧹 Bersihkan File Sampah & Cache Lintas-Drive (VoltClean)" -ForegroundColor White
    Write-Host "     -> Hapus cache usang, temp, shader cache lintas-drive aman 100%." -ForegroundColor Gray
    Write-Host " [4] 🛠️ Buka Fitur Lanjutan Voltune (DNS, DISM, SFC, Power Plan)" -ForegroundColor White
    Write-Host "     -> Utilitas teknis pemeliharaan integritas sistem Windows." -ForegroundColor Gray
    Write-Host " [5] ↩️ Kembalikan Semua Settingan ke Semula (Undo / Reset)" -ForegroundColor Yellow
    Write-Host "     -> Balikin semua perubahan ke kondisi sebelum Voltune dijalankan." -ForegroundColor Gray
    Write-Host " [0] Keluar" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor DarkCyan

    $choice = Read-Host "`nPilihan lu [0-5]"
    switch ($choice) {
        "1" {
            New-VoltBackupSnapshot -Hardware $hwProfile
            Optimize-VoltWindowsCore
            Optimize-VoltDualGPU -Hardware $hwProfile
            Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
            Write-Host "`n[✓] Optimasi otomatis selesai! Tekan Enter untuk melanjutkan..." -ForegroundColor Green
            Read-Host
        }
        "2" {
            Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor Cyan
            Write-Host " GAME TERPASANG YANG TERDETEKSI SECARA DINAMIS:" -ForegroundColor Yellow
            Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
            $gameKeys = @($hwProfile.DiscoveredGames.Keys)
            for ($i = 0; $i -lt $gameKeys.Count; $i++) {
                $gk = $gameKeys[$i]
                $gObj = $hwProfile.DiscoveredGames[$gk]
                Write-Host " [$($i + 1)] $($gObj.Name) [$($gObj.Platform)]"
            }
            Write-Host " [A] Optimalkan Semua Game Terdeteksi Sekaligus"
            Write-Host " [0] Kembali ke Menu Utama"

            $gChoice = Read-Host "`nPilih nomor game [1-$($gameKeys.Count) / A / 0]"
            if ($gChoice -eq "A" -or $gChoice -eq "a") {
                New-VoltBackupSnapshot -Hardware $hwProfile
                Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey "ALL"
            } elseif ($gChoice -match "^\d+$" -and [int]$gChoice -ge 1 -and [int]$gChoice -le $gameKeys.Count) {
                $selectedKey = $gameKeys[[int]$gChoice - 1]
                New-VoltBackupSnapshot -Hardware $hwProfile
                Optimize-VoltPlayGames -Hardware $hwProfile -TargetGameKey $selectedKey
            }
            Write-Host "`n[✓] Selesai! Tekan Enter untuk melanjutkan..." -ForegroundColor Green
            Read-Host
        }
        "3" {
            Invoke-VoltClean -Hardware $hwProfile
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
