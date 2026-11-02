<p align="center">
  <img src="assets/banner.svg" alt="Voltune banner" width="100%">
</p>

# Voltune

**Universal Hardware-Aware Windows Performance, Gaming, Maintenance & Recovery Toolkit.**

Voltune v3.0 Ultimate mengadopsi model distribusi instan one-liner ala Chris Titus Tech (`winutil`), dilengkapi **Modern Native WPF GUI Desktop Hub**, **Hardware-Aware Display & Game Auto-Configurator**, **TCP/IP Gaming Latency Optimizer (Zero-VPN Harm)**, **Windows Services Optimizer**, **Windows Update Security-Only Lock**, serta pembersih disk lintas-drive **VoltClean** dan pemulihan 1-klik **VoltUndo**.

> **Safe by default. Reversible by design. 100% Dynamic. Zero VPN harm.**

---

## ⚡ Quick Start: One-Liner (Tanpa Install)

Cukup buka **PowerShell (Run as Administrator)** dan jalankan satu baris perintah berikut:

```powershell
irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex
```

Atau jalankan secara lokal dari direktori repositori:
```powershell
# Langsung buka Modern Native WPF Desktop Window (GUI - Mode Default)
.\voltune.ps1

# Atau jalankan menu interaktif Terminal (CLI / TUI)
.\voltune.ps1 -CLI
```

---

## 🚀 Fitur Unggulan v3.3 (Universal Ultimate)

1. **Modern Native WPF Desktop GUI (Default Mode & In-Window Hub):**
   - Tampilan antarmuka grafis modern bergaya Fluent Dark Theme dengan kontrol 100% di dalam GUI (tanpa perlu mengetik di terminal).
   - **Dynamic Live State Inspection**: Checkbox pada tab *Tweaks* otomatis memeriksa dan mencentang konfigurasi yang sudah aktif di Windows Anda saat ini.
   - **Atomic Tweaks Engine & Clean Preset Matrix**: Memilih preset (`Recommended`, `Laptop Gaming`, `Desktop Max`, `Minimal Privacy`) langsung menerapkan matriks pilihan bersih tanpa akumulasi centang lama. Setiap tweak dieksekusi secara granular per-item sesuai centang pilihan Anda.
   - **Sticky Bottom Action Bar**: Tombol aksi utama (*Terapkan*, *Undo*, *Snapshot*, *Install Apps*) dipin di bagian bawah tab sehingga selalu terlihat tanpa tertutup scroll.
2. **Katalog Software WinGet Komprehensif & Live Search (Fresh Install Toolkit):**
   - 9 Kategori lengkap: *Web Browsers, Game Runtimes & Libraries (VC++ AIO, DirectX, .NET 8), Utilities & Archives (NanaZip, 7-Zip, WinRAR, PowerToys), Gaming Launchers & Overlays (Steam, Epic, EA, GOG, Battle.net, Discord, OBS, RTSS), Hardware Drivers & Tools (NVIDIA App, HWiNFO64, CPU-Z, GPU-Z), Developer Tools (VS Code, Git, PowerShell 7, Windows Terminal, Docker), Social & Communication (Telegram, WhatsApp, Spotify), Media & Creativity, System Maintenance*.
   - **Live Search Bar**: Filter aplikasi secara instan dan interaktif berdasarkan nama dan ID WinGet saat Anda mengetik.
3. **Universal Dynamic Game Tuner (Card-Based Auto Generator):**
   - Memindai game secara dinamis dari Steam (semua drive via `libraryfolders.vdf`), Epic Games Store Manifests (`*.item`), GOG Galaxy, Ubisoft Connect, HoYoPlay, folder game standalone (`C:\Games\*`, `D:\Games\*`), registry uninstall, serta dokumen game setting.
   - Secara dinamis membuat kartu pengaturan interaktif per-game untuk konfigurasi GPU Discrete High Performance, pengecualian Windows Defender (anti-stutter asset streaming), dan tuning engine.
   - Dilengkapi tombol **Tambah Game Manual (.exe)** via File Dialog untuk mendaftarkan game portable apa pun.
4. **TCP/IP Gaming Latency Optimizer (Zero-VPN Harm):**
   - Menonaktifkan Nagle's Algorithm (`TcpAckFrequency = 1`, `TCPNoDelay = 1`) pada adapter fisik (Ethernet & Wi-Fi).
   - **Strict Whitelist Safety Guard:** Menjamin adapter virtual, TAP, dan Palo Alto GlobalProtect (`PanGPS`) dilewati secara aman tanpa merusak koneksi VPN perusahaan.
   - Menonaktifkan Network Throttling Index (`0xFFFFFFFF`) & `SystemResponsiveness = 0`.
