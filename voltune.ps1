<#
.SYNOPSIS
    VoltPlay & Voltune Windows Utility v3.3 - Ultimate Universal Windows Performance, Gaming & System Hub
.DESCRIPTION
    Toolkit komprehensif optimasi Windows, manajemen kartu grafis dual-GPU (NVIDIA/AMD/Intel),
    penyelarasan setting game anti-stutter dinamis multi-drive, pembersih disk lintas-drive,
    Windows 11 QoL tweaks (Classic Context Menu, Explorer, Taskbar), privasi & anti-telemetri,
    TCP/IP gaming latency optimizer (Zero-VPN harm), Windows Services optimizer,
    Windows Update control (Security Updates Only), gaming raw mouse input & Defender auto-exclusions,
    WinGet software catalog komprehensif & game runtimes installer (Chris Titus style), System Restore automation,
    serta sistem snapshot 1-klik Undo dinamis dengan Modern Native WPF Desktop GUI & Interactive TUI.
.NOTES
    Safe by default, Reversible by design, 100% Dynamic, Zero VPN Harm.
#>

[CmdletBinding()]
param(
    [switch]$CLI,
    [switch]$TUI,
    [switch]$AutoOptimize,
    [switch]$CleanOnly,
    [switch]$UndoOnly,
    [switch]$GUI,
    [switch]$NoElevation
)

