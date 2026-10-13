# KelolaKerja — Employee Attendance & Reporting System with Face Recognition

![Perl](https://img.shields.io/badge/Backend-Perl%205.38%20%7C%20PSGI%20%7C%20uWSGI-39457E?style=flat-square)
![Frontend](https://img.shields.io/badge/Frontend-Vue.js%202.6%20%7C%20Quasar%201.15-1976D2?style=flat-square)
![Biometrics](https://img.shields.io/badge/Computer%20Vision-ResNet--34%20128D%20%2B%2068--Landmark%203D-15803D?style=flat-square)
![Database](https://img.shields.io/badge/Database-MariaDB%2010.11%20%2B%20Redis%207-003545?style=flat-square)
![Docker](https://img.shields.io/badge/Deployment-Docker%20Compose%20%2B%20Nginx-2496ED?style=flat-square)

**KelolaKerja** adalah sistem absensi wajah (*Face Recognition*) dan pelaporan aktivitas harian karyawan berbasis web dengan verifikasi anti-spoofing 3D *real-time*, penguncian biometrik 1:1 & 1:N, pengendalian hak akses berbasis peran (**RBAC**), serta pencatatan jejak keamanan (*Audit Trail*).

---

## Fitur Utama

### 1. Keamanan Biometrik Wajah & Anti-Spoofing 3D
- **Deep Learning Face Recognition (ResNet-34 128-D):** Mengekstrak 128 dimensi vektor *embedding* wajah menggunakan jaringan saraf tiruan (`face_recognition_model` ResNet-34).
- **Pencocokan Ganda Ketat (1:1 Verification):** Verifikasi absensi mewajibkan **Euclidean Distance <= 0.4200** sekaligus **Cosine Similarity >= 89.0%** terhadap vektor wajah pemilik akun.
- **2-Stage 68-Landmark 3D Active Liveness:**
  - **Tahap 1 (Tantangan 3D Bertanda Tangan Server):** Server menerbitkan token tantangan HMAC-SHA256 (`TURN_LEFT`, `TURN_RIGHT`, `SMILE_OPEN`, `HEAD_NOD`). Sistem memverifikasi pergeseran paralaks 3D ujung hidung terhadap kontur rahang (`68-point facial landmarks`) untuk menolak foto cetak maupun layar ponsel.
  - **Tahap 2 (Kunci Vektor Frontal):** Mengambil rata-rata *descriptor* pada 3 *frame* frontal berturut-turut dan memvalidasi konsistensi jarak antar-*frame* (`motion_embedding` vs `primary_embedding`).
- **1:N Cross-Account Deduplication:** Mencegah satu orang mendaftarkan wajahnya pada lebih dari satu akun karyawan (`HTTP 409 Conflict`).
- **Self-Overwrite Lock:** Akun yang sudah memiliki wajah terdaftar terkunci secara otomatis dan tidak dapat ditimpa oleh wajah orang lain kecuali di-*reset* oleh Administrator.

### 2. Pelaporan Aktivitas Harian & Verifikasi Berjenjang
- **Jurnal Kerja Harian:** Karyawan membuat laporan aktivitas, capaian hasil (*output*), serta kendala harian.
- **Alur Persetujuan (Approval Workflow):** Supervisor dan Admin meninjau laporan berstatus `SUBMITTED`, memberikan catatan verifikator, serta menetapkan keputusan **Setujui (`APPROVED`)** atau **Tolak (`REJECTED`)**.
- **Revisi Laporan:** Laporan yang ditolak (`REJECTED`) dapat diperbaiki dan dikirim ulang oleh karyawan, sedangkan laporan yang telah disetujui (`APPROVED`) dikunci secara permanen.

### 3. Role-Based Access Control (RBAC) & Audit Trail
- **3 Level Hak Akses:**
  - `EMPLOYEE` — Registrasi biometrik pribadi, absensi masuk/pulang (`Check-In` / `Check-Out`), dan pengajuan laporan harian.
  - `SUPERVISOR` — Seluruh akses karyawan + pemantauan kehadiran tim dan verifikasi laporan aktivitas.
  - `ADMIN` — Seluruh akses sistem + rekapitulasi kehadiran perusahaan, manajemen akun karyawan, *reset* kunci biometrik wajah, dan pemantauan *Audit Log*.
- **Security Audit Log:** Mencatat seluruh aktivitas login, pendaftaran wajah, percobaan *spoofing*, ketidakcocokan wajah (*impostor attempt*), perubahan laporan, hingga manajemen pengguna beserta alamat IP dan waktu server.

---

## Spesifikasi Teknologi (Technology Stack)

| Lapisan | Teknologi |
| :--- | :--- |
| **Frontend** | JavaScript (ES6+), Vue.js v2.6, Quasar Framework v1.15, HTML5/CSS3, MediaDevices WebRTC API |
| **Computer Vision** | `@vladmandic/face-api` (TinyFaceDetector, 68-Point Landmark Net, ResNet-34 128-D Recognition Net, FaceExpressionNet) |
| **Backend** | Perl 5 (kompatibel v5.38), Arsitektur MVC Modular (`Controller`, `Model`, `Service`, `Router`, `Auth`), PSGI (`web.pl`) |
| **App Server & Gateway** | uWSGI (PSGI plugin) + Nginx Reverse Proxy |
| **Database & Cache** | MariaDB 10.11 (`DBD::mysql`) + Redis 7 |
| **Dokumentasi & Pengujian** | OpenAPI 3.0 (`kelolakerja.yaml`), Perl `Test::More` (`prove`) |

---

## Struktur Direktori

```text
kelolakerja/
├── backend/
│   ├── Dockerfile                 # Image Perl 5 + uWSGI PSGI + DBD::mysql
│   ├── web.pl                     # Entrypoint PSGI aplikasi backend
│   ├── server.pl                  # Standalone HTTP server untuk pengembangan lokal
│   ├── db/
│   │   ├── schema.sql             # DDL tabel (users, face_biometrics, attendances, activity_reports, audit_logs)
│   │   └── seed.sql               # Data akun awal (Admin, Supervisor, Karyawan)
│   ├── etc/api/
│   │   └── kelolakerja.yaml       # Spesifikasi REST API OpenAPI 3.0
│   ├── lib/KelolaKerja/
│   │   ├── Config.pm              # Konfigurasi environment & ambang batas biometrik (0.42)
│   │   ├── Db.pm                  # Koneksi DBI MariaDB/MySQL
│   │   ├── Auth.pm                # Hashing PBKDF2/SHA-256 & Token HMAC-SHA256
│   │   ├── Response.pm            # Helper serialisasi JSON HTTP
│   │   ├── Router.pm              # Dispatcher REST API & middleware RBAC
│   │   ├── Model/                 # User.pm, Attendance.pm, Report.pm, Audit.pm
│   │   ├── Service/               # FaceMatcher.pm (ResNet-34 validation, Euclidean, Cosine, 3D Liveness)
│   │   └── Controller/            # AuthController, BiometricController, AttendanceController, ReportController, AdminController
│   └── t/                         # Unit & Integration Tests (01_auth.t, 02_facematcher.t, 03_integration_api.t)
├── frontend/
│   ├── Dockerfile
│   ├── package.json               # Konfigurasi dependensi Vue 2.6 & Quasar 1.15
│   ├── quasar.conf.js             # Konfigurasi Webpack 4 & PWA Workbox
│   ├── src/                       # Source komponen Vue, router, dan faceService
│   └── dist/spa/                  # Production SPA bundle yang disajikan oleh Nginx
│       ├── index.html
│       ├── styles.css
│       ├── app.js
│       ├── vendor/face-api.js     # Bundle lokal TensorFlow.js + Face-API
│       └── models/                # Bobot neural network ResNet-34 & 68-Landmark (13 MB)
├── docker/
│   └── nginx.conf                 # Konfigurasi Nginx Reverse Proxy & Static Serving
├── docs/
│   └── AUDIT_AND_ARCHITECTURE.md  # Dokumentasi arsitektur & desain keamanan
├── docker-compose.yml             # Orkestrasi container (db, redis, backend, gateway)
├── .env.example                   # Template variabel environment
└── .gitignore
```

---

## Cara Menjalankan Proyek (Quick Start)

### Prasyarat
- **Docker** dan **Docker Compose** telah terpasang.
- Browser modern dengan akses kamera (*Webcam*).

### 1. Clone Repositori & Siapkan Environment
```bash
git clone https://github.com/Fadhilstr/KelolaKerja.git
cd KelolaKerja
cp .env.example .env
```

### 2. Jalankan Seluruh Layanan dengan Docker Compose
```bash
docker compose up -d --build
```

Setelah container berstatus *running/healthy*, seluruh layanan diakses melalui satu pintu (*Single Gateway* Nginx):
- **Aplikasi Web:** [http://localhost:8080](http://localhost:8080)
- **REST API Gateway:** `http://localhost:8080/api/health`
- **Keamanan Jaringan Container:** Layanan database (`MariaDB`), cache (`Redis`), dan aplikasi `Backend` diisolasi di dalam jaringan internal Docker (`expose`) tanpa membuka port langsung ke luar *host*.

---

## Akun Pengujian Awal (Seed Accounts)

| Peran (Role) | Username | Password | Hak Akses Utama |
| :--- | :--- | :--- | :--- |
| **ADMIN** | `admin` | `admin123` | Dashboard perusahaan, kelola akun & role, reset biometrik wajah, audit log |
| **SUPERVISOR** | `supervisor` | `supervisor123` | Monitoring kehadiran tim, persetujuan/penolakan laporan harian karyawan |
| **EMPLOYEE** | `karyawan` | `karyawan123` | Registrasi wajah ResNet-34, absensi Check-In/Check-Out, laporan aktivitas harian |

> **Catatan Keamanan:** Kredensial di atas hanya merupakan *seed data* untuk lingkungan pengembangan/pengujian lokal (`development`). Sebelum men-deploy ke lingkungan produksi, wajib mengganti `DB_PASS` dan `TOKEN_SECRET` pada file `.env` (yang sudah diabaikan oleh `.gitignore`) serta mengganti password akun bawaan.

---

## Panduan Pengujian Fitur

### A. Pendaftaran & Absensi Wajah (Anti-Spoofing)
1. Login menggunakan akun **`karyawan`** (`karyawan123`).
2. Buka menu **Registrasi Wajah** → klik **Buka Kamera Pendaftaran**.
3. Selesaikan **Tahap 1** (ikuti instruksi gerakan 3D seperti menoleh atau tersenyum), lalu hadapkan wajah lurus ke tengah lingkaran pada **Tahap 2** hingga muncul status hijau **`LIVENESS LULUS & TERKUNCI`**.
4. Klik **Ambil & Kunci Biometrik Wajah**.
5. Buka menu **Absensi Wajah**, aktifkan kamera, selesaikan tantangan *liveness*, lalu klik **Absen Masuk (Check-In)** atau **Absen Pulang (Check-Out)**.

### B. Pelaporan & Verifikasi Supervisor
1. Pada akun **`karyawan`**, buka menu **Laporan Aktivitas** → klik **+ Buat Laporan Baru** → isi form dan simpan.
2. Keluar dan login sebagai **`supervisor`** (`supervisor123`) atau **`admin`** (`admin123`).
3. Buka menu **Verifikasi Laporan** → klik **Setujui** atau **Tolak** pada laporan karyawan dan tambahkan catatan verifikator.

---

## Ringkasan Endpoint REST API

Spesifikasi lengkap tersedia di [`backend/etc/api/kelolakerja.yaml`](backend/etc/api/kelolakerja.yaml).

| Method | Endpoint | Role | Deskripsi |
| :--- | :--- | :--- | :--- |
| `GET` | `/api/health` | Public | Pemeriksaan status layanan backend |
| `POST` | `/api/auth/login` | Public | Autentikasi pengguna & penerbitan token Bearer |
| `POST` | `/api/auth/logout` | Semua Role | Pencabutan sesi login |
| `GET` | `/api/auth/me` | Semua Role | Informasi profil pengguna aktif |
| `GET` | `/api/biometric/challenge` | Semua Role | Penerbitan token tantangan *liveness* 3D (HMAC-SHA256) |
| `GET` | `/api/biometric/status` | Semua Role | Status registrasi biometrik wajah akun |
| `POST` | `/api/biometric/register` | Semua Role | Pendaftaran & penguncian vektor wajah 128-D ResNet-34 |
| `POST` | `/api/attendance/check-in` | Semua Role | Absensi masuk dengan verifikasi liveness 3D & kecocokan 1:1 |
| `POST` | `/api/attendance/check-out` | Semua Role | Absensi pulang dengan verifikasi liveness 3D & kecocokan 1:1 |
| `GET` | `/api/attendance/today` | Semua Role | Status kehadiran hari ini |
| `GET` | `/api/attendance/history` | Semua Role | Riwayat kehadiran pribadi |
| `GET` | `/api/attendance/admin-overview` | `SUPERVISOR`, `ADMIN` | Statistik & rekapitulasi kehadiran seluruh karyawan |
| `GET` | `/api/reports` | Semua Role | Daftar laporan aktivitas (filter sesuai role) |
| `POST` | `/api/reports` | Semua Role | Pengajuan laporan aktivitas harian baru |
| `PUT` | `/api/reports/:id` | Semua Role | Pembaruan/revisi laporan sebelum disetujui |
| `POST` | `/api/reports/:id/verify` | `SUPERVISOR`, `ADMIN` | Persetujuan (`APPROVED`) atau penolakan (`REJECTED`) laporan |
| `GET` | `/api/admin/users` | `ADMIN` | Daftar seluruh pengguna & status biometrik |
| `POST` | `/api/admin/users` | `ADMIN` | Pembuatan akun karyawan baru |
| `PUT` | `/api/admin/users/:id/status` | `ADMIN` | Aktivasi / penonaktifan akun karyawan |
| `DELETE` | `/api/admin/users/:id/biometric` | `ADMIN` | Reset kunci biometrik wajah pengguna |
| `GET` | `/api/admin/audit-logs` | `ADMIN` | Jejak keamanan & log audit sistem |

---

## Akses Database & Pengujian Otomatis

### Masuk ke Konsol MariaDB (Pengembangan Lokal)
```bash
# Masuk melalui container Docker (masukkan DB_PASS sesuai file .env saat diminta)
docker exec -it kelolakerja_db mariadb -u root -p kelolakerja_db
```

### Menjalankan Unit & Integration Test
```bash
# Menjalankan seluruh test suite Perl (31 assertions)
prove -Ibackend/lib backend/t/

# Atau melalui container backend
docker exec kelolakerja_backend prove -Ilib t/
```

---

## Manajemen Container & Troubleshooting

```bash
# Melihat status seluruh container
docker compose ps

# Melihat log aktivitas backend secara langsung (live logs)
docker compose logs -f backend

# Me-restart layanan backend setelah mengubah modul Perl (.pm)
docker restart kelolakerja_backend

# Menghentikan seluruh layanan
docker compose down
```

---