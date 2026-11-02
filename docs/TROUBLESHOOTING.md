# Panduan Pemecahan Masalah (Troubleshooting) Voltune

Dokumen ini memuat solusi untuk kendala umum yang mungkin dihadapi saat menjalankan Voltune v3.3.

---

## 1. Pesan Error: "Running scripts is disabled on this system"

### Penyebab:
Kebijakan eksekusi PowerShell bawaan Windows melarang eksekusi skrip lokal yang belum ditandatangani.

### Solusi:
Izinkan eksekusi skrip untuk sesi PowerShell saat ini dengan menjalankan:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\voltune.ps1
```

---

## 2. Permintaan Hak Administrator (UAC Prompt Loop)

### Penyebab:
Voltune memerlukan hak administrator penuh untuk mengakses registri sistem tingkat tinggi (`HKLM:\SYSTEM`, `HKLM:\SOFTWARE`), memanipulasi service Windows, dan membuat System Restore Point.

### Solusi:
Buka **PowerShell** atau **Windows Terminal** dengan cara:
1. Klik kanan ikon PowerShell / Terminal di menu Start.
2. Pilih **Run as Administrator** (Jalankan sebagai administrator).
3. Jalankan kembali `.\voltune.ps1`.

---

## 3. Perintah `winget` Tidak Dikenali di Tab "Install Apps"

### Gejala:
Aplikasi pada tab *Install Apps* gagal diunduh atau memunculkan pesan bahwa `winget` tidak ditemukan.

### Penyebab:
Fitur WinGet (Windows Package Manager) biasanya sudah terpasang di Windows 10/11 standar, namun mungkin belum aktif atau belum diinstal pada edisi Windows 10 LTSC, Windows Server, atau instalasi Windows kustom debloated.

### Solusi:
1. Buka Microsoft Store dan cari **App Installer**, lalu klik **Update / Install**.
2. Atau unduh installer WinGet resmi langsung dari rilis resmi GitHub:
   [https://github.com/microsoft/winget-cli/releases](https://github.com/microsoft/winget-cli/releases) (pilih berkas `.msixbundle` terbaru).

---

## 4. Game Tertentu Tidak Muncul di Tab "Game Tuner"

### Penyebab:
Game dipasang di folder non-standar (misalnya folder portabel, repack, atau emulator) yang tidak memiliki entri di registri instalasi Windows, library Steam `libraryfolders.vdf`, manifest Epic Games, atau launcher HoYoPlay.

### Solusi:
1. Di tab **Game Tuner**, klik tombol **Tambah Game Manual (.exe)** di bagian bawah kartu.
2. Arahkan browser berkas ke berkas executable utama game Anda (contoh: `D:\PortableGames\Cyberpunk2077\bin\x64\Cyberpunk2077.exe`).
3. Voltune akan secara otomatis membuatkan kartu optimasi untuk game tersebut dan mendaftarkannya ke profil GPU High Performance.

---

## 5. Kapasitas VRAM GPU atau Watt TGP Laptop Terlihat Kurang Pas

### Penyebab:
Pada versi Voltune lama (sebelum v3.3), WMI Windows membatasi pembacaan memori grafis hingga maksimal 4 GB untuk semua GPU 8GB/12GB/16GB, dan query TGP laptop standar sering memunculkan `[N/A]`.

### Solusi:
Pastikan Anda menjalankan **Voltune v3.3 atau lebih baru**. Voltune v3.3 menggunakan pembacaan multi-path `nvidia-smi` langsung dari driver grafis (`C:\Windows\System32\nvidia-smi.exe`) serta membaca `enforced.power.limit` sehingga nilai VRAM (contoh: 8.0 GB) dan wattage TGP riil (contoh: 45W) terbaca akurat.

---

## 6. Bagaimana Cara Membatalkan Semua Perubahan? (Undo Rollback)

### Solusi:
Voltune dirancang aman dan sepenuhnya dapat dibatalkan:
1. **Melalui GUI:** Buka tab **VoltUndo**, pilih snapshot cadangan dari dropdown riwayat (misalnya snapshot terbaru berlabel tanggal dan jam sebelum Anda mengoptimasi), lalu klik tombol **Kembalikan Snapshot Ini**.
2. **Melalui CLI:** Jalankan `.\voltune.ps1 -CLI`, lalu pilih opsi **[U] VoltUndo**.
3. **Melalui Windows System Restore:** Jika Anda memerlukan pemulihan sistem menyeluruh, buka *System Properties -> System Protection -> System Restore*, lalu pilih titik pemulihan berlabel **Voltune-PreOptimization**.