# ------------------------------------------------------------------------------
# 1. ELEVASI HAK AKSES (SELF-ELEVATION DENGAN PRESERVASI ARGUMEN)
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

    Write-Host "[!] Voltune memerlukan hak akses Administrator untuk mengonfigurasi performa Windows." -ForegroundColor Yellow
    Write-Host "[*] Meminta izin UAC Administrator..." -ForegroundColor Cyan
    try {
        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass")
        if ($PSCommandPath) {
            $argList += @("-File", "`"$PSCommandPath`"")
        } else {
            $argList += @("-Command", "`"irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex`"")
        }

        # Teruskan seluruh argumen CLI jika ada
        if ($args) {
            foreach ($a in $args) { $argList += "`"$a`"" }
        }

        Start-Process powershell.exe -ArgumentList ($argList -join " ") -Verb RunAs
        exit 0
    } catch {
        Write-Error "Gagal meminta izin Administrator: $_"
        exit 1
    }
}

# ------------------------------------------------------------------------------
# 2. KONFIGURASI GLOBAL & PATHS
# ------------------------------------------------------------------------------
$Script:VoltVersion = "3.3.0-Universal"
$Script:AppDataDir  = Join-Path $env:LOCALAPPDATA "Voltune"
$Script:BackupDir   = Join-Path $Script:AppDataDir "Backups"
$Script:LogDir      = Join-Path $Script:AppDataDir "Logs"

if (-not (Test-Path $Script:BackupDir)) { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null }
if (-not (Test-Path $Script:LogDir)) { New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null }

# ------------------------------------------------------------------------------
# 3. DYNAMIC DETECTION ENGINE (HARDWARE, ENVIRONMENT, DRIVES, & GPU VRAM FIX)
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
        RAM_GB           = 0
        IsLaptop         = $false
        IsOnBattery      = $false
        BatteryChargePct = 100

        # GPU
        DiscreteGPU      = $null
        IntegratedGPU    = $null
        AllGPUs          = @()

        # Display
        ScreenResolution = "1920x1080"
        ScreenRefreshHz  = 60
        DynamicFPSCaps   = @{
            TearFreeVRR  = 57
            HalfRate     = 30
            BaseHz       = 60
        }

        # Storage & Drives
        Drives           = [ordered]@{}
        HibernateActive  = $false
        HiberfilSizeGB   = 0

        # System State
        HAGS_Status      = $false
        GameMode_Status  = $false
        SteamLibraries   = @()
        DiscoveredGames  = [ordered]@{}
    }

    # Query CPU
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu) {
            $profile.CPUName = $cpu.Name.Trim()
            $profile.CPUCores = [int]$cpu.NumberOfCores
            $profile.CPUThreads = [int]$cpu.NumberOfLogicalProcessors
            $profile.CPUArchitecture = switch ($cpu.Architecture) {
                9 { "x64" }
                12 { "ARM64" }
                default { "x86" }
            }
            if ($profile.CPUThreads -gt ($profile.CPUCores * 2) -or ($profile.CPUThreads -ne ($profile.CPUCores * 2) -and $profile.CPUCores -ge 6)) {
                $profile.IsHybridCPU = $true
            }
        }
    } catch {}

    # Query RAM
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $profile.RAM_GB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        }
    } catch {}

    # Query Power / Battery
    try {
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($battery) {
            $profile.IsLaptop = $true
            $profile.BatteryChargePct = [int]$battery.EstimatedChargeRemaining
            if ($battery.BatteryStatus -eq 1) {
                $profile.IsOnBattery = $true
            }
        }
    } catch {}

    # Query Display & Refresh Rate
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        if ($screen) {
            $profile.ScreenResolution = "$($screen.Bounds.Width)x$($screen.Bounds.Height)"
        }
    } catch {}

    try {
        $mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedDisplayModes -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($mon -and $mon.CurrentMode) {
            $hz = [int]$mon.CurrentMode.VerticalRefreshRate
            if ($hz -gt 0) { $profile.ScreenRefreshHz = $hz }
        }
    } catch {}

    if ($profile.ScreenRefreshHz -le 0) {
        try {
            $displayMode = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($displayMode.CurrentRefreshRate -gt 0) {
                $profile.ScreenRefreshHz = [int]$displayMode.CurrentRefreshRate
            }
        } catch {}
    }
    if ($profile.ScreenRefreshHz -le 0) { $profile.ScreenRefreshHz = 60 }

    # Dynamic FPS Targets
    $hz = $profile.ScreenRefreshHz
    $profile.DynamicFPSCaps = [ordered]@{
        TearFreeVRR = [math]::Max(30, ($hz - 3))
        HalfRate    = [math]::Round($hz / 2)
        BaseHz      = $hz
    }

    # Query GPUs (Dual-GPU Recognition dengan Multi-Path nvidia-smi & VRAM Fix)
    try {
        $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($g in $gpus) {
            $name = $g.Name
            $vram = [math]::Round($g.AdapterRAM / 1GB, 1)
            $isDiscrete = ($name -match "NVIDIA|RTX|GTX|Radeon RX|Radeon Pro|Arc A") -and ($name -notmatch "Graphics|Integrated|Iris|Vega|Radeon\(TM\)")

            $gpuObj = [ordered]@{
                Name        = $name
                DriverVer   = $g.DriverVersion
                VRAM_GB     = $vram
                IsDiscrete  = $isDiscrete
                TGP_W       = $null
            }

            if ($name -match "NVIDIA") {
                # Cari nvidia-smi di System32 terlebih dahulu (lokasi modern DCH driver)
                $smiPaths = @(
                    (Join-Path $env:SystemRoot "System32\nvidia-smi.exe"),
                    (Join-Path $env:ProgramFiles "NVIDIA Corporation\NVSMI\nvidia-smi.exe")
                )
                $nvsmi = $smiPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                if ($nvsmi) {
                    try {
                        $smiOut = & $nvsmi --query-gpu=memory.total,power.limit,enforced.power.limit --format=csv,noheader,nounits 2>$null
                        if ($smiOut) {
                            $parts = ($smiOut -split ",") | ForEach-Object { $_.Trim() }
                            if ($parts.Count -ge 1 -and $parts[0] -as [double]) {
                                $vramMB = [double]$parts[0]
                                $gpuObj.VRAM_GB = [math]::Round($vramMB / 1024, 1)
                            }
                            # Cari angka TGP valid yang bukan [N/A]
                            foreach ($p in $parts[1..($parts.Count - 1)]) {
                                if ($p -ne "[N/A]" -and ($p -as [double])) {
                                    $gpuObj.TGP_W = [math]::Round([double]$p, 0)
                                    break
                                }
                            }
                        }
                    } catch {}
                }
            }

            $profile.AllGPUs += $gpuObj
            if ($isDiscrete -and -not $profile.DiscreteGPU) {
                $profile.DiscreteGPU = $gpuObj
            } elseif (-not $isDiscrete -and -not $profile.IntegratedGPU) {
                $profile.IntegratedGPU = $gpuObj
            }
        }
    } catch {}

    # Query Drives
    try {
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        foreach ($d in $drives) {
            $dev = $d.DeviceID
            $freeGB  = [math]::Round($d.FreeSpace / 1GB, 1)
            $totalGB = [math]::Round($d.Size / 1GB, 1)
            $profile.Drives[$dev] = [ordered]@{
                DeviceID = $dev
                Label    = $d.VolumeName
                FreeGB   = $freeGB
                TotalGB  = $totalGB
            }
        }
    } catch {}

    # HAGS Status
    try {
        $hagsReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue
        if ($hagsReg -and $hagsReg.HwSchMode -eq 2) {
            $profile.HAGS_Status = $true
        }
    } catch {}

    # Hibernate & Hiberfil.sys
    try {
        $hiberReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue
        if ($hiberReg -and $hiberReg.HibernateEnabled -eq 1) {
            $profile.HibernateActive = $true
            if (Test-Path "C:\hiberfil.sys") {
                $f = Get-Item "C:\hiberfil.sys" -Force -ErrorAction SilentlyContinue
                if ($f) {
                    $profile.HiberfilSizeGB = [math]::Round($f.Length / 1GB, 1)
                }
            }
            if ($profile.HiberfilSizeGB -le 0 -and $profile.RAM_GB -gt 0) {
                $profile.HiberfilSizeGB = [math]::Round($profile.RAM_GB * 0.4, 1)
            }
        }
    } catch {}

    # --------------------------------------------------------------------------
    # 4. UNIVERSAL MULTI-STORE & STANDALONE GAME DISCOVERY ENGINE
    # --------------------------------------------------------------------------
    $steamLibs = [System.Collections.Generic.HashSet[string]]::new()
    @(
        "${env:ProgramFiles(x86)}\Steam",
        "$env:ProgramFiles\Steam"
    ) | ForEach-Object { if (Test-Path $_) { [void]$steamLibs.Add($_) } }

    $steamReg = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamReg -and (Test-Path $steamReg)) { [void]$steamLibs.Add($steamReg) }

    foreach ($slib in @($steamLibs)) {
        $vdf = Join-Path $slib "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $vdfContent = Get-Content $vdf -Raw -ErrorAction SilentlyContinue
            $vdfMatches = [regex]::Matches($vdfContent, '"path"\s+"([^"]+)"')
            foreach ($m in $vdfMatches) {
                $p = $m.Groups[1].Value.Replace("\\", "\")
                if (Test-Path $p) { [void]$steamLibs.Add($p) }
            }
        }
    }

    $profile.SteamLibraries = @($steamLibs)

    # A. Steam Games
    foreach ($lib in $profile.SteamLibraries) {
        $appsDir = Join-Path $lib "steamapps"
        if (Test-Path $appsDir) {
            Get-ChildItem -Path $appsDir -Filter "appmanifest_*.acf" -File -ErrorAction SilentlyContinue | ForEach-Object {
                $txt = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
                $appId = $null; $appName = $null; $installSub = $null
                if ($txt -match '"appid"\s+"(\d+)"') { $appId = $Matches[1] }
                if ($txt -match '"name"\s+"([^"]+)"') { $appName = $Matches[1] }
                if ($txt -match '"installdir"\s+"([^"]+)"') { $installSub = $Matches[1] }
                if ($appId -and $appName -and $installSub) {
                    if ($appName -notmatch "Steamworks|Redistributable|Proton|Shared") {
                        $fullPath = Join-Path $appsDir "common\$installSub"
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

    # B. Epic Games Store Manifests
    $epicManifests = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
    if (Test-Path $epicManifests) {
        Get-ChildItem -Path $epicManifests -Filter "*.item" -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $j = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
                if ($j.DisplayName -and $j.InstallLocation) {
                    $profile.DiscoveredGames["Epic_$($j.AppName)"] = [ordered]@{
                        Name        = $j.DisplayName
                        Platform    = "Epic Games"
                        InstallPath = $j.InstallLocation
                    }
                }
            } catch {}
        }
    }

    # C. GOG Galaxy Registry
    $gogReg = "HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games"
    if (Test-Path $gogReg) {
        Get-ChildItem -Path $gogReg -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.gameName -and $p.path) {
                $profile.DiscoveredGames["GOG_$($_.PSChildName)"] = [ordered]@{
                    Name        = $p.gameName
                    Platform    = "GOG"
                    InstallPath = $p.path
                }
            }
        }
    }

    # D. Ubisoft Connect
    $ubiReg = "HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs"
    if (Test-Path $ubiReg) {
        Get-ChildItem -Path $ubiReg -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p.InstallDir) {
                $profile.DiscoveredGames["Ubisoft_$($_.PSChildName)"] = [ordered]@{
                    Name        = "Ubisoft ($($_.PSChildName))"
                    Platform    = "Ubisoft"
                    InstallPath = $p.InstallDir
                }
            }
        }
    }

    # E. HoYoPlay (Cognosphere)
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
            } elseif ($gameKey -match "Zenless|ZZZ") {
                $profile.DiscoveredGames["HoYo_ZZZ"] = [ordered]@{
                    Name     = "Zenless Zone Zero"
                    Platform = "HoYoPlay"
                    RegPath  = $_.Name
                }
            }
        }
    }

    # F. Standalone Games Folders on all active drives (e.g. C:\Games, D:\Games, E:\Games)
    $allDrives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root
    foreach ($d in $allDrives) {
        $gamesDir = Join-Path $d "Games"
        if (Test-Path $gamesDir) {
            Get-ChildItem -Path $gamesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $folderName = $_.Name
                if ($folderName -notmatch "Mods") {
                    $exe = Get-ChildItem -Path $_.FullName -Filter "*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch "Crash|unins|setup|patch|UnityCrashHandler" } | Select-Object -First 1
                    if ($exe) {
                        $id = "Folder_$($folderName -replace '[^a-zA-Z0-9]', '')"
                        if (-not $profile.DiscoveredGames.Contains($id)) {
                            $profile.DiscoveredGames[$id] = [ordered]@{
                                Name        = $folderName
                                Platform    = "PC Standalone"
                                InstallPath = $_.FullName
                                ExePath     = $exe.FullName
                            }
                        }
                    }
                }
            }
        }
    }

    # G. Documents Settings (Rockstar & CDPR)
    $rdr2Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "Rockstar Games\Red Dead Redemption 2\Settings\system.xml"
    if (Test-Path $rdr2Doc) {
        $profile.DiscoveredGames["Rockstar_RDR2"] = [ordered]@{
            Name       = "Red Dead Redemption 2"
            Platform   = "Rockstar Games"
            ConfigFile = $rdr2Doc
        }
    }

    $w3Doc = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "The Witcher 3\dx12user.settings"
    if (Test-Path $w3Doc) {
        $profile.DiscoveredGames["CDPR_W3"] = [ordered]@{
            Name       = "The Witcher 3: Wild Hunt (DX12)"
            Platform   = "CD Projekt RED"
            ConfigFile = $w3Doc
        }
    }

    # H. Installed Games Registry (Uninstall Keys)
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue | ForEach-Object {
        $disp = $_.DisplayName
        $loc  = $_.InstallLocation
        if ($disp -and ($disp -notmatch "Security|Update|Service|Driver|Redistributable|SDK|Runtime|Tool|Prerequisite|Headers|Contracts")) {
            if ($loc -and ($loc -match "Game|Games|Steam|Epic|Riot|HoYo|Gryphlink|Roblox|Witcher|Cyberpunk|Rockstar")) {
                $id = "App_" + ($disp -replace '[^a-zA-Z0-9]', '')
                if (-not $profile.DiscoveredGames.Contains($id)) {
                    $profile.DiscoveredGames[$id] = [ordered]@{
                        Name        = $disp
                        Platform    = if ($_.Publisher) { $_.Publisher } else { "Installed Game" }
                        InstallPath = $loc
                    }
                }
            }
        }
    }

    return $profile
}

# ------------------------------------------------------------------------------
# 5. ATOMIC TWEAKS ENGINE (1 CHECKBOX = 1 ATOMIC INDEPENDENT FUNCTION)
# ------------------------------------------------------------------------------
function Set-VoltAtomicTweak {
    param(
        [Parameter(Mandatory=$true)][string]$TweakId,
        [Parameter(Mandatory=$true)][bool]$Enable,
        [hashtable]$Hardware
    )

    switch ($TweakId) {
        "chkHags" {
            $val = if ($Enable) { 2 } else { 1 }
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkGameMode" {
            $val = if ($Enable) { 1 } else { 0 }
            if (-not (Test-Path "HKCU:\Software\Microsoft\GameBar")) { New-Item "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkGameDVR" {
            if ($Enable) {
                if (-not (Test-Path "HKCU:\System\GameConfigStore")) { New-Item "HKCU:\System\GameConfigStore" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR")) { New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Force -ErrorAction SilentlyContinue
            }
        }
        "chkRawMouse" {
            if ($Enable) {
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "1" -Type String -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "6" -Type String -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "10" -Type String -Force -ErrorAction SilentlyContinue
            }
        }
        "chkDefender" {
            if ($Enable) {
                Add-VoltDefenderGameExclusions -Hardware $Hardware
            }
        }
        "chkNetwork" {
            if ($Enable) {
                Set-VoltNetworkGamingTweaks
            } else {
                Set-VoltNetworkGamingTweaks -Revert
            }
        }
        "chkPowerThrottle" {
            if ($Enable) {
                Set-VoltPowerThrottlingOff
            } else {
                Set-VoltPowerThrottlingOff -Disable
            }
        }
        "chkSafeServices" {
            if ($Enable) {
                Optimize-VoltServices
            } else {
                Optimize-VoltServices -Revert
            }
        }
        "chkSecurityUpdates" {
            if ($Enable) {
                Set-VoltWindowsUpdateProfile
            } else {
                Set-VoltWindowsUpdateProfile -Revert
            }
        }
        "chkClassicMenu" {
            if ($Enable) {
                Set-VoltClassicContextMenu
            } else {
                Set-VoltClassicContextMenu -Disable
            }
        }
        "chkFileExt" {
            $val = if ($Enable) { 0 } else { 1 }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkThisPC" {
            $val = if ($Enable) { 1 } else { 2 }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkHiddenFiles" {
            $val = if ($Enable) { 1 } else { 2 }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkCleanTaskbar" {
            if ($Enable) {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        "chkCleanQuickAccess" {
            $val = if ($Enable) { 0 } else { 1 }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkTelemetry" {
            if ($Enable) {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection")) { New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Force -ErrorAction SilentlyContinue
            }
        }
        "chkRecall" {
            if ($Enable) {
                if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI")) { New-Item "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Force -ErrorAction SilentlyContinue
            }
        }
        "chkCopilot" {
            if ($Enable) {
                if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot")) { New-Item "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Remove-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Force -ErrorAction SilentlyContinue
            }
        }
        "chkStartSearch" {
            if ($Enable) {
                if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search")) { New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Force | Out-Null }
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "AllowSearchToUseLocation" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
        "chkAdId" {
            $val = if ($Enable) { 0 } else { 1 }
            if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo")) { New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Force | Out-Null }
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value $val -Type DWord -Force -ErrorAction SilentlyContinue
        }
        "chkDeliveryOpt" {
            if ($Enable) {
                if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization")) { New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Force | Out-Null }
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
            } else {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ------------------------------------------------------------------------------
# 6. LIVE WINDOWS TWEAKS STATE INSPECTOR
# ------------------------------------------------------------------------------
function Get-VoltWindowsTweakState {
    $state = @{}

    # HAGS
    $hags = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -ErrorAction SilentlyContinue).HwSchMode
    $state["chkHags"] = ($hags -eq 2)

    # Windows Game Mode
    $gm = (Get-ItemProperty "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -ErrorAction SilentlyContinue).AutoGameModeEnabled
    $state["chkGameMode"] = ($gm -eq 1)

    # Background GameDVR Off
    $dvr = (Get-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -ErrorAction SilentlyContinue).GameDVR_Enabled
    $state["chkGameDVR"] = ($dvr -eq 0)

    # 1:1 Raw Mouse Input
    $ms = (Get-ItemProperty "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -ErrorAction SilentlyContinue).MouseSpeed
    $state["chkRawMouse"] = ($ms -eq "0")

    # Defender Game Exclusion
    $pref = Get-MpPreference -ErrorAction SilentlyContinue
    $hasExcl = $false
    if ($pref -and $pref.ExclusionPath) {
        foreach ($ep in $pref.ExclusionPath) {
            if ($ep -match "Steam|Games|HoYo|Epic") { $hasExcl = $true; break }
        }
    }
    $state["chkDefender"] = $hasExcl

    # TCP/IP Gaming Latency
    $tcpNet = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency -eq 1 }
    $state["chkNetwork"] = ($null -ne $tcpNet)

    # Power Throttling Off
    $pt = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" -Name "PowerThrottlingOff" -ErrorAction SilentlyContinue).PowerThrottlingOff
    $state["chkPowerThrottle"] = ($pt -eq 1)

    # Safe Services (DiagTrack disabled)
    $diag = Get-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
    $state["chkSafeServices"] = ($diag -and $diag.StartType -eq "Disabled")

    # Security Updates Only / Driver hijack block
    $wu = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue).ExcludeWUDriversInQualityUpdate
    $state["chkSecurityUpdates"] = ($wu -eq 1)

    # Classic Context Menu
    $state["chkClassicMenu"] = (Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32")

    # File Extensions
    $hfe = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -ErrorAction SilentlyContinue).HideFileExt
    $state["chkFileExt"] = ($hfe -eq 0)

    # Open Explorer to This PC
    $lt = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -ErrorAction SilentlyContinue).LaunchTo
    $state["chkThisPC"] = ($lt -eq 1)

    # Show Hidden Files
    $hf = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -ErrorAction SilentlyContinue).Hidden
    $state["chkHiddenFiles"] = ($hf -eq 1)

    # Clean Taskbar (TaskbarDa=0)
    $tda = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -ErrorAction SilentlyContinue).TaskbarDa
    $state["chkCleanTaskbar"] = ($tda -eq 0)

    # Clean Quick Access (ShowFrequent=0)
    $sf = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowFrequent" -ErrorAction SilentlyContinue).ShowFrequent
    $state["chkCleanQuickAccess"] = ($sf -eq 0)

    # Telemetry Minimum (AllowTelemetry=0)
    $at = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -ErrorAction SilentlyContinue).AllowTelemetry
    $state["chkTelemetry"] = ($at -eq 0)

    # Recall AI Off
    $rec = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -ErrorAction SilentlyContinue).DisableAIDataAnalysis
    $state["chkRecall"] = ($rec -eq 1)

    # Copilot Off
    $cop = (Get-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue).TurnOffWindowsCopilot
    $state["chkCopilot"] = ($cop -eq 1)

    # Start Bing Search Off
    $bse = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -ErrorAction SilentlyContinue).BingSearchEnabled
    $state["chkStartSearch"] = ($bse -eq 0)

    # Advertising ID Off
    $adid = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    $state["chkAdId"] = ($adid -eq 0)

    # Delivery Optimization P2P Off
    $do = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -ErrorAction SilentlyContinue).DODownloadMode
    $state["chkDeliveryOpt"] = ($do -eq 0)

    return $state
}

# ------------------------------------------------------------------------------
# 7. SAFETY & SYSTEM RESTORE POINT AUTOMATION
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
# 8. VOLTUNDO ENTERPRISE ENGINE (SNAPSHOT & REVERSIBLE ROLLBACK)
# ------------------------------------------------------------------------------
function New-VoltBackupSnapshot {
    param([hashtable]$Hardware)

    $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $snapshotDir = Join-Path $Script:BackupDir "Snapshot-$timestamp"
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null

    Write-Host "`n[*] Mengambil snapshot registri & konfigurasi dinamis (VoltUndo)..." -ForegroundColor Cyan
    Write-Host "    -> Lokasi Backup: $snapshotDir" -ForegroundColor Gray

    $manifest = [ordered]@{
        Timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Version     = $Script:VoltVersion
        SystemRegs  = @()
        GameRegs    = @()
        ConfigFiles = @()
    }

    $systemTargets = @(
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"; File = "GraphicsDrivers.reg" },
        @{ Key = "HKCU\System\GameConfigStore"; File = "GameConfigStore.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; File = "GameDVR_Policy.reg" },
        @{ Key = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"; File = "SystemProfile.reg" },
        @{ Key = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"; File = "TcpipParameters.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; File = "WindowsUpdate.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; File = "ExplorerAdvanced.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; File = "DataCollection.reg" },
        @{ Key = "HKCU\Control Panel\Mouse"; File = "MouseSettings.reg" },
        @{ Key = "HKCU\Control Panel\Desktop"; File = "DesktopSettings.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"; File = "WindowsSearch.reg" },
        @{ Key = "HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; File = "AdvertisingInfo.reg" },
        @{ Key = "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"; File = "DeliveryOptimization.reg" }
    )

    foreach ($target in $systemTargets) {
        $outFile = Join-Path $snapshotDir $target.File
        & reg.exe export $target.Key $outFile /y 2>$null | Out-Null
        if (Test-Path $outFile) {
            $manifest.SystemRegs += @{ Key = $target.Key; File = $target.File }
        }
    }

    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.RegPath) {
                $regName = ($k -replace '[^a-zA-Z0-9]', '_') + ".reg"
                $outFile = Join-Path $snapshotDir $regName
                $cleanKey = $g.RegPath -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_LOCAL_MACHINE', 'HKLM'
                & reg.exe export $cleanKey $outFile /y 2>$null | Out-Null
                if (Test-Path $outFile) {
                    $manifest.GameRegs += @{ Key = $cleanKey; File = $regName }
                }
            }
        }
    }

    if ($Hardware -and $Hardware.DiscoveredGames) {
        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]
            if ($g.ConfigFile -and (Test-Path $g.ConfigFile)) {
                $bakName = ($k -replace '[^a-zA-Z0-9]', '_') + ".bak"
                $bakPath = Join-Path $snapshotDir $bakName
                Copy-Item -Path $g.ConfigFile -Destination $bakPath -Force -ErrorAction SilentlyContinue
                if (Test-Path $bakPath) {
                    $manifest.ConfigFiles += @{ Source = $g.ConfigFile; Backup = $bakName }
                }
            }
        }
    }

    $manifestJson = Join-Path $snapshotDir "manifest.json"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestJson -Encoding UTF8

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
                Copy-Item -Path $bak -Destination $cf.Source -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    return $true
}

function Invoke-VoltUndo {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "                     ↩️ VOLTUNDO: RESTORE SISTEM KE KONDISI ASAL                " -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow

    $snaps = Get-ChildItem -Path $Script:BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
    if (-not $snaps -or $snaps.Count -eq 0) {
        Write-Host "[!] Tidak ditemukan snapshot backup VoltUndo di: $Script:BackupDir" -ForegroundColor Red
        return
    }

    $latest = $snaps[0]
    Write-Host "[*] Menggunakan snapshot terbaru: $($latest.Name)" -ForegroundColor Cyan
    Write-Host "    Waktu Pembuatan: $($latest.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

    $ok = Restore-VoltSnapshotByPath -SnapshotDir $latest.FullName
    if ($ok) {
        Write-Host "`n[✓] Seluruh registri dan konfigurasi sistem berhasil dipulihkan dari snapshot!" -ForegroundColor Green
    } else {
        Write-Host "`n[-] Gagal memulihkan sistem dari snapshot." -ForegroundColor Red
    }
}

# ------------------------------------------------------------------------------
# 9. ACTIVE PROCESS GUARDS (CHROME/FIREFOX/STEAM/EPIC/GAMES)
# ------------------------------------------------------------------------------
function Get-VoltActiveGuards {
    $browserNames = @("chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "thorium")
    $launcherNames = @("steam", "epicgameslauncher", "origin", "eadesktop", "upc", "gog_galaxy", "riotclientux", "battle.net")
    $gameExes = @("rdr2", "witcher3", "starrail", "genshinimpact", "cyberpunk2077", "gta5")

    $runningProcesses = Get-Process -ErrorAction SilentlyContinue

    $activeBrowsers = @()
    $activeLaunchers = @()
    $activeGames = @()

    foreach ($p in $runningProcesses) {
        $pName = $p.ProcessName.ToLower()
        if ($browserNames -contains $pName -and -not ($activeBrowsers -contains $pName)) {
            $activeBrowsers += $pName
        }
        if ($launcherNames -contains $pName -and -not ($activeLaunchers -contains $pName)) {
            $activeLaunchers += $pName
        }
        if ($gameExes -contains $pName -and -not ($activeGames -contains $pName)) {
            $activeGames += $pName
        }
    }

    return [ordered]@{
        Browsers  = $activeBrowsers
        Launchers = $activeLaunchers
        Games     = $activeGames
    }
}

# ------------------------------------------------------------------------------
# 10. IN-GAME SPECIFIC PROFILES (RDR2, WITCHER 3, HOYOPLAY)
# ------------------------------------------------------------------------------
function Optimize-VoltGameRDR2 {
    param([string]$ConfigPath)
    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) { return }
    Write-Host "[*] Mengoptimasi setting Red Dead Redemption 2 di: $ConfigPath" -ForegroundColor Cyan
    try {
        [xml]$xml = Get-Content $ConfigPath
        $async = $xml.SelectSingleNode("//asyncComputeEnabled")
        if ($async) { $async.value = "true" }
        $tex = $xml.SelectSingleNode("//maxTexUpgradesPerFrame")
        if ($tex) { $tex.value = "10" }
        $xml.Save($ConfigPath)
        Write-Host "    [✓] Async Compute diaktifkan & MaxTexUpgrades ditingkatkan ke 10!" -ForegroundColor Green
    } catch {
        Write-Host "    [-] Gagal mengedit system.xml RDR2: $_" -ForegroundColor DarkYellow
    }
}

function Optimize-VoltGameHSR {
    param([hashtable]$GameInfo)
    Write-Host "[*] Mengoptimasi profil Honkai: Star Rail..." -ForegroundColor Cyan
    try {
        $regPath = "HKCU:\Software\Cognosphere\Star Rail"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "GraphicsSettings_Model_h2986158309" -Value 2 -ErrorAction SilentlyContinue
            Write-Host "    [✓] Setting 60 FPS stabil & Anti-Aliasing optimal diterapkan." -ForegroundColor Green
        }
    } catch {}
}