5. **Windows Services Optimizer (Safe Gaming Profile):**
   - Mengoptimalkan layanan latar belakang bloat (`DiagTrack`, `dmwappushservice`, `MapsBroker`, `lfsvc`, `RemoteRegistry`, Xbox on-demand).
   - Layanan audio, printing, dan network VPN tetap terjaga 100%.
6. **Windows 11 QoL & Deep Privacy:**
   - Classic Right-Click Context Menu (Windows 10 style).
   - File Explorer Pro (tampilkan ekstensi file, buka ke This PC, tampilkan hidden files).
   - Taskbar Clean (sembunyikan Widgets RAM hog, Copilot, & Task View).
   - Matikan Windows Recall AI snapshot (Win11 24H2), Copilot system-wide, dan iklan Start Menu.
7. **Windows Update Control (Security Updates Only):**
   - Menunda feature update tahunan 365 hari agar OS selalu stabil.
   - Mencegah restart mendadak saat user aktif bekerja (`NoAutoRebootWithLoggedOnUsers = 1`).
   - Memblokir pembajakan driver GPU/Audio oleh Windows Update.
8. **VoltClean Cross-Drive Cleaner:**
   - Membersihkan `%TEMP%`, `C:\Windows\Temp`, shader cache multi-vendor (NVIDIA, AMD, Intel, DirectX), shader Steam di semua drive (C: & D:), crash dumps, dan Recycle Bin.
   - Dilindungi Dynamic Process Guard (melewati file yang sedang dikunci game/browser aktif).
9. **System Health & Diagnostic Suite:**
   - SFC /scannow, DISM RestoreHealth, DISM Component Store ResetBase.
   - 1-Klik Reset Windows Update, 1-Klik Reset Network & Winsock catalog, Rebuild Icon cache, dan Trim Standby Memory.
10. **VoltUndo (1-Klik Pemulihan Total & System Restore):**
    - Otomatis membuat Windows System Restore Point dan snapshot registri (`.reg`) serta file config (`.bak`).
    - 1-Klik Undo mengembalikan seluruh settingan ke kondisi awal dengan sempurna.

---

## 🖥️ Antarmuka & Modul Voltune v3.3

Voltune v3.3 dirancang dengan arsitektur **100% In-GUI Desktop Hub** tanpa perlu mengetik perintah lanjutan di terminal, sekaligus menyediakan mode CLI interaktif bila dijalankan di lingkungan headless/remote.

### 1. Dashboard (Hardware Telemetry)
* **Dynamic Spek Inspection:** Menampilkan data prosesor (deteksi arsitektur Hybrid P+E Intel Core / AMD Ryzen), kartu GPU diskrit beserta VRAM riil (bebas bug WMI UInt32 4GB clamp) dan TGP wattage riil (via `enforced.power.limit`), status adaptor daya AC/Baterai, resolusi layar dan target refresh rate VRR, serta pembagian kapasitas drive C: & D:.
* **Hardware-Accelerated GPU Scheduling (HAGS):** Memeriksa status HAGS Windows secara langsung.

### 2. Tweaks (Atomic & Customizable Matrix)
* **21 Granular Tweak Checkboxes:** Terbagi ke dalam 4 kategori (Gaming & Performa Hardware, Windows 11 Quality of Life, Privasi & Anti-Telemetri, Layanan & Update Sistem).
* **Dynamic Live State Inspection:** Pada saat aplikasi dibuka, seluruh checkbox otomatis memeriksa konfigurasi Windows saat ini dan hanya mencentang tweak yang sudah aktif di sistem Anda.
* **Clean Preset Matrix:** Tombol preset (`Recommended`, `Laptop Gaming`, `Desktop Max`, `Minimal Privacy`) menerapkan matriks seleksi bersih tanpa meninggalkan sisa centang dari preset sebelumnya.
* **Clear All Button:** Mengosongkan seluruh centang dalam 1 klik sebelum membuat kustomisasi mandiri.
* **Atomic Execution Engine:** Menjalankan hanya tweak yang Anda pilih secara individual (`Set-VoltAtomicTweak`), tanpa memaksakan perubahan di luar pilihan Anda.

