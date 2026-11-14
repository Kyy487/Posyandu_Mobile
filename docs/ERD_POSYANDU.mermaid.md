# ERD Posyandu (Mermaid)

Diverifikasi terhadap migration dan schema PostgreSQL aktual pada 14 November
2026. Sumber kebenaran tetap migration di
`posyandu-backend/database/migrations/`; ERD ini hanya ringkasan relasi.

Rancangan perubahan Fase 1 yang sudah dikunci ada di
`docs/RANCANGAN_STANDARISASI.md`. Diagram di bawah adalah schema aktual
setelah perubahan Fase 1 diterapkan.

```mermaid
erDiagram
    USERS {
        uuid id PK
        text nik "encrypted, nullable"
        string nik_hash "HMAC-SHA256, unique, nullable"
        text no_kk "encrypted, not unique"
        string name
        string password
        string role "ibu|kader|admin"
        string status "pending|active|rejected"
        string verification_status "generated: pending|approved|rejected"
        string onboarding_status "need_child_data|completed"
        string phone_number
        string whatsapp "E.164, nullable"
        string instagram "handle, nullable"
        string facebook "handle, nullable"
        string jabatan
        string place_of_birth
        date date_of_birth
        string gender "L|P"
        string blood_type "A|B|AB|O"
        text address
        string rt_rw
        string education "SD|SMP|SMA|SMK|D3|S1|S2|S3|other"
        string occupation
        uuid approved_by FK
        timestamp approved_at
        text rejection_reason
        timestamp verified_at
        string remember_token
        timestamps
    }

    USER_VERIFICATIONS {
        uuid id PK
        uuid user_id FK
        string type "self_photo|ktp|kk|other"
        string file_path
        string file_name
        string mime_type
        timestamp uploaded_at
        timestamps
    }

    CHILDREN {
        uuid id PK
        uuid user_id FK
        text nik "encrypted, nullable"
        string nik_hash "HMAC-SHA256, unique, nullable"
        string ihs_number "unique, nullable"
        string name
        string place_of_birth
        string birth_place "alias lama"
        date date_of_birth
        string gender "L|P"
        smallint birth_order
        float birth_weight
        numeric birth_length "canonical"
        numeric birth_head_circumference
        string birth_status "normal|premature"
        string buku_kia_id
        text medical_flags
        float birth_height "generated from birth_length"
        timestamps
        timestamp deleted_at
    }

    POSYANDU_SCHEDULES {
        uuid id PK
        string title
        text description
        date scheduled_date
        time start_time
        time end_time
        string location
        string status "terjadwal|berlangsung|selesai|dibatalkan"
        text notes
        uuid created_by FK
        timestamps
    }

    POSYANDU_SCHEDULE_PETUGAS {
        bigint id PK
        uuid schedule_id FK
        uuid petugas_id FK
        timestamps
    }

    VISITS {
        uuid id PK
        uuid child_id FK
        uuid schedule_id FK
        date visit_date
        timestamp visit_started_at "timestamptz, nullable"
        timestamp visit_ended_at "timestamptz, nullable"
        string visit_type "posyandu|kunjungan_rumah|rujukan"
        uuid kader_id FK
        text anamnesis
        text catatan_kader
        text edukasi_gizi
        timestamps
        timestamp deleted_at
    }

    MEASUREMENTS {
        uuid id PK
        uuid child_id FK
        uuid visit_id FK
        uuid kader_id FK
        date measurement_date
        timestamp measured_at "timestamptz, nullable"
        numeric weight_kg
        numeric height_cm
        numeric head_circumference_cm
        integer age_in_months
        numeric z_score_wfa
        string status_gizi
        numeric z_score_hfa
        string status_stunting
        numeric z_score_bfa
        string status_gizi_imt
        numeric z_score_wfh
        string status_wfh
        timestamps
        timestamp deleted_at
    }

    IMMUNIZATION_TYPES {
        uuid id PK
        string code
        string name
        string kfa_code "nullable"
        string cvx_code "nullable"
        string cvx_display "nullable"
        string cvx_group_code "nullable"
        string target_disease_code "nullable"
        smallint dose_number
        smallint target_age_months
        smallint interval_months
        text notes
        boolean is_active
        timestamps
    }

    IMMUNIZATION_RECORDS {
        uuid id PK
        uuid child_id FK
        uuid immunization_type_id FK
        uuid visit_id FK
        uuid kader_id FK
        date date_given
        string batch_number
        text notes
        timestamps
        timestamp deleted_at
    }

    MEDICAL_NOTES {
        uuid id PK
        uuid child_id FK
        uuid measurement_id FK
        uuid visit_id FK
        uuid kader_id FK
        date note_date
        boolean demam
        boolean rewel
        boolean diare
        text catatan
        json red_flags "jsonb array, nullable"
        string icd10_code "nullable"
        string tindak_lanjut "ringan|sedang|rujuk"
        timestamps
        timestamp deleted_at
    }

    REFERRALS {
        uuid id PK
        uuid child_id FK
        uuid visit_id FK
        uuid kader_id FK
        date referral_date
        string referral_type "puskesmas|rs|faskes_lain"
        text reason
        string facility_name
        string status "dibuat|dilaporkan|selesai"
        timestamps
        timestamp deleted_at
    }

    CONSENTS {
        uuid id PK
        uuid child_id FK
        uuid granted_by FK
        string consent_type "data_processing|data_sharing|research"
        timestamp granted_at
        timestamp revoked_at
        string document_version
        text notes
        timestamps
    }

    AUDIT_LOGS {
        uuid id PK
        string auditable_type
        uuid auditable_id
        string event "created|updated|deleted|restored"
        uuid actor_id FK
        jsonb old_values
        jsonb new_values
        string ip_address
        timestamps
    }

    WHO_WFA_STANDARDS {
        uuid id PK
        smallint age_in_months
        char gender "L|P"
        numeric median_kg
        numeric sd_kg
        timestamps
    }

    WHO_HFA_STANDARDS {
        uuid id PK
        smallint age_in_months
        char gender "L|P"
        numeric l
        numeric m
        numeric s
        timestamps
    }

    WHO_BFA_STANDARDS {
        uuid id PK
        smallint age_in_months
        char gender "L|P"
        numeric l
        numeric m
        numeric s
        timestamps
    }

    WHO_WFH_STANDARDS {
        uuid id PK
        numeric length_cm
        char gender "L|P"
        numeric l
        numeric m
        numeric s
        timestamps
    }

    USERS ||--o{ USERS : "approved_by"
    USERS ||--o{ USER_VERIFICATIONS : "verifikasi"
    USERS ||--o{ CHILDREN : "ibu_wali"
    USERS ||--o{ VISITS : "kader"
    USERS ||--o{ MEASUREMENTS : "kader"
    USERS ||--o{ IMMUNIZATION_RECORDS : "kader"
    USERS ||--o{ MEDICAL_NOTES : "kader"
    USERS ||--o{ POSYANDU_SCHEDULES : "created_by"
    USERS ||--o{ POSYANDU_SCHEDULE_PETUGAS : "petugas"
    USERS ||--o{ REFERRALS : "kader"
    USERS ||--o{ CONSENTS : "granted_by"
    USERS ||--o{ AUDIT_LOGS : "actor"

    CHILDREN ||--o{ VISITS : "has"
    CHILDREN ||--o{ MEASUREMENTS : "has"
    CHILDREN ||--o{ IMMUNIZATION_RECORDS : "has"
    CHILDREN ||--o{ MEDICAL_NOTES : "has"
    CHILDREN ||--o{ REFERRALS : "has"
    CHILDREN ||--o{ CONSENTS : "has"

    POSYANDU_SCHEDULES ||--o{ VISITS : "agenda"
    POSYANDU_SCHEDULES ||--o{ POSYANDU_SCHEDULE_PETUGAS : "petugas"

    VISITS ||--o{ MEASUREMENTS : "has"
    VISITS ||--o{ IMMUNIZATION_RECORDS : "has"
    VISITS ||--o{ MEDICAL_NOTES : "has"
    VISITS ||--o{ REFERRALS : "has"

    MEASUREMENTS ||--o{ MEDICAL_NOTES : "measurement"
    IMMUNIZATION_TYPES ||--o{ IMMUNIZATION_RECORDS : "type"
```

