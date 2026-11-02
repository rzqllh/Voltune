# Panduan Pengujian & Distribusi Voltune (v3.3.0-Universal)

Voltune v3.3 adalah toolkit mandiri berbasis PowerShell dan WPF XAML yang **tidak memerlukan tahapan kompilasi binary biner eksternal**. Dokumen ini menjelaskan cara menjalankan, menguji, dan memvalidasi Voltune di lingkungan pengembangan.

---

## 1. Menjalankan Voltune Secara Lokal

### Mode Standar (Modern Native WPF GUI):
Buka PowerShell dengan hak Administrator, arahkan ke direktori repositori, lalu jalankan:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force
.\voltune.ps1
```

### Mode Terminal Interaktif (CLI Fallback):
Untuk lingkungan remote SSH, Windows Sandbox, atau sistem tanpa antarmuka grafis:

```powershell
.\voltune.ps1 -CLI
```

---

## 2. Menjalankan Suite Pengujian Otomatis

Voltune dilengkapi dengan skrip pengujian mandiri di folder `tests/` untuk memvalidasi syntax, integrasi hardware, pemuatan XAML GUI, dan keandalan backup.

### A. Uji Validasi Syntax & Profiling Hardware
Menguji apakah seluruh skrip valid secara leksikal di mesin Windows PowerShell 5.1 (bawaan Windows 10/11) dan PowerShell 7 (pwsh), serta memverifikasi fungsi pemindaian spek hardware:

```powershell
# Jalankan di Windows PowerShell 5.1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltune_syntax.ps1"

# Jalankan di PowerShell 7 (jika terpasang)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltune_syntax.ps1"
```

### B. Uji Inisialisasi WPF GUI & Elemen XAML
Memastikan dokumen XAML valid, dapat di-parse oleh `System.Windows.Markup.XamlReader`, dan seluruh kontrol interaktif utama (`btnRunSelectedTweaks`, `btnInstallSelectedApps`, `txtConsoleLog`) berhasil di-instansiasi:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_gui_load.ps1"
```

### C. Uji Snapshot Backup & Restore Engine (VoltUndo)
Memastikan pembuatan folder snapshot di `%LOCALAPPDATA%\Voltune\Backups\`, ekspor registri (`.reg`), dan pembuatan `manifest.json` berjalan tanpa hambatan:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "tests/test_voltundo_snapshot.ps1"
```

---

## 3. Standar Encoding & Integritas Berkas

> ⚠️ **SANGAT PENTING (ATURAN ENCODING):**
> Seluruh berkas skrip PowerShell (`.ps1`) di repositori ini **WAJIB** disimpan dalam format **UTF-8 with BOM (`utf-8-sig`)**.

* **Alasan Teknis:** Mesin parser bawaan Windows PowerShell 5.1 (`powershell.exe`) secara default membaca berkas teks non-BOM menggunakan ANSI code page lokal sistem (misalnya Windows-1252 di Windows versi regional tertentu). Karakter multibyte seperti simbol centang (`✓` / `\xE2\x9C\x93`) akan didekode secara keliru menjadi byte `0x93` (karakter quote ganda kiri `“`), yang merusak batas string dan memicu error parsing ampersand (`&`).
* Dengan menyertakan UTF-8 BOM (`EF BB BF`), Windows PowerShell 5.1 secara otomatis mengenali berkas sebagai UTF-8 murni.

---

## 4. Distribusi Instan (One-Liner Web)

Voltune didistribusikan langsung dari branch `main` GitHub melalui URL raw GitHub:

```powershell
irm https://raw.githubusercontent.com/rzqllh/Voltune/main/voltune.ps1 | iex
```

Setiap commit ke branch `main` langsung tersedia bagi pengguna one-liner tanpa perlu mengunggah release asset manual.
