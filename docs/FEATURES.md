# Voltune Features Map (v3.3.0-Universal)

Voltune adalah toolkit manajemen performa, gaming, perawatan disk, dan pemulihan sistem Windows yang dirancang dengan arsitektur **100% In-GUI Desktop Window** berbasis native WPF, tanpa dependensi binary eksternal, dan aman digunakan bersama software jaringan korporat.

---

## 1. Dashboard & Dynamic Hardware Profiling

Voltune secara dinamis memeriksa arsitektur hardware sistem saat startup tanpa mengasumsikan konfigurasi statis:
- **CPU Architecture Awareness:** Mendeteksi prosesor Intel Core (arsitektur Hybrid P-Core + E-Core) dan AMD Ryzen, jumlah core, serta logical thread.
- **Dual GPU & True VRAM / TGP Detection:** 
  - Mendeteksi GPU diskrit (NVIDIA GeForce RTX/GTX) dan iGPU (Intel Iris Xe/UHD, AMD Radeon).
  - Mengambil kapasitas VRAM secara akurat (kebal terhadap keterbatasan WMI 32-bit `AdapterRAM` yang meng-clamp VRAM >4GB ke 4GB).
  - Mengambil daya TGP watt laptop secara langsung via `enforced.power.limit` NVIDIA SMI (mengatasi nilai `[N/A]` pada query daya standar).
- **Display & Dynamic VRR Target:** Mendeteksi resolusi dan refresh rate layar, lalu secara otomatis mengkalkulasi target FPS optimum untuk G-Sync / FreeSync (Refresh Rate - 3 FPS) serta mode dingin (Half Refresh Rate).
- **Power & Storage Metrics:** Menampilkan status adaptor daya (AC/Baterai) serta pembagian kapasitas drive C: dan D:.
- **Hardware-Accelerated GPU Scheduling (HAGS):** Memeriksa dan menampilkan status aktif/nonaktif HAGS Windows.

---

## 2. Tweaks & Atomic Customization Matrix

Setiap tweak di Voltune dieksekusi secara granular per-item (`Set-VoltAtomicTweak`), sehingga pengguna memiliki kendali penuh atas konfigurasi yang ingin diterapkan atau dibatalkan.

### Kategori Tweak
1. **Gaming & Performa Hardware:**
   - *Hardware-Accelerated GPU Scheduling (HAGS):* Mengaktifkan scheduling GPU hardware di Windows.
   - *Windows Game Mode & MMCSS Low Latency Audio:* Memprioritaskan alokasi CPU untuk game dan audio latensi rendah.
   - *Matikan Background GameDVR:* Membebaskan overhead GPU dari perekaman latar belakang Xbox GameDVR.
   - *1:1 Raw Mouse Input:* Menonaktifkan akselerasi mouse pointer untuk akurasi aim 1:1.
   - *Daftarkan Library Game ke Defender Exclusion:* Menghilangkan *micro-stutter* akibat scanning file tekstur/audio saat bermain game.
   - *TCP/IP Gaming Latency Optimizer (Zero-VPN Harm):* Menonaktifkan Nagle's Algorithm (`TcpAckFrequency = 1`, `TCPNoDelay = 1`) dan Network Throttling Index (`0xFFFFFFFF`).
   - *Matikan CPU Power Throttling Execution:* Menjamin clock CPU tidak diturunkan paksa saat beban komputasi tinggi.
2. **Windows 11 Quality of Life (QoL):**
   - *Classic Context Menu:* Mengaktifkan klik kanan penuh Windows 10 tanpa submenu "Show more options".
   - *Tampilkan Ekstensi File:* Memperlihatkan ekstensi berkas (`.exe`, `.ps1`, `.dll`, dll.) di File Explorer.
   - *Buka File Explorer ke 'This PC':* Membuka langsung ke drive lokal, bukan Quick Access / Home.
   - *Tampilkan File Tersembunyi:* Mengaktifkan visibilitas berkas tersembunyi.
   - *Bersihkan Taskbar:* Menyembunyikan tombol Widgets (hemat RAM), Copilot, dan Task View.
   - *Bersihkan Clutter Quick Access:* Menonaktifkan riwayat berkas dan folder terkini.
3. **Privasi & Anti-Telemetri:**
   - *Windows Telemetry Level Minimum (Level 0 / Security Only):* Membatasi pengiriman data diagnostik Windows.
   - *Matikan Windows Recall AI Snapshot:* Menonaktifkan perekaman layar otomatis Windows Recall di Windows 11 24H2.
   - *Matikan Copilot System-Wide:* Menonaktifkan integrasi AI Copilot Windows.
   - *Matikan Bing Search & Iklan Start Menu:* Memblokir pencarian web Bing dan rekomendasi aplikasi pihak ketiga di menu Start.
4. **Layanan & Update Sistem:**
   - *Safe Gaming Services:* Mengoptimalkan layanan latar belakang bloat (`DiagTrack`, `dmwappushservice`, `MapsBroker`, `RetailDemo`, Xbox) dengan proteksi ketat agar layanan audio, pencetakan, dan VPN tetap aman.
   - *Windows Update: Security Updates Only Profile:* Menunda feature update tahunan 365 hari, mencegah restart paksa saat pengguna aktif bekerja, dan memblokir pembajakan driver GPU oleh Windows Update.