Catatan:

- `posyandu_schedule_petugas` memakai `bigint` autoincrement sebagai PK, bukan
  UUID. Ini warisan migration lama dan satu-satunya pengecualian aturan UUID;
  jangan diubah tanpa migration baru.
- `visits` tidak punya unique `(child_id, visit_date)`. Satu anak boleh punya
  lebih dari satu kunjungan pada tanggal yang sama.
- `measurements` memakai partial unique `(child_id, measurement_date)` hanya
  untuk baris dengan `deleted_at IS NULL`.
- `immunization_records` memakai partial unique
  `(child_id, immunization_type_id)` hanya untuk baris aktif.
- `medical_notes` memakai partial unique `(child_id, note_date)` hanya untuk
  baris aktif.
- `who_*_standards` adalah data referensi internal, bukan resource FHIR.

## Perubahan Fase 1 (Sudah Diterapkan)

Perubahan berikut tidak mengubah relasi utama dan sudah ada di diagram aktual:

- `USERS`: `whatsapp`, `instagram`, `facebook`; role `admin`.
- `USER_VERIFICATIONS`: tipe `ktp` diterima untuk unggah ulang.
- `CHILDREN`: `ihs_number` unique nullable.
- `VISITS`: `visit_started_at`, `visit_ended_at`, `edukasi_gizi`.
- `MEASUREMENTS`: `measured_at`.
- `IMMUNIZATION_TYPES`: `kfa_code`, `cvx_code`, `cvx_display`,
  `cvx_group_code`, `target_disease_code`.
- `MEDICAL_NOTES`: `red_flags` JSONB, `icd10_code` nullable.

Tidak ada tabel baru di Fase 1. Urutan migration dan struktur kode ada di
`docs/RANCANGAN_STANDARISASI.md`.
