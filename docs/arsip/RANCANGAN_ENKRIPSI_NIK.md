# Rancangan Enkripsi NIK (UU PDP)

> **Status:** Rancangan — **belum diimplementasikan**
> **Tanggal:** 12 Oktober 2026
> **Dokumen acuan:** `PERANCANGAN_PERKUATAN.md` §9, `AI_AGENT_RULES.md`
> **Aturan:** `posyandu-backend/.ai/rules/yang-jangan-diubah.md`

---

## 1. Tujuan & Ruang Lingkup

NIK adalah data pribadi yang dilindungi UU PDP. Saat ini NIK tersimpan plain-text
di database. Rancangan ini mengenkripsi NIK di rest (at rest) agar tidak terbaca
bila database bocor.

**Termasuk:**
1. Enkripsi kolom `nik` di tabel `users` dan `children`.
2. Lookup NIK untuk login memakai `nik_hash` (SHA-256, tidak reversible).
3. Cast Eloquent `encrypted` agar transparan bagi kode aplikasi.

**Tidak termasuk:**
- Enkripsi field lain (name, phone, dll) — hanya NIK dulu.
- Key management server (KMS) — pakai `APP_KEY` yang sudah ada.
- Enkripsi in-transit (HTTPS) — tanggung jawab deployment.

---

## 2. Pendekatan

- **Algoritma:** AES-256-GCM via Laravel `encrypt()`/`decrypt()` (built-in).
- **Key:** `APP_KEY` yang sudah ada — tidak perlu key management terpisah.
- **Cast:** Eloquent cast `encrypted` — auto encrypt saat save, decrypt saat read.
- **Lookup:** tambah kolom `nik_hash` (SHA-256) untuk pencarian saat login.

---

## 3. Perubahan per Komponen

| Komponen | Perubahan |
|---|---|
| Migration baru | `encrypt_nik_on_users_table` + `encrypt_nik_on_children_table` |
| Model `User` | Cast `nik` → `encrypted` |
| Model `Child` | Cast `nik` → `encrypted` |
| `UserFactory` | NIK di-generate plain, cast yang mengenkripsi |
| `ChildFactory` | Sama |
| `AuthController@login` | Cari by `nik_hash`, bukan `nik` |
| Endpoint yang menampilkan NIK | Pastikan tidak ada yang mengirim NIK ke klien |

---

## 4. Migration Strategy

1. Tambah `nik_encrypted` (text, nullable) + `nik_hash` (string 64, nullable).
2. Backfill: copy `nik` → `nik_encrypted` (encrypt) + `nik_hash` (hash).
3. Verifikasi semua baris terenkripsi.
4. Drop kolom `nik` lama.
5. Rename `nik_encrypted` → `nik`.

---

## 5. Masalah Kritis: Login by NIK

`AuthController@login` menerima NIK + password. Kalau NIK dienkripsi, tidak bisa
`where('nik', $nik)` langsung.

**Solusi:** tambah kolom `nik_hash` (SHA-256, unindexed) untuk lookup.
Login: hash input → cari by `nik_hash` → verify password.

`nik_hash` tidak reversible, hanya untuk pencarian.

---

## 6. Test

- NIK tersimpan encrypted di DB (bukan plain).
- Login by NIK tetap jalan.
- NIK tidak muncul di response API.
- `nik_hash` konsisten untuk NIK yang sama.

---

## 7. Risiko & Mitigasi

| Risiko | Mitigasi |
|---|---|
| `APP_KEY` ganti → NIK tidak bisa didekripsi | Simpan key lama untuk decrypt-only |
| Backup DB tidak terenkripsi | Backup di lingkungan yang aman |
| Lupa `nik_hash` → login gagal | Test wajib mencakup login by NIK |

---

## 8. Urutan Langkah Implementasi

1. `[ ]` Migration `encrypt_nik_on_users_table` + `encrypt_nik_on_children_table`
2. `[ ]` Model `User` + `Child`: cast `encrypted`
3. `[ ]` `UserFactory` + `ChildFactory`: NIK plain → cast encrypt
4. `[ ]` `AuthController@login`: cari by `nik_hash`
5. `[ ]` Test: NIK encrypted, login jalan, NIK tidak di response
6. `[ ]` Full suite + Pint
7. `[ ]` Update docs (`API_CONTRACT.md`, `DATABASE_SCHEMA.md`)
8. `[ ]` Commit + push

---

## 9. Referensi

- `PERANCANGAN_PERKUATAN.md` §9 — Prioritas P1
- `AI_AGENT_RULES.md` — Aturan wajib
- `posyandu-backend/.ai/rules/yang-jangan-diubah.md` — Aturan backend