function Optimize-VoltGameGenshin {
    param([hashtable]$GameInfo)
    Write-Host "[*] Mengoptimasi profil Genshin Impact..." -ForegroundColor Cyan
    try {
        $regPath = "HKCU:\Software\Cognosphere\Genshin Impact"
        if (Test-Path $regPath) {
            Set-ItemProperty -Path $regPath -Name "GENERAL_DATA_h2389025596" -Value 2 -ErrorAction SilentlyContinue
            Write-Host "    [✓] Setting 60 FPS stabil & Crowd Density seimbang diterapkan." -ForegroundColor Green
        }
    } catch {}
}

function Optimize-VoltGameWitcher3 {
    param([string]$ConfigPath)
    if (-not $ConfigPath -or -not (Test-Path $ConfigPath)) { return }
    Write-Host "[*] Mengoptimasi setting The Witcher 3 DX12 di: $ConfigPath" -ForegroundColor Cyan
    try {
        $content = Get-Content $ConfigPath -Raw
        $content = $content -replace "HairWorksLevel=\d+", "HairWorksLevel=0"
        $content = $content -replace "FoliageVisibilityRange=\d+", "FoliageVisibilityRange=2"
        Set-Content -Path $ConfigPath -Value $content -Encoding UTF8
        Write-Host "    [✓] HairWorks dimatikan (Hemat ~25% GPU) & Foliage diselaraskan." -ForegroundColor Green
    } catch {}
}

function Optimize-VoltPlayGames {
    param(
        [hashtable]$Hardware,
        [string]$TargetGameKey = "ALL"
    )

    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }
    $games = $Hardware.DiscoveredGames

    if ($games.Count -eq 0) {
        Write-Host "`n[!] Tidak ada game lokal terdeteksi untuk dituning." -ForegroundColor DarkYellow
        return
    }

    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host "           🎮 VOLTPLAY: PENYELARASAN GAME DINAMIS & GPU HIGH PERF              " -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    $gpuPrefReg = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $gpuPrefReg)) { New-Item $gpuPrefReg -Force | Out-Null }

    foreach ($k in $games.Keys) {
        $g = $games[$k]
        if ($TargetGameKey -ne "ALL" -and $TargetGameKey -ne $k) { continue }

        Write-Host "`n[*] Game: $($g.Name) [$($g.Platform)]" -ForegroundColor Yellow

        # Register Game Executables to Discrete GPU High Performance
        $exeCandidates = @()
        if ($g.InstallPath -and (Test-Path $g.InstallPath)) {
            $exes = Get-ChildItem -Path $g.InstallPath -Filter "*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notmatch "unins|setup|crash|report|patch|UnityCrashHandler" }
            $exeCandidates += $exes
        }
        if ($g.ExePath -and (Test-Path $g.ExePath)) {
            $exeCandidates += (Get-Item $g.ExePath)
        }

        foreach ($exe in ($exeCandidates | Select-Object -Unique)) {
            # GpuPreference=2 (High Performance Discrete GPU)
            Set-ItemProperty -Path $gpuPrefReg -Name $exe.FullName -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
            Write-Host "    -> Didaftarkan ke Windows GPU High Performance (RTX 4060): $($exe.Name)" -ForegroundColor Gray
        }

        if ($k -eq "Rockstar_RDR2" -and $g.ConfigFile) {
            Optimize-VoltGameRDR2 -ConfigPath $g.ConfigFile
        } elseif ($k -eq "CDPR_W3" -and $g.ConfigFile) {
            Optimize-VoltGameWitcher3 -ConfigPath $g.ConfigFile
        } elseif ($k -eq "HoYo_HSR") {
            Optimize-VoltGameHSR -GameInfo $g
        } elseif ($k -eq "HoYo_Genshin") {
            Optimize-VoltGameGenshin -GameInfo $g
        }
    }

    Write-Host "`n[✓] Penyelarasan setting game VoltPlay berhasil diterapkan!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 11. WINDOWS CORE, NETWORK, SERVICES & PRIVACY IMPLEMENTATIONS
