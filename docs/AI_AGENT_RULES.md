# 🤖 AI Code Agent Rules & Guidelines (Strict Mode)

You are an expert Backend Developer assisting in building the "Smart Posyandu" REST API.
**CRITICAL INSTRUCTION:** Read these rules carefully before generating, refactoring, or modifying ANY code.

## 1. Architectural Principles
* **Fat Model, Skinny Controller:** Keep controllers clean. Business logic, complex queries, and data formatting should reside in Models, Services, or API Resources.
* **RESTful Standards:** Always use proper HTTP Verbs (GET, POST, PUT, DELETE, PATCH) and return standard HTTP Status Codes (200, 201, 401, 403, 404, 422, 500).
* **API Responses:** All API responses MUST return structured JSON.

## 2. Database & Models
* **Primary Keys:** ALL tables use `UUID` as primary keys. Always include `use HasUuids;` in Models.
* **Foreign Keys:** Must use `foreignUuid()` in migrations.
* **Mass Assignment:** Always define `$fillable` arrays in Models. NEVER use `$guarded = []`.

## 3. Security & Authentication
* **Auth System:** Use Laravel Sanctum (`auth:sanctum`). Never use session-based web auth logic.
* **Input Validation:** NEVER trust user input. Always use Laravel Form Requests or `$request->validate()`.

## 4. Coding Environment
* **Stack:** Laravel 13, PostgreSQL (Local via Laragon), Flutter (Mobile Client).
* **Database Management:** Developer uses HeidiSQL. SQL queries or DB administration advice should align with standard PostgreSQL syntax compatible with HeidiSQL.

## 5. IMMUTABILITY RULES (DO NOT MODIFY)
* **DO NOT** alter existing migration files once they have been migrated. If database changes are needed, generate a NEW migration file (e.g., `add_column_to_table`).
* **DO NOT** change the established Table Schemas, Route structures, or the `AuthController` unless explicitly instructed by the user.
* **DO NOT** change the `UUID` architecture to `auto-increment ID`.

## 6. BEHAVIORAL CONSTRAINTS
* **Strictly Additive:** When asked to implement a new feature, add new code. Do not refactor existing working code unless requested.
* **No Assumptions:** If a required table or relationship is missing from `DATABASE_SCHEMA.md`, ask the user for clarification before inventing one.

## 7. DOMAIN TERMINOLOGY & NAMING CONVENTIONS (CRITICAL)
Do NOT translate Indonesian domain-specific terms into English for variables, database columns, or routes. Use the following exact terms:
* **Posyandu:** Keep as `posyandu` (Not integrated health post).
* **Kader:** Keep as `kader` (Not cadre or health worker). Represents the admin/staff role.
* **Ibu / Orang Tua:** Keep as `ibu` or `parent`.
* **KMS (Kartu Menuju Sehat):** Keep as `kms` or `measurements`.
* **Balita / Anak:** Keep as `child` or `children` (Plural).
* **Stunting / Gizi Kurang:** Keep as standard string values for `status_gizi`.
* **MPASI:** Keep as `mpasi` (Makanan Pendamping ASI).

## 8. API RESPONSE ENVELOPE STANDARDIZATION
To ensure the Flutter mobile app can parse responses consistently, ALL Laravel API responses MUST follow this exact JSON envelope. NEVER invent new response structures.

**Success Response (200, 201):**
{
  "success": true,
  "message": "Deskripsi aksi berhasil",
  "data": { ... } // Or [] for arrays
}

**Error / Validation Response (400, 401, 403, 404, 422, 500):**
{
  "success": false,
  "message": "Deskripsi utama error",
  "errors": { ... } // Optional: Detailed validation errors array/object
}

## 9. DATABASE VS APPLICATION LOGIC ISOLATION
* **Z-Score Calculation:** The logic to calculate `z_score_wfa` and determine `status_gizi` MUST NOT be written in PHP (Laravel Controllers or Models). This logic is strictly reserved for PostgreSQL **Stored Procedures / Database Triggers**.
* If the user asks to implement the Z-Score logic, generate a Laravel Migration file that creates the `DB::unprepared()` SQL for the trigger, do NOT write a PHP helper function for it.

## 10. ERROR HANDLING
* Never use `dd()` or `var_dump()` in API controllers.
* Always use `try-catch` blocks for complex transactions. If catching an exception, return a `500` status code using the standardized Error Response Envelope above, and log the actual error using `Log::error()`.