### Fitur Presets
- **Live State Inspection:** Saat aplikasi dibuka, hanya opsi yang sedang aktif di Windows yang tercentang.
- **Clean Preset Blueprints:** Preset *Recommended*, *Laptop Gaming*, *Desktop Max*, dan *Minimal Privacy* menerapkan matriks pilihan bersih tanpa akumulasi centang lama.
- **Clear All:** Mengosongkan seluruh checkbox dalam 1 klik.

---

## 3. Katalog Software Pasca-Install (WinGet + Live Search)

Katalog perangkat lunak komprehensif untuk melengkapi kebutuhan komputer setelah install ulang Windows:
- **Game Runtimes & Libraries:** Microsoft Visual C++ 2005–2022 AIO, DirectX End-User Runtimes, .NET 8 Desktop Runtime.
- **Utilities & Archive:** NanaZip (integrasi context menu Win11), 7-Zip, WinRAR, PowerToys, Everything Search, Process Hacker, BleachBit.
- **Gaming Launchers & Tools:** Steam, Epic Games Launcher, GOG Galaxy, EA App, Ubisoft Connect, Battle.net, Discord, OBS Studio, RivaTuner (RTSS), MSI Afterburner.
- **Hardware Drivers & Monitoring:** NVIDIA App (pengganti modern GeForce Experience), HWiNFO64, CPU-Z, GPU-Z.
- **Developer Tools:** VS Code, Git, PowerShell 7, Windows Terminal, Docker Desktop, Node.js LTS, Python 3.
- **Web Browsers:** Brave, Google Chrome, Mozilla Firefox, Microsoft Edge Dev.
- **Social & Media:** Telegram Desktop, WhatsApp, Spotify, VLC Media Player, HandBrake.
- **Interactive Live Search Bar (`txtAppSearch`):** Pencarian interaktif real-time berdasarkan nama aplikasi atau ID WinGet saat pengguna mengetik.
- **Non-Blocking Background Installation:** Proses instalasi dieksekusi di background tanpa membekukan antarmuka WPF.

---

## 4. Game Tuner (Universal Dynamic Card Generator)

- **Universal Multi-Drive Scanning:** Memindai game dari library Steam (semua drive via `libraryfolders.vdf`), manifest Epic Games Store (`*.item`), GOG Galaxy, HoYoPlay, Ubisoft Connect, folder game standalone (`C:\Games\*`, `D:\Games\*`), dan registry uninstall.
- **Dynamic Card UI:** Membuat kartu pengaturan interaktif otomatis untuk seluruh game yang ditemukan di sistem.
- **Per-Game Tuning Controls:**
  - *GPU High Performance Priority:* Mendaftarkan game ke GPU diskrit berdaya tinggi di Windows Settings.
  - *Windows Defender Exclusion:* Menambahkan folder instalasi game ke pengecualian antivirus agar aset tekstur tidak tertahan saat streaming.
  - *Engine-Specific Tuning:* Menyelaraskan pengaturan engine game (RDR2 Async Compute, The Witcher 3 Next-Gen DX12, Honkai: Star Rail, Genshin Impact).
- **Tambah Game Manual (.exe):** Mengizinkan pengguna memilih berkas `.exe` game portabel atau game custom via file dialog.

---

## 5. VoltClean (Cross-Drive Disk & Cache Cleaner)

- **Temp Cache Cleaner:** Membersihkan `%TEMP%` dan `C:\Windows\Temp`.
- **Shader Cache Cleaner:** Membersihkan shader cache lintas vendor (NVIDIA `DXCache` & `GLCache`, AMD, Intel, dan DirectX `D3DSCache`).
- **Steam Shader Cleaner:** Membersihkan shader cache game Steam di semua drive yang terdeteksi (C: dan D:).
- **Crash Dumps & Recycle Bin:** Membersihkan berkas minidump, error report, dan tempat sampah Windows.
- **Process Guard:** Mencegah error file lock dengan melewati cache aplikasi/game yang sedang aktif berjalan.

---

## 6. System Health & Diagnostics

- **SFC System File Checker:** Memindai dan memperbaiki kerusakan berkas integritas Windows (`sfc /scannow`).
- **DISM Online RestoreHealth:** Memperbaiki citra Windows menggunakan Windows Update sebagai sumber perbaikan.
- **DISM Component Store Cleanup:** Membersihkan sisa pembaruan sistem lama (`/ResetBase`) untuk menghemat ruang disk.
- **1-Klik Reset Windows Update:** Menghentikan service pembaruan, membersihkan cache `SoftwareDistribution` dan `catroot2`, lalu menyalakan ulang service secara bersih.
- **1-Klik Reset Network & Winsock:** Memperbaiki konfigurasi stack TCP/IP dan katalog Winsock yang korup.
- **Rebuild Icon Cache & Trim Standby Memory:** Memulihkan ikon desktop yang rusak dan mengosongkan memory cache standby Windows.

---

## 7. VoltUndo & Rollback Engine

- **1-Klik Undo Semuanya:** Memulihkan seluruh pengaturan registri dan konfigurasi sistem ke kondisi awal sebelum Voltune dijalankan.
- **System Restore Point Automation:** Secara otomatis membuat Windows System Restore Point resmi sebelum eksekusi perubahan massal.
- **Snapshot Browser:** Dropdown pemilih riwayat snapshot backup registri (`.reg`) dan berkas konfigurasi (`.bak`) di folder `%LOCALAPPDATA%\Voltune\Backups\`.
- **Structured Manifest:** Setiap snapshot dicatat dalam berkas `manifest.json` yang memuat tanggal, waktu, versi Voltune, serta daftar komponen yang dicadangkan.