### 3. Install Apps (Katalog Fresh Install WinGet + Live Search)
* **9 Kategori Software Esensial:**
  * *Game Runtimes & Libs:* Visual C++ 2005-2022 AIO, DirectX End-User Runtimes, .NET 8 Desktop Runtime.
  * *Utilities & Archive:* NanaZip, 7-Zip, WinRAR, PowerToys, Everything Search, Process Hacker, BleachBit.
  * *Gaming Launchers & Tools:* Steam, Epic Games Launcher, GOG Galaxy, EA App, Ubisoft Connect, Battle.net, Discord, OBS Studio, RivaTuner (RTSS), MSI Afterburner.
  * *Hardware Drivers & Monitoring:* NVIDIA App, HWiNFO64, CPU-Z, GPU-Z.
  * *Developer Suite:* Visual Studio Code, Git, PowerShell 7, Windows Terminal, Docker Desktop, Node.js LTS, Python 3.
  * *Web Browsers:* Brave, Google Chrome, Mozilla Firefox, Microsoft Edge Dev.
  * *Social & Media:* Telegram Desktop, WhatsApp, Spotify, VLC Media Player, HandBrake.
* **Interactive Live Search Bar:** Filter aplikasi secara instan dan interaktif saat Anda mengetik.
* **Non-Blocking Background Installation:** Proses instalasi berjalan secara asinkron tanpa membekukan antarmuka, dengan log progres terkirim langsung ke konsol GUI.

### 4. Game Tuner (Universal Dynamic Card Generator)
* **Universal Multi-Drive Discovery:** Memindai instalasi game secara otomatis dari Steam (semua drive via `libraryfolders.vdf`), Epic Games Store Manifests (`*.item`), GOG Galaxy, HoYoPlay, Ubisoft Connect, folder standalone (`C:\Games\*`, `D:\Games\*`), dan registry uninstall.
* **Dynamic Game Cards:** Secara dinamis membuat kartu pengaturan per-game dengan opsi 1-klik:
  * Prioritas GPU High Performance di Windows Graphics Settings.
  * Pengecualian folder game di Windows Defender (mengeliminasi *micro-stutter* saat streaming tekstur).
  * Penyetelan engine game khusus (RDR2 Async Compute & texture budget, The Witcher 3 Next-Gen DX12, Honkai: Star Rail, Genshin Impact).
* **Tambah Game Manual (.exe):** Tombol file dialog untuk mendaftarkan executable game portabel apa pun ke dalam optimasi Voltune.

### 5. VoltClean (Cross-Drive Disk & Cache Cleaner)
* Pembersihan aman cache sementara Windows (`%TEMP%`, `C:\Windows\Temp`).
* Pembersihan shader cache lintas vendor (NVIDIA `DXCache` & `GLCache`, AMD, Intel, DirectX `D3DSCache`).
* Pembersihan shader cache Steam di seluruh drive (C: dan D:).
* Pembersihan crash dumps, error reports, dan Recycle Bin.
* **Dynamic Process Guard:** Melindungi file dari error penguncian bila game atau browser sedang aktif berjalan.

### 6. System Health & Diagnostics
* 1-Klik SFC System File Checker (`sfc /scannow`).
* 1-Klik DISM Online RestoreHealth & Component Store Cleanup.
* 1-Klik Reset Windows Update & Winsock Catalog.
* Rebuild Windows Icon Cache & Trim Standby Memory.

### 7. VoltUndo & Snapshot Engine
* **1-Klik Pemulihan Total:** Mengembalikan seluruh nilai registri dan konfigurasi sistem ke kondisi sebelum Voltune dijalankan.
* **System Restore Automation:** Membuat Windows System Restore Point resmi sebelum eksekusi massal.
* **Snapshot Browser:** Memilih riwayat backup registri dan konfigurasi dari menu dropdown di GUI.

---

## ⚡ Mode Interaktif CLI (Terminal Fallback)

Bagi pengguna yang menjalankan Voltune melalui sesi remote SSH, Windows Sandbox, atau lebih menyukai antarmuka terminal bergaya Chris Titus Tech, Voltune tetap menyediakan mode CLI interaktif penuh:

```powershell
.\voltune.ps1 -CLI
```

