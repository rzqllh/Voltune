# VOLTUNE NEXT-GEN: MASTER IMPLEMENTATION PLAN
**Arsitektur, Roadmap, dan Rencana Pengembangan Toolkit Optimasi Windows Universal**

> **Dokumen Disusun:** 01 November 2026 (Menjelang Rilis v2.0)  
> **Target Repositori:** [`rzqllh/Voltune`](https://github.com/rzqllh/Voltune)  
> **Lokasi Lokal:** `C:\Users\Hafizh Rizqullah\Documents\Code\_active\voltune`  
> **Prinsip Utama:** *Safe by default, Reversible by design, Hardware-Aware, Human-Friendly.*

---

## 1. Executive Summary & Visi Produk

Voltune Next-Gen adalah evolusi dari repositori `rzqllh/Voltune`. Dari yang sebelumnya berupa Python CLI teknis berbahasa Inggris, Voltune ditingkatkan menjadi **Toolkit Performa & Gaming Windows Universal** yang mengadopsi model distribusi instan ala **Chris Titus Tech (`winutil`)**, namun dipersenjatai dengan fitur unik yang belum pernah ada di optimizer lain: **Hardware-Aware Display & Game Auto-Configurator**.

### Karakteristik Produk:
1. **Distribusi Instan (One-Liner):** Pengguna tidak perlu download file apa pun, tidak perlu install Python, dan tidak perlu ekstrak ZIP. Cukup jalankan satu baris perintah di PowerShell (Administrator):
   ```powershell
   irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex
   ```
2. **Bahasa Indonesia Manusiawi:** Menghapus semua jargon teknis yang membingungkan (*"CIM thread scheduling"*, *"Nagle algorithm"*, *"TCP heuristic window"*). Seluruh antarmuka menggunakan Bahasa Indonesia yang santai, ringkas, dan fokus pada manfaat nyata bagi pengguna awam.
3. **General untuk Semua Laptop:** Tidak ada dependensi hardware tunggal. Mampu mendeteksi secara dinamis prosesor Intel (Hybrid P+E Cores) / AMD Ryzen, GPU ganda (NVIDIA GeForce & AMD Radeon), RAM, kapasitas storage, dan refresh rate monitor (60Hz s/d 240Hz).
4. **Dual GPU Parity:** Mendukung penuh optimasi driver kartu grafis **NVIDIA** (Shader Cache 10GB, Low Latency, DLSS Override, Reflex) dan **AMD Radeon** (Anti-Lag, Radeon Chill, Shader Cache Registry, Smart Access Memory).
5. **Game Auto-Configurator:** Secara otomatis mendeteksi game open-world terinstal (Red Dead Redemption 2, Honkai: Star Rail, Genshin Impact, The Witcher 3, dll.) dan menyelaraskan file konfigurasi in-game agar bebas dari *stuttering* akibat *power-throttling* atau *VRAM spillover*.
6. **Zero-Harm & 1-Klik Undo:** Setiap perubahan registri atau file game wajib membuat cadangan snapshot/`.bak`. Pengguna dapat mengembalikan seluruh sistem ke kondisi semula hanya dengan satu klik.

---

## 2. Arsitektur Teknis Sistem

```mermaid
flowchart TD
    User([Pengguna Windows]) -->|irm ... | iex| Boot[voltune.ps1 Web Entrypoint]
    Boot --> UAC{Cek Administrator}
    UAC -->|Belum Admin| Elevate[Self-Elevate UAC Prompt]
    UAC -->|Sudah Admin| Engine[Hardware & Environment Detection Engine]
    
    Engine --> SysInfo[Deteksi CPU, GPU Dual, RAM, Screen Hz, Storage]
    Engine --> GameScan[Pindai Game Terinstal: RDR2, HoYo, Witcher]
    
    SysInfo --> UI[Interactive UI - Bahasa Indonesia]
    GameScan --> UI
    
    UI --> Opt1[1. Optimasi Otomatis Rekomendasi]
    UI --> Opt2[2. Menu Pilih Sendiri Custom]
    UI --> Opt3[3. Kembalikan Semua Settingan Undo]
    UI --> Opt4[4. Buka Tool Lanjutan Voltune Core]
    
    Opt1 --> Backup[Snapshot & Restore Point Engine]
    Opt2 --> Backup
    
    Backup --> TaskWin[Windows Gaming Boost: HAGS, Game Mode, MMCSS]
    Backup --> TaskGPU[Dual GPU Alignment: NVIDIA / AMD]
    Backup --> TaskClean[Safe Disk & Cache Cleanup]
    Backup --> TaskGame[Game Config Injector: RDR2, HSR, Genshin]
    
    Opt3 --> Rollback[Restore Registry & Restore Game Configs]
```

---

## 3. Rincian Modul & Fitur (Feature Specifications)

### Modul 1: Detection Engine (Pemeriksa Spek Otomatis)
Mendeteksi karakteristik mesin tanpa asumsi:
* **CPU:** Nama prosesor, jumlah Core/Thread, dan apakah menggunakan arsitektur hybrid (Intel 12th/13th/14th Gen P-Core + E-Core).
* **GPU Primer & Sekunder:** Memisahkan GPU diskrit (NVIDIA RTX/GTX vs AMD Radeon RX) dari GPU internal (Intel UHD/Iris Xe vs AMD Radeon Graphics). Mendeteksi kapasitas VRAM dan estimasi batas daya (TGP).
* **Layar (Display):** Resolusi asli dan Refresh Rate aktif (60 Hz, 120 Hz, 144 Hz, 165 Hz, 240 Hz) serta status MSHybrid/Optimus.
* **Storage:** Kapasitas sisa Drive C: untuk menentukan apakah aman mengaktifkan Shader Cache besar.
* **Status HAGS:** Membaca status `HwSchMode` di `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers`.

### Modul 2: Windows Gaming Responsiveness Boost
* **HAGS (Hardware-Accelerated GPU Scheduling):** Menyuntikkan `HwSchMode = 2` agar GPU menjadwalkan alokasi video memory sendiri tanpa interupsi CPU, sekaligus membuka kunci DLSS 3 Frame Generation.
* **Windows Game Mode:** Memastikan `AllowAutoGameMode = 1` aktif agar thread game diprioritaskan di P-Cores pada prosesor hybrid.
* **MMCSS System Responsiveness:**
  * `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile` $\rightarrow$ `SystemResponsiveness = 10`.
  * `Tasks\Games`: `GPU Priority = 8`, `Priority = 6`, `Scheduling Category = High`.
  * *Manfaat manusia:* Mencegah suara headset kresek-kresek, drop ping jaringan, dan stutter saat ada aplikasi background menyala saat main game.
* **Matikan Background GameDVR:**
  * `GameDVR_Enabled = 0`, `GameDVR_HistoricalCaptureEnabled = 0`, `AllowGameDVR = 0`.
  * *Manfaat manusia:* Menghilangkan beban Windows yang diam-diam merekam layar ke SSD yang sering memicu lag tiba-tiba saat main game.

### Modul 3: Dual GPU Alignment Engine
Menyesuaikan pengaturan kartu grafis secara otomatis sesuai merek GPU pengguna:

#### A. Jika Terdeteksi NVIDIA (GeForce / RTX / GTX):
* **Shader Cache 10 GB:** Mencegah kompilasi ulang shader terus-menerus saat menjelajah dunia open-world (melenyapkan traversal micro-stutter).
* **Low Latency Mode:** Diaktifkan (`On`) untuk memangkas antrean render CPU-GPU.
* **Adaptive FPS Capping:**
  * Jika GPU terdeteksi tipe laptop hemat daya ($\le 60$W TGP) $\rightarrow$ tawarkan kunci FPS di setengah refresh rate monitor (misal 72 FPS di layar 144 Hz, atau 60 FPS) agar GPU tidak menabrak batas watt dan thermal throttle.
  * Jika GPU daya penuh ($\ge 100$W TGP / Desktop) $\rightarrow$ tawarkan kunci di `RefreshRate - 4` (misal 140 FPS di 144 Hz) untuk G-Sync/FreeSync tear-free.
* **Power Management Mode:** Diatur ke *Prefer Maximum Performance* pada profil game.

#### B. Jika Terdeteksi AMD Radeon (RX 6000/7000/8000 Series / iGPU):
* **Radeon Anti-Lag:** Mengaktifkan padanan Low Latency di registri driver AMD.
* **Radeon Chill / Frame Rate Limiter:** Mengatur pembatasan FPS selaras dengan refresh rate monitor.
* **AMD Shader Cache:** Memastikan registri cache shader AMD diatur ke *AMD Optimized / Enabled*.
* **HAGS AMD:** Menerapkan `HwSchMode = 2` yang kompatibel pada arsitektur RDNA2/RDNA3.

### Modul 4: Game Auto-Configurator (VoltPlay)
Memindai lokasi instalasi game secara otomatis (Steam, Epic, HoYoPlay, Documents, AppData, Registry). Jika ditemukan, menyediakan preset anti-stutter siap pakai:

1. **Red Dead Redemption 2 (`system.xml`):**
   * Lokasi: `Documents\Rockstar Games\Red Dead Redemption 2\Settings\system.xml`
   * Optimasi: `asyncComputeEnabled = true`, `maxTexUpgradesPerFrame = 10`, `refreshRate = 144`, `tripleBuffered = false`, `anisotropicFiltering = 4 (16x)`.
   * Dampak: Menghilangkan freeze saat menunggang kuda cepat masuk ke kota Valentine/Saint Denis.
2. **Honkai: Star Rail:**
   * Lokasi: Registry `HKCU\Software\Cognosphere\Star Rail`
   * Optimasi: Menurunkan `ReflectionQuality` dan `LightQuality` dari *Very High (5)* ke *High (4)*. Menjaga FPS stabil 60–72 FPS di Penacony tanpa membuat GPU menabrak batas daya.
3. **Genshin Impact:**
   * Lokasi: Registry `HKCU\Software\miHoYo\Genshin Impact`
   * Optimasi: Menurunkan `Crowd Density` ke *Medium* di kota besar (Fontaine/Natlan) dan memastikan Render Scale 1.0 (anti-overload CPU).
4. **The Witcher 3: Wild Hunt (DX12 Next-Gen):**
   * Lokasi: `Documents\The Witcher 3\dx12user.settings`
   * Optimasi: Sinkronisasi Frame Generation (`AllowDLSSG=true`), memastikan Nvidia HairWorks tetap `0`, dan membatasi FPS stabil.

### Modul 5: Pembersih Disk & Sampah Aman (VoltClean)
* Membersihkan `%TEMP%`, `C:\Windows\Temp`, crash dumps (`*.dmp`), cache instalasi Windows lama (`$WINDOWS.~WS`).
* Mengosongkan Recycle Bin secara terverifikasi.
* **Hard Safety Boundary:** DILARANG menyentuh file user di luar direktori sampah sementara, dilarang menyentuh driver jaringan atau service VPN (`PanGPS` / GlobalProtect, dll.).

### Modul 6: Sistem Backup & 1-Klik Undo (VoltUndo)
* **Restore Point Helper:** Membuat Windows System Restore Point otomatis bernama `Voltune-PreOptimization`.
* **Registry Snapshot:** Menyimpan file cadangan `.reg` di `%LOCALAPPDATA%\Voltune\Backups\` sebelum ada registri yang diubah.
* **File Game Backup:** Membuat salinan `.bak` untuk setiap file konfigurasi yang disentuh.
* **Tombol Kembalikan:** Mengembalikan semua nilai registri dan menimpa balik file `.bak` ke kondisi aslinya jika pengguna merasa tidak cocok.

---

## 4. Antarmuka Interaktif Pengguna (Interactive CLI / TUI Mockup)

Tampilan antarmuka saat dijalankan via PowerShell:

```text
================================================================================
                       ⚡ VOLTUNE WINDOWS UTILITY v2.0 ⚡
                 Bikin Laptop & PC Gaming Lu Lebih Ngacir & Stabil
================================================================================

[SPEK LAPTOP LU TERDETEKSI]
 • Prosesor  : 12th Gen Intel Core i7-12650H (10 Cores, 16 Threads)
 • Kartu GPU : NVIDIA GeForce RTX 4060 Laptop (45W TGP | 8 GB VRAM)
 • Layar     : 1920x1080 @ 144 Hz (MSHybrid / Optimus)
 • Memori    : 16 GB DDR5 Dual-Channel
 • Ruang C:  : 83.5 GB Bebas (Aman)
 • Game Nemu : Red Dead Redemption 2, Honkai: Star Rail, Genshin Impact

--------------------------------------------------------------------------------
 PILIH TINDAKAN (Ketik angka lalu tekan Enter):
--------------------------------------------------------------------------------

 [1] 🚀 Optimasi Otomatis (Rekomendasi - Terima Beres)
     -> Bikin cadangan dulu, aktifkan HAGS & prioritas game Windows, 
        setel driver NVIDIA/AMD biar gak stutter, dan beresin setting game lu.

 [2] 🎮 Sesuaikan Setting Game Khusus (RDR2 / HSR / Genshin / Witcher)
     -> Pilih game yang mau disesuaikan settingannya biar FPS-nya rata.

 [3] 🧹 Bersihkan File Sampah & Ruang Disk
     -> Hapus file sementara dan cache usang yang menumpuk aman 100%.

 [4] 🛠️ Buka Fitur Lanjutan Voltune (DNS Benchmark, Appx, DISM)
     -> Masuk ke modul utilitas teknis lengkap Voltune.

 [5] ↩️ Kembalikan Semua Settingan ke Semula (Undo / Reset)
     -> Balikin semua perubahan ke kondisi sebelum Voltune dijalankan.

 [0] Keluar
================================================================================
Pilihan lu [0-5]: _
```

---

## 5. Roadmap Pelaksanaan Bertahap (Phased Implementation)

### Tahap 1: Struktur & Core Engine (`voltune.ps1`)
* Membuat skrip mandiri `voltune.ps1` di root direktori repositori.
* Mengimplementasikan modul deteksi hardware: CPU, GPU Dual (NVIDIA/AMD), RAM, Screen Refresh Rate, dan status HAGS.
* Mengimplementasikan mekanisme self-elevation UAC (otomatis jadi Administrator jika dibuka biasa).

### Tahap 2: Windows Gaming Responsiveness & Dual GPU Engine
* Menerapkan fungsi registri HAGS (`HwSchMode = 2`).
* Menerapkan optimasi MMCSS & GameDVR.
* Membangun modul khusus NVIDIA (Shader Cache 10GB, Low Latency, Power Max, FPS Cap adaptif).
* Membangun modul khusus AMD Radeon (Anti-Lag, Radeon Chill, Shader Cache).

### Tahap 3: Game Auto-Configurator (VoltPlay)
* Membangun scanner direktori game (Documents, AppData, Registry HoYo, Steam common).
* Membangun injector setting RDR2 (`system.xml`).
* Membangun injector setting Honkai Star Rail (`GraphicsSettings_Model`).
* Membangun panduan/preset untuk Genshin Impact dan The Witcher 3.

### Tahap 4: Sistem Backup, Safety & Undo (VoltUndo)
* Membuat engine snapshot registri dan file `.bak`.
* Membangun alur `Undo` teruji untuk mengembalikan setiap perubahan.
* Menjalankan audit kepatuhan *Safe Mode* (memastikan 0 VPN break, 0 network break).

### Tahap 5: Rilis & Pengujian Lapangan
* Sinkronisasi repositori git `rzqllh/Voltune`.
* Menguji eksekusi via satu baris perintah `irm ... | iex` di mesin pengujian.
* Memperbarui dokumentasi `README.md` repositori dengan petunjuk satu baris dalam Bahasa Indonesia & Inggris.

---

## 6. Checklist Verifikasi & Jaminan Kualitas

- [ ] Skrip berjalan sempurna di Windows 10 dan Windows 11.
- [ ] Berjalan native tanpa memerlukan instalasi Python pada komputer pengguna.
- [ ] Deteksi akurat saat laptop hanya punya iGPU, atau dGPU NVIDIA, atau dGPU AMD Radeon.
- [ ] Pembatasan FPS selaras dengan monitor (misal 72 FPS di 144 Hz, 60 FPS di 60/120 Hz, 82 FPS di 165 Hz).
- [ ] Tidak pernah menyentuh service VPN (khususnya `PanGPS` Palo Alto Networks) atau koneksi internet pengguna.
- [ ] File backup selalu tercipta sebelum ada perubahan yang disimpan ke disk/registri.
- [ ] Fitur Undo mengembalikan seluruh nilai registri dan file game ke nilai semula tanpa cacat.

---
*Dokumen ini adalah cetak biru resmi untuk sesi pengerjaan berikutnya. Selamat beristirahat!*
