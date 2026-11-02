# ERD Posyandu (Mermaid)

```mermaid
erDiagram
    USERS {
        uuid id PK
        string nik "encrypted (UK)"
        string nik_hash UK
        string name
        string password
        string role "ibu|kader|admin"
        string status "pending|active|rejected"
        string phone_number
        string jabatan
        string place_of_birth
        date date_of_birth
        string gender "L|P"
        text address
        string whatsapp
        string instagram
        string facebook
        uuid approved_by FK
        timestamp approved_at
        text rejection_reason
        timestamp verified_at
        timestamp email_verified_at
        string remember_token
        timestamps
        timestamp deleted_at
    }

    USER_VERIFICATIONS {
        uuid id PK
        uuid user_id FK
        string type "ktp|kk|kartu_keluarga|surat_keterangan|lainnya"
        string file_name
        string file_path
        text description
        timestamps
    }

    CHILDREN {
        uuid id PK
        uuid user_id FK
        string name
        string nik "encrypted (UK)"
        string nik_hash UK
        string gender "L|P"
        date birth_date
        string place_of_birth
        decimal birth_weight
        decimal birth_length
        string father_name
        string mother_name
        string address
        text medical_history
        text allergy
        text notes
        string blood_type
        json immunization_status
        boolean is_active
        timestamps
        timestamp deleted_at
    }

    VISITS {
        uuid id PK
        uuid child_id FK
        uuid kader_id FK
        date visit_date
        time visit_time
        string location
        text notes
        json meta
        timestamps
    }

    MEASUREMENTS {
        uuid id PK
        uuid child_id FK
        uuid kader_id FK
        uuid visit_id FK
        date measurement_date
        decimal weight_kg
        decimal height_cm
        decimal head_circumference_cm
        decimal arm_circumference_cm
        integer age_months
        decimal zscore_wfa
        decimal zscore_hfa
        decimal zscore_wfh
        decimal zscore_bfa
        string status_gizi "Gizi Buruk|Gizi Kurang|Gizi Baik|Berisiko Gizi Lebih|Gizi Lebih|Obesitas"
        string status_hfa
        string status_wfh
        string status_bfa
        text notes
        timestamps
    }

    IMMUNIZATION_TYPES {
        uuid id PK
        string code UK
        string name
        text description
        integer age_months_recommended
        integer dose_order
        boolean is_active
        timestamps
    }

    IMMUNIZATION_RECORDS {
        uuid id PK
        uuid child_id FK
        uuid immunization_type_id FK
        uuid kader_id FK
        uuid visit_id FK
        date immunization_date
        string batch_number
        text notes
        timestamps
        timestamp deleted_at
    }

    MEDICAL_NOTES {
        uuid id PK
        uuid child_id FK
        uuid kader_id FK
        uuid visit_id FK
        date note_date
        string complaint
        text diagnosis
        text treatment
        text advice
        timestamps
        timestamp deleted_at
    }

    POSYANDU_SCHEDULES {
        uuid id PK
        uuid created_by FK
        string title
        date scheduled_date
        time start_time
        time end_time
        string location
        string location_name
        text description
        string status "direncanakan|berlangsung|selesai|dibatalkan"
        timestamps
    }

    POSYANDU_SCHEDULE_PETUGAS {
        uuid schedule_id FK
        uuid petugas_id FK
        timestamps
    }

    REFERRALS {
        uuid id PK
        uuid child_id FK
        uuid visit_id FK
        uuid referred_by FK
        string referral_to
        string reason
        string status "dikirim|ditindaklanjuti|selesai|dibatalkan"
        text notes
        date referral_date
        timestamps
    }

    CONSENTS {
        uuid id PK
        uuid child_id FK
        uuid granted_by FK
        string type "data_processing|research|third_party"
        boolean granted
        timestamp granted_at
        timestamp revoked_at
        text ip_address
        text user_agent
        timestamps
    }

    AUDIT_LOGS {
        bigint id PK
        uuid user_id FK
        string action
        string model_type
        string model_id
        json old_values
        json new_values
        text ip_address
        text user_agent
        timestamps
    }

    WHO_WFA_STANDARDS {
        bigint id PK
        string sex
        decimal age_months
        decimal l
        decimal m
        decimal s
        decimal sd0
        decimal sd1neg
        decimal sd1pos
        decimal sd2neg
        decimal sd2pos
        decimal sd3neg
        decimal sd3pos
    }

    WHO_HFA_STANDARDS {
        bigint id PK
        string sex
        decimal age_months
        decimal l
        decimal m
        decimal s
        decimal sd0
        decimal sd1neg
        decimal sd1pos
        decimal sd2neg
        decimal sd2pos
        decimal sd3neg
        decimal sd3pos
    }

    WHO_BFA_STANDARDS {
        bigint id PK
        string sex
        decimal age_months
        decimal l
        decimal m
        decimal s
        decimal sd0
        decimal sd1neg
        decimal sd1pos
        decimal sd2neg
        decimal sd2pos
        decimal sd3neg
        decimal sd3pos
    }

    WHO_WFH_STANDARDS {
        bigint id PK
        string sex
        decimal length_cm
        decimal height_cm
        decimal l
        decimal m
        decimal s
        decimal sd0
        decimal sd1neg
        decimal sd1pos
        decimal sd2neg
        decimal sd2pos
        decimal sd3neg
        decimal sd3pos
    }

    USERS ||--o{ USERS : "approved_by"
    USERS ||--o{ USER_VERIFICATIONS : "has"
    USERS ||--o{ CHILDREN : "ibu_wali"
    USERS ||--o{ VISITS : "kader"
    USERS ||--o{ MEASUREMENTS : "kader"
    USERS ||--o{ IMMUNIZATION_RECORDS : "kader"
    USERS ||--o{ MEDICAL_NOTES : "kader"
    USERS ||--o{ POSYANDU_SCHEDULES : "created_by"
    USERS ||--o{ POSYANDU_SCHEDULE_PETUGAS : "petugas"
    USERS ||--o{ REFERRALS : "referred_by"
    USERS ||--o{ CONSENTS : "granted_by"
    USERS ||--o{ AUDIT_LOGS : "actor"

    CHILDREN ||--o{ VISITS : "has"
    CHILDREN ||--o{ MEASUREMENTS : "has"
    CHILDREN ||--o{ IMMUNIZATION_RECORDS : "has"
    CHILDREN ||--o{ MEDICAL_NOTES : "has"
    CHILDREN ||--o{ REFERRALS : "has"
    CHILDREN ||--o{ CONSENTS : "has"

    VISITS ||--o{ MEASUREMENTS : "has"
    VISITS ||--o{ IMMUNIZATION_RECORDS : "has"
    VISITS ||--o{ MEDICAL_NOTES : "has"
    VISITS ||--o{ REFERRALS : "has"

    IMMUNIZATION_TYPES ||--o{ IMMUNIZATION_RECORDS : "type"

    POSYANDU_SCHEDULES ||--o{ POSYANDU_SCHEDULE_PETUGAS : "detail"
```