Tampilan Menu CLI:
```text
================================================================================
            ⚡ VOLTUNE WINDOWS UTILITY v3.3.0-Universal ⚡
             Toolkit Optimasi Dinamis, Gaming & Tweaks Tanpa Batas
================================================================================

[SPEK HARDWARE DINAMIS TERDETEKSI]
   Prosesor   : 12th Gen Intel(R) Core(TM) i7-12650H (10 Cores, 16 Threads | Hybrid P+E)
   Kartu GPU  : NVIDIA GeForce RTX 4060 Laptop GPU (8.0 GB VRAM | 45W TGP)
   Sumber Daya: AC Adapter (Daya Maksimal) [✓]
   Layar      : 1920x1080 @ 60 Hz | Target FPS : VRR 57 FPS
   Memori     : 15.7 GB RAM | Storage : C: 81.5/475.8 GB
   Status HAGS: Aktif [✓] | Hibernate: Nonaktif [✓]
   Game Nemu  : 13 game terdeteksi dinamis

--------------------------------------------------------------------------------
 PILIH KATEGORI TINDAKAN (Ketik angka lalu tekan Enter):
--------------------------------------------------------------------------------
 [1] 🚀 Optimasi Lengkap (Rekomendasi Terima Beres)
 [2] 🎮 VoltPlay: Sesuaikan Setting Game Khusus
 [3] 🧹 VoltClean: Pembersih Disk & Cache Lintas-Drive
 [4] 🛠️ Windows 11 QoL & Explorer Tweaks
 [5] 🛡️ Privasi, Telemetri & Background Bloat Killer
 [6] ⚡ TCP/IP Gaming Latency & Raw Input (Zero-VPN Harm)
 [7] ⚙️ Windows Services Optimizer (Safe Gaming Profile)
 [8] 🔒 Windows Update Control (Security Updates Only Profile)
 [9] 📦 Game Runtimes & Software Catalog (WinGet One-Click)
 [10] 🧩 Windows Optional Features (DirectPlay, WSL2, Sandbox)
 [11] 💾 Reclaim Ruang SSD (Toggle Hibernasi)
 [12] 🔧 System Health & Repair Diagnostics (SFC, DISM, Network Reset)
 [G] 🖥️ Buka Voltune Modern Native GUI (WPF Desktop Window)
 [U] ↩️ VoltUndo: Kembalikan Semua Settingan ke Semula (1-Klik Reset)
 [0] Keluar
================================================================================
```

---

## 🛡️ Prinsip Keamanan & Jaminan Zero-VPN Harm

Voltune dibangun dengan standar kehati-hatian tingkat tinggi untuk mencegah kerusakan pada Windows maupun software kerja:
1. **Zero-VPN Harm (Network Safety Whitelist):**
   Optimasi TCP/IP latency (`Nagle's Algorithm`, `TcpAckFrequency = 1`) **hanya** diterapkan pada adapter fisik (Ethernet & Wi-Fi aktif). Seluruh adapter virtual, TAP, dan **Palo Alto GlobalProtect (`PanGPS`)** dilewati secara ketat agar koneksi VPN perusahaan tidak pernah terganggu.
2. **Reversible by Design:**
   Setiap kali optimasi dijalankan, Voltune mengekspor snapshot registri sistem lengkap (`.reg`) dan file konfigurasi game ke folder `%LOCALAPPDATA%\Voltune\Backups\`. Pengguna dapat membatalkan semua perubahan kapan saja via tab *VoltUndo*.
3. **Safe Gaming Services Profile:**
   Layanan Windows yang dinonaktifkan terbatas pada telemetri dan bloat non-esensial (`DiagTrack`, `dmwappushservice`, `MapsBroker`, `RetailDemo`). Layanan Audio, Spooler Printer, Bluetooth, dan Network VPN tetap 100% terjaga.
4. **Driver Hijack Protection:**
   Mencegah Windows Update menimpa driver display GPU khusus (NVIDIA/AMD) yang sering menyebabkan layar berkedip atau penurunan performa game.

---

## 📋 Persyaratan Sistem

* **Sistem Operasi:** Windows 10 (versi 2004 atau lebih baru) / Windows 11 (64-bit).
* **PowerShell:** Windows PowerShell 5.1 (bawaan Windows) atau PowerShell 7+ (`pwsh.exe`).
* **Hak Akses:** Administrator (otomatis meminta elevasi UAC saat dijalankan).
* **Dependensi Binary:** **Nol (Zero External Dependencies)**. Menggunakan .NET WPF bawaan sistem (`PresentationFramework`, `PresentationCore`, `WindowsBase`).

---

## 🧪 Verifikasi & Pengujian Kualitas

Setiap perubahan pada Voltune diverifikasi menggunakan suite pengujian otomatis:

```powershell
# Uji Validasi Syntax pada Windows PowerShell 5.1 & PowerShell 7
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltune_syntax.ps1"
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltune_syntax.ps1"

# Uji Inisialisasi WPF GUI & Elemen XAML
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_gui_load.ps1"

# Uji Snapshot Backup & Restore Engine VoltUndo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltundo_snapshot.ps1"
```

> **Catatan Encoding:** Seluruh berkas skrip PowerShell (`.ps1`) di repositori ini disimpan dalam format **UTF-8 with BOM (`utf-8-sig`)** untuk menjamin kompatibilitas penuh dengan mesin parser Windows PowerShell 5.1 tanpa risiko kegagalan karakter ampersand (`&`).

---

## 📄 Lisensi

Didistribusikan di bawah lisensi **MIT License**. Lihat [LICENSE](LICENSE) untuk informasi lebih lanjut.