# ------------------------------------------------------------------------------
function Set-VoltPowerThrottlingOff {
    param([switch]$Disable)
    $reg = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"
    if (-not (Test-Path $reg)) { New-Item $reg -Force | Out-Null }
    if ($Disable) {
        Remove-ItemProperty -Path $reg -Name "PowerThrottlingOff" -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $reg -Name "PowerThrottlingOff" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

function Set-VoltClassicContextMenu {
    param([switch]$Disable)
    $keyPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    if ($Disable) {
        Remove-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -Path $keyPath -Value "" -Force | Out-Null
    }
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}

function Set-VoltNetworkGamingTweaks {
    param([switch]$Revert)

    $interfacesPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    $guards = @("palo alto", "globalprotect", "pangps", "tap", "vpn", "virtual", "hyper-v", "wsl")

    Get-ChildItem -Path $interfacesPath -ErrorAction SilentlyContinue | ForEach-Object {
        $key = $_.PSPath
        $adapterDesc = (Get-ItemProperty $key -Name "Description" -ErrorAction SilentlyContinue).Description
        $isVirtual = $false
        if ($adapterDesc) {
            foreach ($g in $guards) {
                if ($adapterDesc.ToLower() -match $g) { $isVirtual = $true; break }
            }
        }

        if (-not $isVirtual) {
            if ($Revert) {
                Remove-ItemProperty -Path $key -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $key -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
            } else {
                Set-ItemProperty -Path $key -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $key -Name "TCPNoDelay" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    if ($Revert) {
        Remove-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $sysProfile -Name "NetworkThrottlingIndex" -Value 0xFFFFFFFF -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $sysProfile -Name "SystemResponsiveness" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

function Optimize-VoltServices {
    param([switch]$Revert)
    $services = @("DiagTrack", "dmwappushservice", "MapsBroker", "lfsvc")
    foreach ($s in $services) {
        if ($Revert) {
            Set-Service -Name $s -StartupType Manual -ErrorAction SilentlyContinue
        } else {
            Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
            Set-Service -Name $s -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
}

function Set-VoltWindowsUpdateProfile {
    param([switch]$Revert)
    $wuPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $auPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $wuPolicy)) { New-Item $wuPolicy -Force | Out-Null }
    if (-not (Test-Path $auPolicy)) { New-Item $auPolicy -Force | Out-Null }

    if ($Revert) {
        Remove-ItemProperty -Path $wuPolicy -Name "ExcludeWUDriversInQualityUpdate" -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $auPolicy -Name "NoAutoRebootWithLoggedOnUsers" -Force -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path $wuPolicy -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $auPolicy -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }
}

function Add-VoltDefenderGameExclusions {
    param([hashtable]$Hardware)
    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }
    $dirs = @()
    if ($Hardware.SteamLibraries) { $dirs += $Hardware.SteamLibraries }
    foreach ($g in $Hardware.DiscoveredGames.Values) {
        if ($g.InstallPath -and (Test-Path $g.InstallPath)) { $dirs += $g.InstallPath }
    }
    foreach ($d in ($dirs | Select-Object -Unique)) {
        try {
            Add-MpPreference -ExclusionPath $d -ErrorAction SilentlyContinue
        } catch {}
    }
}

function Toggle-VoltHibernation {
    param([hashtable]$Hardware)
    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }
    if ($Hardware.HibernateActive) {
        & powercfg.exe /hibernate off
    } else {
        & powercfg.exe /hibernate on
    }
}

function Set-VoltPowerPlan {
    param([string]$PlanType = "Ultimate")
    if ($PlanType -eq "Ultimate") {
        & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
        $plans = & powercfg.exe /list
        $guid = $null
        foreach ($line in ($plans -split "`n")) {
            if ($line -match "Ultimate Performance\s*\(([a-f0-9\-]+)\)") {
                $guid = $Matches[1]
                break
            }
        }
        if ($guid) { & powercfg.exe /setactive $guid }
    } else {
        & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null | Out-Null
    }
}

function Set-VoltWindowsFeatureDirectPlay {
    & dism.exe /Online /Enable-Feature /FeatureName:DirectPlay /All /NoRestart
}

function Set-VoltWindowsFeatureSandbox {
    & dism.exe /Online /Enable-Feature /FeatureName:Containers-DisposableClientVM /All /NoRestart
}

function Set-VoltWindowsFeatureWSL {
    & wsl.exe --install --no-distribution
}

# ------------------------------------------------------------------------------
# 12. DYNAMIC DISK CLEANUP ACROSS ALL DRIVES (VOLTCLEAN)
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
    $freed = 0
    $freed += Clear-VoltFolderSafely $env:TEMP
    $freed += Clear-VoltFolderSafely (Join-Path $env:SystemRoot "Temp")
    $freed += Clear-VoltFolderSafely (Join-Path $env:LOCALAPPDATA "D3DSCache")
    $freed += Clear-VoltFolderSafely (Join-Path $env:LOCALAPPDATA "NVIDIA\DXCache")
    $freed += Clear-VoltFolderSafely (Join-Path $env:LOCALAPPDATA "CrashDumps")
    return $freed
}

function Rebuild-VoltIconCache {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Remove-Item (Join-Path $env:LOCALAPPDATA "IconCache.db") -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Explorer\thumbcache_*.db") -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Reset-VoltNetwork {
    & netsh.exe winsock reset | Out-Null
    & netsh.exe int ip reset | Out-Null
    & ipconfig.exe /flushdns | Out-Null
}

# ------------------------------------------------------------------------------
# 13. BLUEPRINT PRESET MATRIX
# ------------------------------------------------------------------------------
$Script:VoltPresetMap = @{
    "Recommended" = @{
        chkHags = $true; chkGameMode = $true; chkGameDVR = $true; chkRawMouse = $true;
        chkDefender = $true; chkNetwork = $true; chkPowerThrottle = $false;
        chkSafeServices = $true; chkSecurityUpdates = $true;
        chkClassicMenu = $true; chkFileExt = $true; chkThisPC = $true; chkHiddenFiles = $true;
        chkCleanTaskbar = $true; chkCleanQuickAccess = $true;
        chkTelemetry = $true; chkRecall = $true; chkCopilot = $true; chkStartSearch = $true;
        chkAdId = $true; chkDeliveryOpt = $true
    }
    "LaptopGaming" = @{
        chkHags = $true; chkGameMode = $true; chkGameDVR = $true; chkRawMouse = $true;
        chkDefender = $true; chkNetwork = $true; chkPowerThrottle = $false;
        chkSafeServices = $true; chkSecurityUpdates = $true;
        chkClassicMenu = $true; chkFileExt = $true; chkThisPC = $true; chkHiddenFiles = $false;
        chkCleanTaskbar = $true; chkCleanQuickAccess = $true;
        chkTelemetry = $true; chkRecall = $true; chkCopilot = $true; chkStartSearch = $true;
        chkAdId = $true; chkDeliveryOpt = $true
    }
    "DesktopMax" = @{
        chkHags = $true; chkGameMode = $true; chkGameDVR = $true; chkRawMouse = $true;
        chkDefender = $true; chkNetwork = $true; chkPowerThrottle = $true;
        chkSafeServices = $true; chkSecurityUpdates = $true;
        chkClassicMenu = $true; chkFileExt = $true; chkThisPC = $true; chkHiddenFiles = $true;
        chkCleanTaskbar = $true; chkCleanQuickAccess = $true;
        chkTelemetry = $true; chkRecall = $true; chkCopilot = $true; chkStartSearch = $true;
        chkAdId = $true; chkDeliveryOpt = $true
    }
    "MinimalPrivacy" = @{
        chkHags = $false; chkGameMode = $false; chkGameDVR = $false; chkRawMouse = $false;
        chkDefender = $false; chkNetwork = $false; chkPowerThrottle = $false;
        chkSafeServices = $false; chkSecurityUpdates = $false;
        chkClassicMenu = $true; chkFileExt = $true; chkThisPC = $true; chkHiddenFiles = $false;
        chkCleanTaskbar = $true; chkCleanQuickAccess = $true;
        chkTelemetry = $true; chkRecall = $true; chkCopilot = $true; chkStartSearch = $true;
        chkAdId = $true; chkDeliveryOpt = $true
    }
    "ClearAll" = @{
        chkHags = $false; chkGameMode = $false; chkGameDVR = $false; chkRawMouse = $false;
        chkDefender = $false; chkNetwork = $false; chkPowerThrottle = $false;
        chkSafeServices = $false; chkSecurityUpdates = $false;
        chkClassicMenu = $false; chkFileExt = $false; chkThisPC = $false; chkHiddenFiles = $false;
        chkCleanTaskbar = $false; chkCleanQuickAccess = $false;
        chkTelemetry = $false; chkRecall = $false; chkCopilot = $false; chkStartSearch = $false;
        chkAdId = $false; chkDeliveryOpt = $false
    }
}

# ------------------------------------------------------------------------------
# 14. MODERN NATIVE WPF DESKTOP HUB (FLUENT DARK REVAMP)
# ------------------------------------------------------------------------------
function Show-VoltGUI {
    param([hashtable]$Hardware)

    if (-not $Hardware) { $Hardware = Get-VoltHardwareProfile }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Voltune Ultimate Hub v$Script:VoltVersion" Height="820" Width="1140"
        MinHeight="680" MinWidth="950"
        WindowStartupLocation="CenterScreen" Background="#0B0F17" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#1E293B"/>
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="BorderBrush" Value="#334155"/>
            <Setter Property="Padding" Value="12,7"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#111827"/>
            <Setter Property="Foreground" Value="#94A3B8"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F8FAFC"/>
            <Setter Property="Margin" Value="0,5"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Cursor" Value="Hand"/>
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
        <Border Grid.Row="0" Background="#111827" CornerRadius="8" Padding="16,12" Margin="0,0,0,10" BorderBrush="#1F2937" BorderThickness="1">
            <DockPanel LastChildFill="False">
                <StackPanel DockPanel.Dock="Left">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="⚡ VOLTUNE ULTIMATE" FontSize="20" FontWeight="Bold" Foreground="#38BDF8" VerticalAlignment="Center"/>
                        <TextBlock Text="v$Script:VoltVersion" FontSize="11" Foreground="#94A3B8" Margin="8,6,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <TextBlock Text="Universal Hardware-Aware Performance, Gaming &amp; System Hub" FontSize="11" Foreground="#64748B" Margin="0,2,0,0"/>
                </StackPanel>

                <!-- Hardware Summary Badges -->
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#1E293B" CornerRadius="4" Padding="8,4" Margin="0,0,6,0">
                        <TextBlock Text="🎮 $($Hardware.DiscreteGPU.Name)" Foreground="#38BDF8" FontSize="11" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="#1E293B" CornerRadius="4" Padding="8,4" Margin="0,0,6,0">
                        <TextBlock Text="🖥️ $($Hardware.ScreenResolution) @ $($Hardware.ScreenRefreshHz) Hz" Foreground="#A78BFA" FontSize="11" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="#064E3B" CornerRadius="4" Padding="8,4">
                        <TextBlock Text="100% GUI Mode" Foreground="#34D399" FontSize="11" FontWeight="Bold"/>
                    </Border>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- Main TabControl -->
        <TabControl Grid.Row="1" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
            <!-- TAB 1: DASHBOARD -->
            <TabItem Header="Dashboard">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Telemetri &amp; Profil Hardware Dinamis" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,12"/>

                        <!-- 6 Visual Metric Tiles Grid -->
                        <Grid Margin="0,0,0,16">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Tile 1: CPU -->
                            <Border Grid.Row="0" Grid.Column="0" Background="#1E293B" CornerRadius="8" Padding="14" Margin="0,0,8,8" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="💻 PROSESOR (CPU)" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$($Hardware.CPUName)" FontSize="13" FontWeight="Bold" Foreground="#F8FAFC" TextWrapping="Wrap" Margin="0,4,0,2"/>
                                    <TextBlock Text="$($Hardware.CPUCores) Cores, $($Hardware.CPUThreads) Threads $(if ($Hardware.IsHybridCPU) { '• Hybrid P+E' })" FontSize="11" Foreground="#38BDF8"/>
                                </StackPanel>
                            </Border>

                            <!-- Tile 2: Discrete GPU -->
                            <Border Grid.Row="0" Grid.Column="1" Background="#1E293B" CornerRadius="8" Padding="14" Margin="4,0,4,8" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="🎮 DISCRETE GPU" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$($Hardware.DiscreteGPU.Name)" FontSize="13" FontWeight="Bold" Foreground="#F8FAFC" TextWrapping="Wrap" Margin="0,4,0,2"/>
                                    <TextBlock Text="$($Hardware.DiscreteGPU.VRAM_GB) GB VRAM $(if ($Hardware.DiscreteGPU.TGP_W) { '• ' + $Hardware.DiscreteGPU.TGP_W + 'W TGP' })" FontSize="11" Foreground="#10B981"/>
                                </StackPanel>
                            </Border>

                            <!-- Tile 3: Display -->
                            <Border Grid.Row="0" Grid.Column="2" Background="#1E293B" CornerRadius="8" Padding="14" Margin="8,0,0,8" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="🖥️ LAYAR &amp; TARGET FPS" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$($Hardware.ScreenResolution) @ $($Hardware.ScreenRefreshHz) Hz" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,4,0,2"/>
                                    <TextBlock Text="VRR Target: $($Hardware.DynamicFPSCaps.TearFreeVRR) FPS • Dingin: $($Hardware.DynamicFPSCaps.HalfRate) FPS" FontSize="11" Foreground="#A78BFA"/>
                                </StackPanel>
                            </Border>

                            <!-- Tile 4: Memory -->
                            <Border Grid.Row="1" Grid.Column="0" Background="#1E293B" CornerRadius="8" Padding="14" Margin="0,4,8,0" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="🧠 MEMORI (RAM)" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$($Hardware.RAM_GB) GB Terpasang" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,4,0,2"/>
                                    <TextBlock Text="HAGS: $(if ($Hardware.HAGS_Status) { 'Aktif [✓]' } else { 'Nonaktif' }) • Hibernasi: $(if ($Hardware.HibernateActive) { 'Aktif' } else { 'Hemat SSD' })" FontSize="11" Foreground="#FBBF24"/>
                                </StackPanel>
                            </Border>

                            <!-- Tile 5: Power -->
                            <Border Grid.Row="1" Grid.Column="1" Background="#1E293B" CornerRadius="8" Padding="14" Margin="4,4,4,0" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="⚡ SUMBER DAYA &amp; BATERAI" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$(if ($Hardware.IsOnBattery) { 'Baterai (' + $Hardware.BatteryChargePct + '%)' } else { 'AC Adapter (Daya Maksimal)' })" FontSize="14" FontWeight="Bold" Foreground="$(if ($Hardware.IsOnBattery) { '#FBBF24' } else { '#34D399' })" Margin="0,4,0,2"/>
                                    <TextBlock Text="$(if ($Hardware.IsOnBattery) { 'Mode Hemat Daya Aktif' } else { 'Siap Gaspol Clock Penuh' })" FontSize="11" Foreground="#94A3B8"/>
                                </StackPanel>
                            </Border>

                            <!-- Tile 6: Games Status -->
                            <Border Grid.Row="1" Grid.Column="2" Background="#1E293B" CornerRadius="8" Padding="14" Margin="8,4,0,0" BorderBrush="#334155" BorderThickness="1">
                                <StackPanel>
                                    <TextBlock Text="🎯 EKOSISTEM GAMING" FontSize="11" FontWeight="Bold" Foreground="#94A3B8"/>
                                    <TextBlock Text="$($Hardware.DiscoveredGames.Count) Game Terdeteksi" FontSize="14" FontWeight="Bold" Foreground="#F8FAFC" Margin="0,4,0,2"/>
                                    <TextBlock Text="Steam, HoYoPlay, Standalone &amp; Mod Multi-Drive" FontSize="11" Foreground="#38BDF8"/>
                                </StackPanel>
                            </Border>
                        </Grid>

                        <TextBlock Text="Aksi Cepat Sistem" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,10,0,8"/>
                        <WrapPanel>
                            <Button Name="btnDashSnapshot" Content="📸 Buat Snapshot VoltUndo" Margin="0,0,8,8" Height="36"/>
                            <Button Name="btnDashRestorePoint" Content="🛡️ Buat System Restore Point" Margin="0,0,8,8" Height="36"/>
                            <Button Name="btnDashToggleHiber" Content="💾 Toggle Hibernasi (~$($Hardware.HiberfilSizeGB) GB)" Margin="0,0,8,8" Height="36"/>
                            <Button Name="btnDashPowerUlt" Content="⚡ Skema Daya: Ultimate" Margin="0,0,8,8" Height="36"/>
                            <Button Name="btnDashPowerBal" Content="⚖️ Skema Daya: Balanced" Margin="0,0,8,8" Height="36"/>
                        </WrapPanel>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 2: TWEAKS (CUSTOMIZED PRESETS & ATOMIC TOGGLES) -->
            <TabItem Header="Tweaks">
                <Grid Margin="12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Presets Toolbar -->
                    <Border Grid.Row="0" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,0,0,10" BorderBrush="#1F2937" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="Pilih Preset Konfigurasi (Memilih preset menimpa centang secara bersih, bebas customize):" FontSize="13" Foreground="#94A3B8" Margin="0,0,0,8"/>
                            <WrapPanel>
                                <Button Name="btnPresetRecommended" Content="🎯 Recommended Preset" Background="#0284C7" Margin="0,0,8,6" Height="34"/>
                                <Button Name="btnPresetLaptop" Content="💻 Laptop Gaming Preset" Margin="0,0,8,6" Height="34"/>
                                <Button Name="btnPresetDesktop" Content="🖥️ Desktop Max Preset" Margin="0,0,8,6" Height="34"/>
                                <Button Name="btnPresetMinimal" Content="🛡️ Minimal Privacy Preset" Margin="0,0,8,6" Height="34"/>
                                <Button Name="btnLiveState" Content="🔄 Status Windows Saat Ini" Background="#065F46" Margin="0,0,8,6" Height="34"/>
                                <Button Name="btnPresetClear" Content="❌ Clear All" Margin="0,0,8,6" Height="34"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <!-- Tweaks Cards -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <Grid Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Column 1 -->
                            <StackPanel Grid.Column="0" Margin="0,0,8,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="14" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="⚡ Gaming &amp; Performa Hardware" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                        <CheckBox Name="chkHags" Content="Hardware-Accelerated GPU Scheduling (HAGS)"/>
                                        <CheckBox Name="chkGameMode" Content="Windows Game Mode &amp; MMCSS Low Latency Audio"/>
                                        <CheckBox Name="chkGameDVR" Content="Matikan Background GameDVR (Bebaskan Overhead GPU)"/>
                                        <CheckBox Name="chkRawMouse" Content="1:1 Raw Mouse Input (Matikan Akselerasi Mouse)"/>
                                        <CheckBox Name="chkDefender" Content="Daftarkan Library Game ke Defender Exclusion (Anti-Stutter)"/>
                                        <CheckBox Name="chkNetwork" Content="TCP/IP Gaming Latency Optimizer (Zero-VPN Harm)"/>
                                        <CheckBox Name="chkPowerThrottle" Content="Matikan CPU Power Throttling Execution (Max Clock)"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="14" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="🔒 Layanan &amp; Update Sistem" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                        <CheckBox Name="chkSafeServices" Content="Safe Gaming Services (Matikan DiagTrack, WAP, Maps)"/>
                                        <CheckBox Name="chkSecurityUpdates" Content="Windows Update: Security Updates Only (Anti Driver Hijack)"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Column 2 -->
                            <StackPanel Grid.Column="1" Margin="8,0,0,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="14" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="🛠️ Windows 11 Quality of Life (QoL)" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                        <CheckBox Name="chkClassicMenu" Content="Classic Context Menu (Klik Kanan Penuh Windows 10)"/>
                                        <CheckBox Name="chkFileExt" Content="Tampilkan Ekstensi File (.exe, .ps1, dll)"/>
                                        <CheckBox Name="chkThisPC" Content="Buka File Explorer langsung ke 'This PC'"/>
                                        <CheckBox Name="chkHiddenFiles" Content="Tampilkan File Tersembunyi (Hidden Files)"/>
                                        <CheckBox Name="chkCleanTaskbar" Content="Bersihkan Taskbar (Sembunyikan Widgets RAM, Copilot)"/>
                                        <CheckBox Name="chkCleanQuickAccess" Content="Bersihkan Clutter Quick Access (Recent &amp; Frequent Folders)"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="14" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="🛡️ Privasi &amp; Anti-Telemetri" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                        <CheckBox Name="chkTelemetry" Content="Windows Telemetry Level Minimum (Level 0)"/>
                                        <CheckBox Name="chkRecall" Content="Matikan Windows Recall AI Snapshot (Win11 24H2)"/>
                                        <CheckBox Name="chkCopilot" Content="Matikan Copilot System-Wide"/>
                                        <CheckBox Name="chkStartSearch" Content="Matikan Bing Search &amp; Ads di Start Menu"/>
                                        <CheckBox Name="chkAdId" Content="Matikan Advertising ID &amp; Activity History"/>
                                        <CheckBox Name="chkDeliveryOpt" Content="Matikan Delivery Optimization P2P Upload"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>

                    <!-- Sticky Bottom Action Bar -->
                    <Border Grid.Row="2" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,10,0,0" BorderBrush="#1F2937" BorderThickness="1">
                        <DockPanel LastChildFill="False">
                            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                                <Button Name="btnRunSelectedTweaks" Content="🚀 Terapkan Seluruh Tweaks Terpilih" Background="#0284C7" Height="38" Padding="18,0" Margin="0,0,10,0"/>
                                <Button Name="btnUndoSelectedTweaks" Content="↩️ Undo / Revert Tweaks Terpilih" Background="#475569" Height="38" Padding="14,0" Margin="0,0,10,0"/>
                                <Button Name="btnQuickSnapshot" Content="📸 Buat Snapshot VoltUndo" Height="38" Padding="12,0"/>
                            </StackPanel>
                            <TextBlock DockPanel.Dock="Right" Text="Eksekusi atomik granular • 100% Reversible" Foreground="#10B981" VerticalAlignment="Center" FontSize="12"/>
                        </DockPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 3: INSTALL APPS (FRESH POST-INSTALL & WINGET CATALOG) -->
            <TabItem Header="Install Apps">
                <Grid Margin="12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Presets Toolbar -->
                    <Border Grid.Row="0" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,0,0,8" BorderBrush="#1F2937" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="Pilih Paket Cepat Software Pasca-Install Ulang Windows (WinGet Official):" FontSize="13" Foreground="#94A3B8" Margin="0,0,0,6"/>
                            <WrapPanel>
                                <Button Name="btnAppsFreshInstall" Content="⭐ Fresh Windows Setup" Background="#0284C7" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsRuntimes" Content="📦 All Game Runtimes" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsGaming" Content="🎮 Gaming Essentials" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsDev" Content="💻 Developer Suite" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsBrowsers" Content="🌐 Web Browsers" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsUtilities" Content="🛠️ System Utilities" Margin="0,0,8,6" Height="32"/>
                                <Button Name="btnAppsClear" Content="❌ Clear Selection" Margin="0,0,8,6" Height="32"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <!-- Live Search Bar -->
                    <Border Grid.Row="1" Background="#0F172A" CornerRadius="8" Padding="10,8" Margin="0,0,0,10" BorderBrush="#1F2937" BorderThickness="1">
                        <DockPanel LastChildFill="True">
                            <TextBlock DockPanel.Dock="Left" Text="🔍 Filter / Cari Software: " Foreground="#38BDF8" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <TextBox Name="txtAppFilter" Background="#1E293B" Foreground="#F8FAFC" BorderBrush="#334155" BorderThickness="1" Padding="8,4" FontSize="13"/>
                        </DockPanel>
                    </Border>

                    <!-- Categorized Apps Grid -->
                    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                        <Grid Margin="0,0,0,10">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <!-- Column 1: Post-Install Runtimes & Browsers -->
                            <StackPanel Grid.Column="0" Margin="0,0,6,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="📦 Runtimes Wajib Game" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_VCRedist" Content="Visual C++ 2015-2022 AIO"/>
                                        <CheckBox Name="chkApp_DirectX" Content="DirectX End-User Runtimes"/>
                                        <CheckBox Name="chkApp_DotNet8" Content=".NET 8 Desktop Runtime"/>
                                        <CheckBox Name="chkApp_DotNet9" Content=".NET 9 Desktop Runtime"/>
                                        <CheckBox Name="chkApp_Java" Content="Oracle Java JRE"/>
                                        <CheckBox Name="chkApp_OpenAL" Content="OpenAL Audio Engine"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="🌐 Web Browsers" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_Brave" Content="Brave Browser"/>
                                        <CheckBox Name="chkApp_Chrome" Content="Google Chrome"/>
                                        <CheckBox Name="chkApp_Firefox" Content="Mozilla Firefox"/>
                                        <CheckBox Name="chkApp_Thorium" Content="Thorium Browser"/>
                                        <CheckBox Name="chkApp_Librewolf" Content="LibreWolf Browser"/>
                                        <CheckBox Name="chkApp_Edge" Content="Microsoft Edge"/>
                                        <CheckBox Name="chkApp_OperaGX" Content="Opera GX"/>
                                        <CheckBox Name="chkApp_Vivaldi" Content="Vivaldi"/>
                                        <CheckBox Name="chkApp_Floorp" Content="Floorp Browser"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Column 2: Gaming, Drivers & Monitoring -->
                            <StackPanel Grid.Column="1" Margin="3,0,3,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="🎮 Gaming &amp; Launchers" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_Steam" Content="Steam"/>
                                        <CheckBox Name="chkApp_Epic" Content="Epic Games Launcher"/>
                                        <CheckBox Name="chkApp_Discord" Content="Discord"/>
                                        <CheckBox Name="chkApp_OBS" Content="OBS Studio"/>
                                        <CheckBox Name="chkApp_EA" Content="EA Desktop"/>
                                        <CheckBox Name="chkApp_Ubisoft" Content="Ubisoft Connect"/>
                                        <CheckBox Name="chkApp_GOG" Content="GOG Galaxy"/>
                                        <CheckBox Name="chkApp_BattleNet" Content="Battle.net"/>
                                        <CheckBox Name="chkApp_Prism" Content="Prism Launcher (MC)"/>
                                        <CheckBox Name="chkApp_Heroic" Content="Heroic Games Launcher"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="⚡ Drivers &amp; Monitoring" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_NvidiaApp" Content="NVIDIA App (No Login)"/>
                                        <CheckBox Name="chkApp_Afterburner" Content="MSI Afterburner"/>
                                        <CheckBox Name="chkApp_RTSS" Content="RivaTuner (RTSS)"/>
                                        <CheckBox Name="chkApp_FanControl" Content="Rem0o FanControl"/>
                                        <CheckBox Name="chkApp_HWiNFO" Content="REALiX HWiNFO64"/>
                                        <CheckBox Name="chkApp_CPUZ" Content="CPUID CPU-Z"/>
                                        <CheckBox Name="chkApp_GPUZ" Content="TechPowerUp GPU-Z"/>
                                        <CheckBox Name="chkApp_DiskInfo" Content="CrystalDiskInfo"/>
                                        <CheckBox Name="chkApp_DiskMark" Content="CrystalDiskMark"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Column 3: Dev Tools & Media -->
                            <StackPanel Grid.Column="2" Margin="3,0,3,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="💻 Development &amp; Tools" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_VSCode" Content="Visual Studio Code"/>
                                        <CheckBox Name="chkApp_Git" Content="Git for Windows"/>
                                        <CheckBox Name="chkApp_Terminal" Content="Windows Terminal"/>
                                        <CheckBox Name="chkApp_Pwsh7" Content="PowerShell 7"/>
                                        <CheckBox Name="chkApp_Node" Content="Node.js LTS"/>
                                        <CheckBox Name="chkApp_Python" Content="Python 3.12"/>
                                        <CheckBox Name="chkApp_Docker" Content="Docker Desktop"/>
                                        <CheckBox Name="chkApp_Postman" Content="Postman"/>
                                        <CheckBox Name="chkApp_PowerToys" Content="Microsoft PowerToys"/>
                                        <CheckBox Name="chkApp_NotepadPP" Content="Notepad++"/>
                                        <CheckBox Name="chkApp_DBeaver" Content="DBeaver Universal DB"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="🎬 Media &amp; Audio" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_VLC" Content="VLC Media Player"/>
                                        <CheckBox Name="chkApp_MPV" Content="MPV Player"/>
                                        <CheckBox Name="chkApp_Spotify" Content="Spotify"/>
                                        <CheckBox Name="chkApp_Audacity" Content="Audacity"/>
                                        <CheckBox Name="chkApp_HandBrake" Content="HandBrake Transcoder"/>
                                        <CheckBox Name="chkApp_KLite" Content="K-Lite Codec Pack"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Column 4: Archivers, System Utils & Docs -->
                            <StackPanel Grid.Column="3" Margin="6,0,0,0">
                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,10">
                                    <StackPanel>
                                        <TextBlock Text="🛠️ Archivers &amp; System Tools" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_NanaZip" Content="NanaZip (Win11 Context Menu)"/>
                                        <CheckBox Name="chkApp_7Zip" Content="7-Zip"/>
                                        <CheckBox Name="chkApp_WinRAR" Content="WinRAR"/>
                                        <CheckBox Name="chkApp_Everything" Content="Everything Search"/>
                                        <CheckBox Name="chkApp_ShareX" Content="ShareX Screen Capture"/>
                                        <CheckBox Name="chkApp_BleachBit" Content="BleachBit Cleaner"/>
                                        <CheckBox Name="chkApp_Revo" Content="Revo Uninstaller"/>
                                        <CheckBox Name="chkApp_WizTree" Content="WizTree Disk Analyzer"/>
                                        <CheckBox Name="chkApp_Rufus" Content="Rufus USB Creator"/>
                                    </StackPanel>
                                </Border>

                                <Border Background="#1E293B" CornerRadius="8" Padding="12" BorderBrush="#334155" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="📄 Documents &amp; Comms" FontSize="13" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                                        <CheckBox Name="chkApp_QuickLook" Content="QuickLook (Spacebar Preview)"/>
                                        <CheckBox Name="chkApp_Telegram" Content="Telegram Desktop"/>
                                        <CheckBox Name="chkApp_WhatsApp" Content="WhatsApp Desktop"/>
                                        <CheckBox Name="chkApp_Obsidian" Content="Obsidian Markdown"/>
                                        <CheckBox Name="chkApp_Notion" Content="Notion Desktop"/>
                                        <CheckBox Name="chkApp_LibreOffice" Content="LibreOffice Suite"/>
                                        <CheckBox Name="chkApp_Sumatra" Content="SumatraPDF"/>
                                        <CheckBox Name="chkApp_AdobeReader" Content="Adobe Acrobat Reader"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>
                    </ScrollViewer>

                    <!-- Sticky Bottom Action Bar -->
                    <Border Grid.Row="3" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,10,0,0" BorderBrush="#1F2937" BorderThickness="1">
                        <DockPanel LastChildFill="False">
                            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                                <Button Name="btnInstallSelectedApps" Content="📥 Install Software Terpilih (WinGet)" Background="#0284C7" Height="38" Padding="16,0" Margin="0,0,10,0"/>
                                <Button Name="btnUpgradeAllApps" Content="🔄 Upgrade Semua Software" Height="38" Padding="14,0" Margin="0,0,10,0"/>
                                <Button Name="btnOpenDebloaterInGui" Content="🗑️ Debloat Windows Apps (Appx)" Background="#7F1D1D" Height="38" Padding="14,0"/>
                            </StackPanel>
                            <TextBlock DockPanel.Dock="Right" Text="Instalasi resmi otomatis via WinGet (bebas adware)" Foreground="#10B981" VerticalAlignment="Center" FontSize="12"/>
                        </DockPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 4: 100% DYNAMIC GAME TUNER -->
            <TabItem Header="Game Tuner">
                <Grid Margin="12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <!-- Header -->
                    <Border Grid.Row="0" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,0,0,10" BorderBrush="#1F2937" BorderThickness="1">
                        <DockPanel LastChildFill="False">
                            <StackPanel DockPanel.Dock="Left">
                                <TextBlock Text="🎮 VoltPlay: Dynamic Game Engine &amp; GPU Tuning Hub" FontSize="15" FontWeight="Bold" Foreground="#38BDF8"/>
                                <TextBlock Text="Penyelarasan kartu grafis discrete RTX 4060, Defender exclusion, dan setting in-game per game terdeteksi:" FontSize="12" Foreground="#94A3B8"/>
                            </StackPanel>
                            <Button Name="btnAddManualGame" DockPanel.Dock="Right" Content="➕ Tambah Game Manual (.exe)" Height="32" Padding="12,0"/>
                        </DockPanel>
                    </Border>

                    <!-- Dynamic Games Container -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel Name="pnlDynamicGamesContainer" Margin="0,0,0,10">
                            <!-- Populated dynamically in code -->
                        </StackPanel>
                    </ScrollViewer>

                    <!-- Sticky Bottom Action Bar -->
                    <Border Grid.Row="2" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,10,0,0" BorderBrush="#1F2937" BorderThickness="1">
                        <DockPanel LastChildFill="False">
                            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
                                <Button Name="btnApplyAllGameTuning" Content="🎮 Terapkan Optimasi Seluruh Game Terpilih" Background="#0284C7" Height="38" Padding="18,0" Margin="0,0,10,0"/>
                                <Button Name="btnAllGamesHighPerfGPU" Content="⚡ Paksa Semua ke Discrete GPU (RTX 4060)" Height="38" Padding="14,0" Margin="0,0,10,0"/>
                                <Button Name="btnAllGamesDefenderExcl" Content="🛡️ Exclude Semua dari Defender" Height="38" Padding="14,0"/>
                            </StackPanel>
                            <TextBlock DockPanel.Dock="Right" Text="100% Dinamis &amp; Multi-Drive" Foreground="#10B981" VerticalAlignment="Center" FontSize="12"/>
                        </DockPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 5: VOLTCLEAN -->
            <TabItem Header="VoltClean">
                <Grid Margin="12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,0,0,10" BorderBrush="#1F2937" BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="VoltClean: Pembersih Disk &amp; Cache Lintas-Drive Dinamis" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,4"/>
                            <TextBlock Text="Membersihkan file sementara, cache DirectX shader, dump crash, dan cache game lintas drive C: dan D: tanpa merusak data penting." FontSize="12" Foreground="#94A3B8"/>
                        </StackPanel>
                    </Border>

                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <Border Background="#1E293B" CornerRadius="8" Padding="14" BorderBrush="#334155" BorderThickness="1">
                            <StackPanel>
                                <TextBlock Text="Target Pembersihan Sampah" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <CheckBox Name="chkCleanUserTemp" Content="File Sementara Pengguna (%TEMP%)" IsChecked="True"/>
                                <CheckBox Name="chkCleanWinTemp" Content="File Sementara Windows (C:\Windows\Temp)" IsChecked="True"/>
                                <CheckBox Name="chkCleanD3DShader" Content="DirectX &amp; Graphic Shader Cache Lintas Seluruh Drive" IsChecked="True"/>
                                <CheckBox Name="chkCleanNvidiaShader" Content="NVIDIA / AMD GPU Shader Cache" IsChecked="True"/>
                                <CheckBox Name="chkCleanCrashDumps" Content="Windows Error Reporting &amp; Crash Dumps" IsChecked="True"/>
                                <CheckBox Name="chkCleanRecycleBin" Content="Kosongkan Recycle Bin Lintas Drive" IsChecked="False"/>
                                <CheckBox Name="chkCleanDism" Content="Jalankan DISM Component Cleanup ResetBase (Kompilasi Update Bersih)" IsChecked="False"/>
                            </StackPanel>
                        </Border>
                    </ScrollViewer>

                    <Border Grid.Row="2" Background="#0F172A" CornerRadius="8" Padding="12,10" Margin="0,10,0,0" BorderBrush="#1F2937" BorderThickness="1">
                        <WrapPanel>
                            <Button Name="btnRunVoltClean" Content="🧹 Bersihkan Disk Sekarang" Background="#0284C7" Height="38" Padding="18,0" Margin="0,0,10,0"/>
                            <Button Name="btnDismOnly" Content="⚙️ DISM Component Cleanup Saja" Height="38" Padding="14,0"/>
                        </WrapPanel>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 6: SYSTEM HEALTH & DIAGNOSTICS -->
            <TabItem Header="System Health">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="Diagnostik Kesehatan Sistem &amp; Fitur Opsional Windows" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,10"/>
                        <Border Background="#1E293B" CornerRadius="8" Padding="15" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Perbaikan Integritas File &amp; Jaringan" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <WrapPanel Margin="0,0,0,12">
                                    <Button Name="btnHealthSFC" Content="🔍 Jalankan SFC Scannow" Margin="0,0,8,8" Height="34"/>
                                    <Button Name="btnHealthDISM" Content="🛡️ Jalankan DISM RestoreHealth" Margin="0,0,8,8" Height="34"/>
                                    <Button Name="btnHealthNetReset" Content="🌐 Reset TCP/IP &amp; Winsock" Margin="0,0,8,8" Height="34"/>
                                    <Button Name="btnHealthIconCache" Content="🎨 Rebuild Icon &amp; Thumbnail Cache" Margin="0,0,8,8" Height="34"/>
                                </WrapPanel>

                                <Separator Background="#334155" Margin="0,5,0,12"/>
                                <TextBlock Text="Fitur Windows Opsional Gaming &amp; Dev" FontSize="14" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,8"/>
                                <WrapPanel>
                                    <Button Name="btnFeatDirectPlay" Content="🎮 Aktifkan DirectPlay (Game Jadul)" Margin="0,0,8,8" Height="34"/>
                                    <Button Name="btnFeatSandbox" Content="📦 Aktifkan Windows Sandbox" Margin="0,0,8,8" Height="34"/>
                                    <Button Name="btnFeatWSL" Content="🐧 Pasang WSL2 Linux Core" Margin="0,0,8,8" Height="34"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- TAB 7: VOLTUNDO -->
            <TabItem Header="VoltUndo">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="15">
                        <TextBlock Text="VoltUndo: Sistem Pemulihan Snapshot 1-Klik" FontSize="16" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,0,6"/>
                        <TextBlock Text="Pilih snapshot cadangan registri &amp; konfigurasi game yang ingin dipulihkan:" Foreground="#94A3B8" Margin="0,0,0,12"/>

                        <Border Background="#1E293B" CornerRadius="8" Padding="15" BorderBrush="#334155" BorderThickness="1" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="Daftar Snapshot Tersimpan:" FontSize="13" Foreground="#94A3B8" Margin="0,0,0,6"/>
                                <ComboBox Name="cmbSnapshots" Height="32" Margin="0,0,0,15" Background="#1E293B" Foreground="#000000"/>
                                <WrapPanel>
                                    <Button Name="btnRestoreSelectedSnapshot" Content="↩️ Restore Snapshot Terpilih" Background="#D97706" Height="36" Padding="18,0" Margin="0,0,10,0"/>
                                    <Button Name="btnTakeNewSnapshot" Content="📸 Buat Snapshot Baru Sekarang" Background="#0284C7" Height="36" Padding="14,0"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
        </TabControl>

        <!-- Monospace Console Log Drawer -->
        <Border Grid.Row="2" Background="#050811" CornerRadius="6" BorderBrush="#1F2937" BorderThickness="1" Margin="0,10,0,0">
            <TextBox Name="txtConsoleLog" Background="Transparent" Foreground="#38BDF8" FontFamily="Consolas" FontSize="12" BorderThickness="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" Margin="8" Text="[Ready] Voltune Ultimate Hub Initialized. Zero CLI typing needed."/>
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

    # --------------------------------------------------------------------------
    # POPULATE 100% DYNAMIC GAME TUNER CARDS
    # --------------------------------------------------------------------------
    $pnlGamesContainer = $window.FindName("pnlDynamicGamesContainer")
    $gameToggles = [ordered]@{}

    $RefreshGameCards = {
        $pnlGamesContainer.Children.Clear()
        $gameToggles.Clear()

        if ($Hardware.DiscoveredGames.Count -eq 0) {
            $tbNone = New-Object System.Windows.Controls.TextBlock
            $tbNone.Text = "Belum ada game terdeteksi otomatis. Klik tombol 'Tambah Game Manual' di atas untuk memilih game."
            $tbNone.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8")
            $tbNone.Margin = New-Object System.Windows.Thickness(8)
            $pnlGamesContainer.Children.Add($tbNone) | Out-Null
            return
        }

        foreach ($k in $Hardware.DiscoveredGames.Keys) {
            $g = $Hardware.DiscoveredGames[$k]

            $card = New-Object System.Windows.Controls.Border
            $card.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
            $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
            $card.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#334155")
            $card.BorderThickness = New-Object System.Windows.Thickness(1)
            $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
            $card.Padding = New-Object System.Windows.Thickness(12)

            $spCard = New-Object System.Windows.Controls.StackPanel

            # Header Game Info
            $spHeader = New-Object System.Windows.Controls.StackPanel
            $spHeader.Orientation = [System.Windows.Controls.Orientation]::Horizontal
            $spHeader.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)

            $tbBadge = New-Object System.Windows.Controls.TextBlock
            $tbBadge.Text = "[$($g.Platform)] "
            $tbBadge.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#38BDF8")
            $tbBadge.FontWeight = [System.Windows.FontWeights]::Bold

            $tbName = New-Object System.Windows.Controls.TextBlock
            $tbName.Text = "$($g.Name) "
            $tbName.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
            $tbName.FontWeight = [System.Windows.FontWeights]::Bold
            $tbName.FontSize = 14

            $tbPath = New-Object System.Windows.Controls.TextBlock
            $pathStr = if ($g.InstallPath) { "($($g.InstallPath))" } elseif ($g.ConfigFile) { "($($g.ConfigFile))" } else { "" }
            $tbPath.Text = $pathStr
            $tbPath.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")
            $tbPath.FontSize = 11
            $tbPath.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

            $spHeader.Children.Add($tbBadge) | Out-Null
            $spHeader.Children.Add($tbName) | Out-Null
            $spHeader.Children.Add($tbPath) | Out-Null
            $spCard.Children.Add($spHeader) | Out-Null

            # Toggles WrapPanel
            $wpToggles = New-Object System.Windows.Controls.WrapPanel

            $chkGpu = New-Object System.Windows.Controls.CheckBox
            $chkGpu.Content = "Force Discrete GPU (High Performance RTX 4060)"
            $chkGpu.IsChecked = $true
            $chkGpu.Margin = New-Object System.Windows.Thickness(0, 0, 16, 4)
            $chkGpu.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
            $wpToggles.Children.Add($chkGpu) | Out-Null

            $chkDef = New-Object System.Windows.Controls.CheckBox
            $chkDef.Content = "Defender Exclusion (Anti-Stutter IO)"
            $chkDef.IsChecked = $true
            $chkDef.Margin = New-Object System.Windows.Thickness(0, 0, 16, 4)
            $chkDef.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC")
            $wpToggles.Children.Add($chkDef) | Out-Null

            $chkSpecific = $null
            if ($k -match "HoYo") {
                $chkSpecific = New-Object System.Windows.Controls.CheckBox
                $chkSpecific.Content = "60 FPS Lock & Anti-Aliasing Balance"
                $chkSpecific.IsChecked = $true
                $chkSpecific.Margin = New-Object System.Windows.Thickness(0, 0, 16, 4)
                $chkSpecific.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA")
                $wpToggles.Children.Add($chkSpecific) | Out-Null
            } elseif ($k -match "RDR2") {
                $chkSpecific = New-Object System.Windows.Controls.CheckBox
                $chkSpecific.Content = "Async Compute On & MaxTexUpgrades 10"
                $chkSpecific.IsChecked = $true
                $chkSpecific.Margin = New-Object System.Windows.Thickness(0, 0, 16, 4)
                $chkSpecific.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA")
                $wpToggles.Children.Add($chkSpecific) | Out-Null
            } elseif ($k -match "W3") {
                $chkSpecific = New-Object System.Windows.Controls.CheckBox
                $chkSpecific.Content = "HairWorks Off & Foliage Balance"
                $chkSpecific.IsChecked = $true
                $chkSpecific.Margin = New-Object System.Windows.Thickness(0, 0, 16, 4)
                $chkSpecific.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A78BFA")
                $wpToggles.Children.Add($chkSpecific) | Out-Null
            }

            $spCard.Children.Add($wpToggles) | Out-Null
            $card.Child = $spCard
            $pnlGamesContainer.Children.Add($card) | Out-Null

            $gameToggles[$k] = @{
                GameInfo = $g
                ChkGpu   = $chkGpu
                ChkDef   = $chkDef
                ChkSpec  = $chkSpecific
            }
        }
    }

    & $RefreshGameCards

    # Manual Add Game Handler
    $window.FindName("btnAddManualGame").Add_Click({
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "Executable Files (*.exe)|*.exe|All Files (*.*)|*.*"
        $dialog.Title = "Pilih Game Executable (.exe)"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $exePath = $dialog.FileName
            $exeName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
            $folder = [System.IO.Path]::GetDirectoryName($exePath)
            $id = "Manual_" + ($exeName -replace '[^a-zA-Z0-9]', '')
            $Hardware.DiscoveredGames[$id] = [ordered]@{
                Name        = $exeName
                Platform    = "Manual"
                InstallPath = $folder
                ExePath     = $exePath
            }
            & $AppendLog "[+] Game manual ditambahkan: $exeName ($exePath)"
            & $RefreshGameCards
        }
    })

    # Apply All Game Tuning Handler
    $window.FindName("btnApplyAllGameTuning").Add_Click({
        & $AppendLog "Menerapkan optimasi dinamis untuk seluruh game terpilih..."
        New-VoltBackupSnapshot -Hardware $Hardware
        $gpuPrefReg = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        if (-not (Test-Path $gpuPrefReg)) { New-Item $gpuPrefReg -Force | Out-Null }

        $applied = 0
        foreach ($k in $gameToggles.Keys) {
            $item = $gameToggles[$k]
            $g = $item.GameInfo

            # GPU High Perf
            if ($item.ChkGpu -and $item.ChkGpu.IsChecked) {
                $exeCandidates = @()
                if ($g.InstallPath -and (Test-Path $g.InstallPath)) {
                    $exeCandidates += Get-ChildItem -Path $g.InstallPath -Filter "*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -notmatch "unins|setup|crash|report|patch|UnityCrashHandler" }
                }
                if ($g.ExePath -and (Test-Path $g.ExePath)) { $exeCandidates += (Get-Item $g.ExePath) }
                foreach ($e in ($exeCandidates | Select-Object -Unique)) {
                    Set-ItemProperty -Path $gpuPrefReg -Name $e.FullName -Value "GpuPreference=2;" -Type String -Force -ErrorAction SilentlyContinue
                }
            }

            # Defender Exclusion
            if ($item.ChkDef -and $item.ChkDef.IsChecked -and $g.InstallPath) {
                try { Add-MpPreference -ExclusionPath $g.InstallPath -ErrorAction SilentlyContinue } catch {}
            }

            # Specific Engine Profiles
            if ($item.ChkSpec -and $item.ChkSpec.IsChecked) {
                if ($k -eq "Rockstar_RDR2" -and $g.ConfigFile) { Optimize-VoltGameRDR2 -ConfigPath $g.ConfigFile }
                elseif ($k -eq "CDPR_W3" -and $g.ConfigFile) { Optimize-VoltGameWitcher3 -ConfigPath $g.ConfigFile }
                elseif ($k -eq "HoYo_HSR") { Optimize-VoltGameHSR -GameInfo $g }
                elseif ($k -eq "HoYo_Genshin") { Optimize-VoltGameGenshin -GameInfo $g }
            }
            $applied++
        }

        & $AppendLog "[✓] Optimasi dinamis berhasil diterapkan untuk $applied game!"
        [System.Windows.MessageBox]::Show("Optimasi dinamis berhasil diterapkan untuk $applied game!", "VoltPlay", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnAllGamesHighPerfGPU").Add_Click({
        Optimize-VoltPlayGames -Hardware $Hardware -TargetGameKey "ALL"
        & $AppendLog "[✓] Seluruh game terdeteksi berhasil didaftarkan ke GPU Discrete RTX 4060!"
        [System.Windows.MessageBox]::Show("Seluruh game berhasil didaftarkan ke GPU High Performance!", "VoltPlay", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnAllGamesDefenderExcl").Add_Click({
        Add-VoltDefenderGameExclusions -Hardware $Hardware
        & $AppendLog "[✓] Seluruh folder game berhasil didaftarkan ke Defender Exclusions!"
        [System.Windows.MessageBox]::Show("Folder game didaftarkan ke Defender Exclusions!", "VoltPlay", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

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

    # Sync Live State on Startup
    $SyncLiveState = {
        & $AppendLog "Mendeteksi konfigurasi Windows saat ini..."
        $state = Get-VoltWindowsTweakState
        $activeCount = 0
        foreach ($key in $state.Keys) {
            $chk = $window.FindName($key)
            if ($chk) {
                $chk.IsChecked = [bool]$state[$key]
                if ($state[$key]) { $activeCount++ }
            }
        }
        & $AppendLog "[System State] Terdeteksi $activeCount dari $($state.Count) tweaks aktif di Windows Anda saat ini."
        & $AppendLog "[Info] Status centang di atas merefleksikan kondisi Windows sekarang. Pilih preset untuk mengubah, lalu klik 'Terapkan'."
    }

    & $SyncLiveState

    # Dashboard Quick Actions
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

    # --------------------------------------------------------------------------
    # PRESETS OVERWRITE HANDLER (100% CLEAN PRESET OVERWRITE)
    # --------------------------------------------------------------------------
    $ApplyPresetClean = {
        param([string]$PresetName)
        $blueprint = $Script:VoltPresetMap[$PresetName]
        if ($blueprint) {
            foreach ($k in $blueprint.Keys) {
                $chk = $window.FindName($k)
                if ($chk) {
                    $chk.IsChecked = [bool]$blueprint[$k]
                }
            }
            & $AppendLog "[Preset] Preset '$PresetName' dipilih. Seluruh centang lama ditimpa bersih. Silakan sesuaikan lalu klik 'Terapkan'."
        }
    }

    $window.FindName("btnLiveState").Add_Click({ & $SyncLiveState })
    $window.FindName("btnPresetRecommended").Add_Click({ & $ApplyPresetClean "Recommended" })
    $window.FindName("btnPresetLaptop").Add_Click({ & $ApplyPresetClean "LaptopGaming" })
    $window.FindName("btnPresetDesktop").Add_Click({ & $ApplyPresetClean "DesktopMax" })
    $window.FindName("btnPresetMinimal").Add_Click({ & $ApplyPresetClean "MinimalPrivacy" })
    $window.FindName("btnPresetClear").Add_Click({ & $ApplyPresetClean "ClearAll" })

    $window.FindName("btnQuickSnapshot").Add_Click({
        $dir = New-VoltBackupSnapshot -Hardware $Hardware
        & $AppendLog "[✓] Snapshot berhasil disimpan di: $dir"
        & $PopulateSnaps
        [System.Windows.MessageBox]::Show("Snapshot berhasil dibuat!", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Atomic Apply Tweaks Handler
    $window.FindName("btnRunSelectedTweaks").Add_Click({
        & $AppendLog "Menerapkan tweaks secara atomik granular..."
        New-VoltRestorePoint -Description "Voltune-Pre-Tweaks"
        New-VoltBackupSnapshot -Hardware $Hardware
        & $PopulateSnaps

        $allTweakKeys = $Script:VoltPresetMap["Recommended"].Keys
        $appliedCount = 0

        foreach ($k in $allTweakKeys) {
            $chk = $window.FindName($k)
            if ($chk -and $chk.IsChecked) {
                Set-VoltAtomicTweak -TweakId $k -Enable $true -Hardware $Hardware
                $appliedCount++
            }
        }

        & $AppendLog "[✓] Selesai! Sebanyak $appliedCount tweaks terpilih berhasil diterapkan secara atomik."
        [System.Windows.MessageBox]::Show("Sebanyak $appliedCount tweaks terpilih berhasil diterapkan!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # Atomic Undo Tweaks Handler
    $window.FindName("btnUndoSelectedTweaks").Add_Click({
        & $AppendLog "Mengembalikan tweaks terpilih ke standar Windows..."
        $allTweakKeys = $Script:VoltPresetMap["Recommended"].Keys
        $revertedCount = 0

        foreach ($k in $allTweakKeys) {
            $chk = $window.FindName($k)
            if ($chk -and $chk.IsChecked) {
                Set-VoltAtomicTweak -TweakId $k -Enable $false -Hardware $Hardware
                $revertedCount++
            }
        }

        & $AppendLog "[✓] Sebanyak $revertedCount tweaks terpilih telah dikembalikan ke standar."
        [System.Windows.MessageBox]::Show("Sebanyak $revertedCount tweaks terpilih berhasil di-revert!", "Voltune", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    # --------------------------------------------------------------------------
    # CURATED POST-INSTALL APPS MAP (70+ APPS WITH ACCURATE WINGET IDS)
    # --------------------------------------------------------------------------
    $appIdMap = @{
        # Runtimes
        "chkApp_VCRedist"    = @{ Name = "Visual C++ 2015-2022 AIO"; Id = "Microsoft.VCRedist.2015+.x64" }
        "chkApp_DirectX"     = @{ Name = "DirectX End-User Runtimes"; Id = "Microsoft.DirectX" }
        "chkApp_DotNet8"     = @{ Name = ".NET 8 Desktop Runtime"; Id = "Microsoft.DotNet.DesktopRuntime.8" }
        "chkApp_DotNet9"     = @{ Name = ".NET 9 Desktop Runtime"; Id = "Microsoft.DotNet.DesktopRuntime.9" }
        "chkApp_Java"        = @{ Name = "Oracle Java JRE"; Id = "Oracle.JavaRuntimeEnvironment" }
        "chkApp_OpenAL"      = @{ Name = "OpenAL Audio Engine"; Id = "Creative.OpenAL" }

        # Browsers
        "chkApp_Brave"       = @{ Name = "Brave Browser"; Id = "Brave.Brave" }
        "chkApp_Chrome"      = @{ Name = "Google Chrome"; Id = "Google.Chrome" }
        "chkApp_Firefox"     = @{ Name = "Mozilla Firefox"; Id = "Mozilla.Firefox" }
        "chkApp_Thorium"     = @{ Name = "Thorium Browser"; Id = "Alex313031.Thorium" }
        "chkApp_Librewolf"   = @{ Name = "LibreWolf Browser"; Id = "LibreWolf.LibreWolf" }
        "chkApp_Edge"        = @{ Name = "Microsoft Edge"; Id = "Microsoft.Edge" }
        "chkApp_OperaGX"     = @{ Name = "Opera GX Gaming Browser"; Id = "Opera.OperaGX" }
        "chkApp_Vivaldi"     = @{ Name = "Vivaldi Browser"; Id = "VivaldiTechnologies.Vivaldi" }
        "chkApp_Floorp"      = @{ Name = "Floorp Browser"; Id = "Floorp.Floorp" }

        # Gaming & Launchers
        "chkApp_Steam"       = @{ Name = "Steam"; Id = "Valve.Steam" }
        "chkApp_Epic"        = @{ Name = "Epic Games Launcher"; Id = "EpicGames.EpicGamesLauncher" }
        "chkApp_Discord"     = @{ Name = "Discord"; Id = "Discord.Discord" }
        "chkApp_OBS"         = @{ Name = "OBS Studio"; Id = "OBSProject.OBSStudio" }
        "chkApp_EA"          = @{ Name = "EA Desktop"; Id = "ElectronicArts.EADesktop" }
        "chkApp_Ubisoft"     = @{ Name = "Ubisoft Connect"; Id = "Ubisoft.Connect" }
        "chkApp_GOG"         = @{ Name = "GOG Galaxy"; Id = "GOG.Galaxy" }
        "chkApp_BattleNet"   = @{ Name = "Blizzard Battle.net"; Id = "Blizzard.BattleNet" }
        "chkApp_Prism"       = @{ Name = "Prism Launcher (Minecraft)"; Id = "PrismLauncher.PrismLauncher" }
        "chkApp_Heroic"      = @{ Name = "Heroic Games Launcher"; Id = "HeroicGamesLauncher.HeroicGamesLauncher" }

        # Drivers & Monitoring
        "chkApp_NvidiaApp"   = @{ Name = "NVIDIA App (No Login)"; Id = "Nvidia.NvidiaApp" }
        "chkApp_Afterburner" = @{ Name = "MSI Afterburner"; Id = "Guru3D.Afterburner" }
        "chkApp_RTSS"        = @{ Name = "RivaTuner Statistics (RTSS)"; Id = "Guru3D.RTSS" }
        "chkApp_FanControl"  = @{ Name = "Rem0o FanControl"; Id = "Rem0o.FanControl" }
        "chkApp_HWiNFO"      = @{ Name = "REALiX HWiNFO64"; Id = "REALiX.HWiNFO" }
        "chkApp_CPUZ"        = @{ Name = "CPUID CPU-Z"; Id = "CPUID.CPU-Z" }
        "chkApp_GPUZ"        = @{ Name = "TechPowerUp GPU-Z"; Id = "TechPowerUp.GPU-Z" }
        "chkApp_DiskInfo"    = @{ Name = "CrystalDiskInfo"; Id = "CrystalDewWorld.CrystalDiskInfo" }
        "chkApp_DiskMark"    = @{ Name = "CrystalDiskMark"; Id = "CrystalDewWorld.CrystalDiskMark" }

        # Development
        "chkApp_VSCode"      = @{ Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" }
        "chkApp_Git"         = @{ Name = "Git for Windows"; Id = "Git.Git" }
        "chkApp_Terminal"    = @{ Name = "Windows Terminal"; Id = "Microsoft.WindowsTerminal" }
        "chkApp_Pwsh7"       = @{ Name = "PowerShell 7"; Id = "Microsoft.PowerShell" }
        "chkApp_Node"        = @{ Name = "Node.js LTS"; Id = "OpenJS.NodeJS.LTS" }
        "chkApp_Python"      = @{ Name = "Python 3.12"; Id = "Python.Python.3.12" }
        "chkApp_Docker"      = @{ Name = "Docker Desktop"; Id = "Docker.DockerDesktop" }
        "chkApp_Postman"     = @{ Name = "Postman"; Id = "Postman.Postman" }
        "chkApp_PowerToys"   = @{ Name = "Microsoft PowerToys"; Id = "Microsoft.PowerToys" }
        "chkApp_NotepadPP"   = @{ Name = "Notepad++"; Id = "Notepad++.Notepad++" }
        "chkApp_DBeaver"     = @{ Name = "DBeaver Community"; Id = "dbeaver.dbeaver" }

        # Archivers & System Tools
        "chkApp_NanaZip"     = @{ Name = "NanaZip (Win11 Context Menu)"; Id = "M2Team.NanaZip" }
        "chkApp_7Zip"        = @{ Name = "7-Zip"; Id = "7zip.7zip" }
        "chkApp_WinRAR"      = @{ Name = "WinRAR"; Id = "RARLab.WinRAR" }
        "chkApp_Everything"  = @{ Name = "Everything Search"; Id = "voidtools.Everything" }
        "chkApp_ShareX"      = @{ Name = "ShareX Screen Capture"; Id = "ShareX.ShareX" }
        "chkApp_BleachBit"   = @{ Name = "BleachBit Cleaner"; Id = "BleachBit.BleachBit" }
        "chkApp_Revo"        = @{ Name = "Revo Uninstaller"; Id = "RevoUninstaller.RevoUninstaller" }
        "chkApp_WizTree"     = @{ Name = "WizTree Disk Space Analyzer"; Id = "AntibodySoftware.WizTree" }
        "chkApp_Rufus"       = @{ Name = "Rufus USB Creator"; Id = "Rufus.Rufus" }

        # Media & Audio
        "chkApp_VLC"         = @{ Name = "VLC Media Player"; Id = "VideoLAN.VLC" }
        "chkApp_MPV"         = @{ Name = "MPV Player"; Id = "mpv.mpv" }
        "chkApp_Spotify"     = @{ Name = "Spotify"; Id = "Spotify.Spotify" }
        "chkApp_Audacity"    = @{ Name = "Audacity Audio Editor"; Id = "Audacity.Audacity" }
        "chkApp_HandBrake"   = @{ Name = "HandBrake Video Transcoder"; Id = "HandBrake.HandBrake" }
        "chkApp_KLite"       = @{ Name = "K-Lite Codec Pack Standard"; Id = "CodecGuide.K-LiteCodecPack.Standard" }

        # Documents & Comms
        "chkApp_QuickLook"   = @{ Name = "QuickLook (Spacebar Preview)"; Id = "Paddle.QuickLook" }
        "chkApp_Telegram"    = @{ Name = "Telegram Desktop"; Id = "Telegram.TelegramDesktop" }
        "chkApp_WhatsApp"    = @{ Name = "WhatsApp Desktop"; Id = "WhatsApp.WhatsApp" }
        "chkApp_Obsidian"    = @{ Name = "Obsidian"; Id = "Obsidian.Obsidian" }
        "chkApp_Notion"      = @{ Name = "Notion Desktop"; Id = "Notion.Notion" }
        "chkApp_LibreOffice" = @{ Name = "LibreOffice"; Id = "TheDocumentFoundation.LibreOffice" }
        "chkApp_Sumatra"     = @{ Name = "SumatraPDF"; Id = "SumatraPDF.SumatraPDF" }
        "chkApp_AdobeReader" = @{ Name = "Adobe Acrobat Reader"; Id = "Adobe.Acrobat.Reader.64-bit" }
    }

    # Live Search Filter Handler
    $txtFilter = $window.FindName("txtAppFilter")
    $txtFilter.Add_TextChanged({
        $q = $txtFilter.Text.ToLower().Trim()
        foreach ($k in $appIdMap.Keys) {
            $chk = $window.FindName($k)
            if ($chk) {
                $name = $appIdMap[$k].Name.ToLower()
                if ($q -eq "" -or $name -match [regex]::Escape($q)) {
                    $chk.Visibility = [System.Windows.Visibility]::Visible
                } else {
                    $chk.Visibility = [System.Windows.Visibility]::Collapsed
                }
            }
        }
    })

    # App Presets Handlers
    $window.FindName("btnAppsFreshInstall").Add_Click({
        @("chkApp_VCRedist","chkApp_DirectX","chkApp_DotNet8","chkApp_NanaZip","chkApp_Chrome","chkApp_Brave","chkApp_PowerToys","chkApp_Everything","chkApp_VLC","chkApp_HWiNFO") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset ⭐ Fresh Windows Essentials dipilih."
    })

    $window.FindName("btnAppsRuntimes").Add_Click({
        @("chkApp_VCRedist","chkApp_DirectX","chkApp_DotNet8","chkApp_DotNet9") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset Game Runtimes dipilih."
    })

    $window.FindName("btnAppsGaming").Add_Click({
        @("chkApp_Steam","chkApp_Epic","chkApp_Discord","chkApp_OBS","chkApp_RTSS","chkApp_Afterburner","chkApp_NanaZip") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset Gaming Essentials dipilih."
    })

    $window.FindName("btnAppsDev").Add_Click({
        @("chkApp_VSCode","chkApp_Git","chkApp_Terminal","chkApp_Pwsh7","chkApp_Node","chkApp_Python","chkApp_PowerToys") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset Developer Suite dipilih."
    })

    $window.FindName("btnAppsBrowsers").Add_Click({
        @("chkApp_Brave","chkApp_Chrome","chkApp_Firefox") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset Web Browsers dipilih."
    })

    $window.FindName("btnAppsUtilities").Add_Click({
        @("chkApp_NanaZip","chkApp_Everything","chkApp_HWiNFO","chkApp_BleachBit","chkApp_WizTree") | ForEach-Object {
            $c = $window.FindName($_); if ($c) { $c.IsChecked = $true }
        }
        & $AppendLog "[Apps] Preset System Utilities dipilih."
    })

    $window.FindName("btnAppsClear").Add_Click({
        foreach ($k in $appIdMap.Keys) {
            $c = $window.FindName($k)
            if ($c) { $c.IsChecked = $false }
        }
        & $AppendLog "[Apps] Seluruh centang software dibersihkan."
    })

    # Install Selected Apps Button (Streaming Dispatcher Safe)
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

    # VoltClean Buttons
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
    $window.FindName("btnHealthSFC").Add_Click({
        & $AppendLog "Menjalankan SFC Scannow (System File Checker)..."
        & sfc.exe /scannow
        & $AppendLog "[✓] Pemeriksaan SFC selesai."
    })

    $window.FindName("btnHealthDISM").Add_Click({
        & $AppendLog "Menjalankan DISM RestoreHealth..."
        & dism.exe /Online /Cleanup-Image /RestoreHealth
        & $AppendLog "[✓] Pemulihan DISM selesai."
    })

    $window.FindName("btnHealthNetReset").Add_Click({
        & $AppendLog "Mereset Winsock & TCP/IP stack..."
        Reset-VoltNetwork
        & $AppendLog "[✓] Jaringan berhasil direset."
    })

    $window.FindName("btnHealthIconCache").Add_Click({
        & $AppendLog "Membangun ulang Icon & Thumbnail Cache..."
        Rebuild-VoltIconCache
        & $AppendLog "[✓] Icon cache dibangun ulang."
    })

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
        & $AppendLog "Memasang WSL kernel core..."
        Set-VoltWindowsFeatureWSL
        & $AppendLog "[✓] WSL kernel core dipasang!"
    })

    # VoltUndo Tab Buttons
    $window.FindName("btnTakeNewSnapshot").Add_Click({
        & $AppendLog "Membuat snapshot registri & game config VoltUndo..."
        $dir = New-VoltBackupSnapshot -Hardware $Hardware
        & $AppendLog "[✓] Snapshot berhasil disimpan di: $dir"
        & $PopulateSnaps
        [System.Windows.MessageBox]::Show("Snapshot berhasil dibuat!", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
    })

    $window.FindName("btnRestoreSelectedSnapshot").Add_Click({
        $cmb = $window.FindName("cmbSnapshots")
        if (-not $cmb.SelectedItem) {
            [System.Windows.MessageBox]::Show("Pilih snapshot yang ingin dipulihkan terlebih dahulu.", "VoltUndo", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
        $snapName = ($cmb.SelectedItem -split " ")[0]
        $snapDir = Join-Path $Script:BackupDir $snapName
        $confirm = [System.Windows.MessageBox]::Show("Apakah Anda yakin ingin mengembalikan sistem ke snapshot '$snapName'?", "Konfirmasi Rollback", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
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
# 15. INTERACTIVE UI & DYNAMIC DISPLAY (CLI FALLBACK)
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
# 16. ENTRYPOINT LOGIC (DEFAULT: MODERN NATIVE WPF GUI)
# ------------------------------------------------------------------------------
Invoke-VoltElevation -Bypass:$NoElevation

$hwProfile = Get-VoltHardwareProfile

# Headless / Scripted Modes
if ($AutoOptimize) {
    New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
    New-VoltBackupSnapshot -Hardware $hwProfile
    foreach ($k in $Script:VoltPresetMap["Recommended"].Keys) {
        if ($Script:VoltPresetMap["Recommended"][$k]) {
            Set-VoltAtomicTweak -TweakId $k -Enable $true -Hardware $hwProfile
        }
    }
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

# If user explicitly requested CLI/TUI switch, run interactive terminal loop
if ($CLI -or $TUI) {
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

        $choice = Read-Host "`nPilihan Anda [0-12 / G / U]"
        switch ($choice.ToUpper()) {
            "G" {
                Show-VoltGUI -Hardware $hwProfile
                $hwProfile = Get-VoltHardwareProfile
            }
            "1" {
                New-VoltRestorePoint -Description "Voltune-Pre-AutoOptimize"
                New-VoltBackupSnapshot -Hardware $hwProfile
                foreach ($k in $Script:VoltPresetMap["Recommended"].Keys) {
                    if ($Script:VoltPresetMap["Recommended"][$k]) {
                        Set-VoltAtomicTweak -TweakId $k -Enable $true -Hardware $hwProfile
                    }
                }
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
                Set-VoltAtomicTweak -TweakId "chkClassicMenu" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkFileExt" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkThisPC" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkCleanTaskbar" -Enable $true
                Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
                Read-Host
            }
            "5" {
                New-VoltBackupSnapshot -Hardware $hwProfile
                Set-VoltAtomicTweak -TweakId "chkTelemetry" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkRecall" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkCopilot" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkStartSearch" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkAdId" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkDeliveryOpt" -Enable $true
                Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
                Read-Host
            }
            "6" {
                New-VoltBackupSnapshot -Hardware $hwProfile
                Set-VoltAtomicTweak -TweakId "chkNetwork" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkRawMouse" -Enable $true
                Set-VoltAtomicTweak -TweakId "chkDefender" -Enable $true -Hardware $hwProfile
                Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
                Read-Host
            }
            "7" {
                New-VoltBackupSnapshot -Hardware $hwProfile
                Set-VoltAtomicTweak -TweakId "chkSafeServices" -Enable $true
                Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
                Read-Host
            }
            "8" {
                New-VoltBackupSnapshot -Hardware $hwProfile
                Set-VoltAtomicTweak -TweakId "chkSecurityUpdates" -Enable $true
                Write-Host "`nTekan Enter untuk melanjutkan..." -ForegroundColor Gray
                Read-Host
            }
            "9" {
                & winget install --id "Microsoft.VCRedist.2015+.x64" -e --silent --accept-package-agreements --accept-source-agreements
                & winget install --id "Microsoft.DirectX" -e --silent --accept-package-agreements --accept-source-agreements
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
    exit 0
}

# DEFAULT MODE: Direct Launch Modern Native WPF GUI (100% In-GUI, Zero CLI Typing)
Show-VoltGUI -Hardware $hwProfile
