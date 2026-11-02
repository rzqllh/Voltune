# Model Keamanan & Jaminan Stabilitas Voltune (v3.3.0-Universal)

Voltune dibangun di atas filosofi: **Safe by default. Reversible by design. Zero VPN harm.**

Setiap optimasi, pembersihan disk, dan penyesuaian layanan diatur secara ketat untuk mencegah kerusakan pada Windows maupun software kerja pengguna.

---

## 1. Jaminan Keamanan Jaringan (Zero-VPN Harm)

Salah satu masalah terbesar skrip optimasi Windows pihak ketiga adalah merusak rute jaringan atau koneksi VPN kantor ketika menerapkan optimasi TCP/IP. Voltune mencegah hal ini dengan menerapkan **Network Whitelist Filter**:

- **Hanya Adapter Fisik:** Optimasi Nagle's Algorithm (`TcpAckFrequency = 1`, `TCPNoDelay = 1`) hanya diterapkan pada adapter jaringan Ethernet dan Wi-Fi fisik yang aktif.
- **Strict VPN & Virtual Whitelist:**
  - **Palo Alto GlobalProtect (`PanGPS`):** Dikenali dan dilewati secara mutlak dari segala modifikasi TCP/IP.
  - **Cisco AnyConnect, OpenVPN, WireGuard, TAP Adapters:** Dilewati secara otomatis.
  - **Virtual Network Adapters (Hyper-V, VMware, VirtualBox, WSL2):** Tidak pernah dimodifikasi.
- **Network Throttling Index:** Menyetel `0xFFFFFFFF` dan `SystemResponsiveness = 0` pada Multimedia Class Scheduler (MMCSS) untuk menghilangkan pembatasan throughput paket saat bermain game online tanpa mengganggu rute gateway VPN.

---

## 2. Dynamic Process Guard pada Pembersih Disk (VoltClean)

Saat membersihkan cache sementara Windows (`%TEMP%`, `C:\Windows\Temp`) dan shader cache (NVIDIA `DXCache`/`GLCache`, AMD, Intel, Steam shaders):
- Voltune mendeteksi proses yang sedang aktif berjalan.
- Berkas yang sedang dikunci oleh game atau browser aktif (Chrome, Edge, Firefox, Steam) secara otomatis dilewati dengan blok `try/catch` tanpa memaksa pemutusan proses atau menimbulkan error akses.
- Direktori sistem penting dilindungi dari penghapusan tidak sengaja.

---

## 3. Profil Aman Layanan Windows (Safe Gaming Services)

Optimasi layanan latar belakang di Voltune hanya menargetkan layanan telemetri dan bloat non-kritis:
- **Layanan yang Dioptimalkan:** `DiagTrack` (Connected User Experiences and Telemetry), `dmwappushservice` (WAP Push Message Routing), `MapsBroker` (Downloaded Maps Manager), `lfsvc` (Geolocation Service), `RemoteRegistry`, `RetailDemo`, `WerSvc` (Windows Error Reporting), dan layanan Xbox on-demand.
- **Layanan yang Mutlak Dilindungi (Tidak Pernah Dimatikan):**
  - **Audio & Komunikasi:** `Audiosrv` (Windows Audio), `AudioEndpointBuilder`.
  - **Pencetakan & Dokumen:** `Spooler` (Print Spooler).
  - **Jaringan & VPN:** `Dnscache`, `Dhcp`, `LanmanWorkstation`, `PanGPS` (GlobalProtect), `RasMan`.
  - **Keamanan Sistem:** `WinDefend` (Microsoft Defender Antivirus), `KeyIso`, `VaultSvc`.

---

## 4. Perlindungan Pembajakan Driver oleh Windows Update

Windows Update sering kali secara otomatis mengunduh driver GPU versi lama yang menimpa driver khusus NVIDIA/AMD yang sudah diinstal pengguna, menyebabkan game crash atau layar hitam.
- Voltune mengonfigurasi kebijakan registri:
  ```text
  HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
  "ExcludeWUDriversInQualityUpdate" = 1
  ```
- Kebijakan ini memastikan Windows Update hanya menerima pembaruan keamanan penting (*Security Updates Only*), tanpa merusak instalasi driver hardware resmi.

---

## 5. Arsitektur Pemulihan Penuh (VoltUndo & System Restore)

Sebelum optimasi massal diterapkan, Voltune secara otomatis menjalankan dua lapis pencadangan:
1. **Windows System Restore Point:** Memanggil cmdlet `Checkpoint-Computer` untuk membuat titik pemulihan sistem Windows resmi berlabel `Voltune-PreOptimization`.
2. **Snapshot Registri & Konfigurasi Berstempel Waktu:** Mengekspor seluruh kunci registri yang akan diubah ke format `.reg` di `%LOCALAPPDATA%\Voltune\Backups\Snapshot-<Timestamp>\`.
3. **1-Klik Pemulihan Total:** Melalui tab *VoltUndo* di GUI atau opsi `[U]` di CLI, pengguna dapat mengimpor kembali seluruh snapshot registri dengan utilitas resmi Windows `reg.exe import` dan mengembalikan konfigurasi sistem ke kondisi semula secara sempurna.
