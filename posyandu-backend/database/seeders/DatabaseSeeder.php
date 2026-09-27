<?php

namespace Database\Seeders;

use App\Models\Child;
use App\Models\ImmunizationType;
use App\Models\MedicalNote;
use App\Models\PosyanduSchedule;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

/**
 * Seeder idempotent.
 *
 * Aman dijalankan berkali-kali: `php artisan db:seed` tidak boleh menggandakan
 * akun, anak, master vaksin, maupun agenda. Semua baris dicocokkan lewat kunci
 * alami (NIK untuk user/anak, `code` + `dose_number` untuk master vaksin,
 * `title` untuk agenda contoh) dan memakai `firstOrNew`/`updateOrCreate`,
 * bukan `create()`.
 *
 * Yang TIDAK ditimpa saat baris sudah ada: kredensial akun. Password hanya
 * dipasang ketika baris dibuat, jadi password yang sudah diganti pengguna
 * tetap aman (lihat `makeUser`).
 *
 * Yang justru MELETAKI ulang: data anak contoh, master vaksin, dan agenda
 * contoh. Baris-baris ini milik seeder, bukan milik pengguna, jadi isinya
 * dibalik ke nilai acuan setiap kali dijalankan. Jangan menaruh data produksi
 * di NIK yang sama dengan NIK contoh di bawah.
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->seedIbu();
        $this->seedKader();
        $this->seedAnak();
        $this->seedImmunizationTypes();
        $this->seedSchedules();
        $this->seedMedicalNotes();
    }

    /**
     * Akun Ibu. `jabatan` sengaja dibiarkan kosong: kolom itu hanya diisi untuk
     * petugas posyandu.
     */
    private function seedIbu(): void
    {
        $this->makeUser('1111222233334444', 'Ibu Annisa', 'ibu');
        $this->makeUser('1111222233334445', 'Ibu Ceri', 'ibu');
    }

    /**
     * Minimal 5 akun Kader sesuai kebutuhan operasional: beberapa bidan dan
     * kader posyandu. `jabatan` disimpan terpisah dari `role` karena `role`
     * hanya punya dua nilai (`ibu` / `kader`) dan dipakai untuk otorisasi
     * endpoint.
     */
    private function seedKader(): void
    {
        $petugas = [
            ['5555666677778888', 'Kader Siti', 'Kader Posyandu'],
            ['5555666677778889', 'Bidan Rina', 'Bidan'],
            ['5555666677778890', 'Kader Dewi', 'Kader Posyandu'],
            ['5555666677778891', 'Kader Tati', 'Kader Posyandu'],
            ['5555666677778892', 'Bidan Yuni', 'Bidan'],
        ];

        foreach ($petugas as [$nik, $name, $jabatan]) {
            $this->makeUser($nik, $name, 'kader', $jabatan);
        }
    }

    /**
     * Membuat akun bila NIK belum terdaftar.
     *
     * Password hanya di-set saat baris baru dibuat. Kalau akun sudah ada,
     * password yang sudah diganti pengguna tidak ditimpa kembali ke
     * `password123`.
     */
    private function makeUser(string $nik, string $name, string $role, ?string $jabatan = null): User
    {
        $user = User::firstOrNew(['nik' => $nik]);

        if (! $user->exists) {
            $user->name = $name;
            $user->role = $role;
            $user->password = Hash::make('password123');
        }

        // `jabatan` boleh di-update: ini data referensi yang memang dikelola
        // di sisi posyandu, bukan kredensial.
        if ($jabatan !== null) {
            $user->jabatan = $jabatan;
        }

        $user->save();

        return $user;
    }

    private function seedAnak(): void
    {
        $annisa = User::where('nik', '1111222233334444')->first();
        $ceri = User::where('nik', '1111222233334445')->first();

        $anak = [
            ['1234567890123456', 'Budi Santoso', '2025-05-10', 'L', 3.2, 50.0, $annisa?->id],
            ['1234567890123459', 'Ceril Ganteng', '2025-05-11', 'L', 3.2, 50.0, $annisa?->id],
            ['1234567890123457', 'Zainab Putri', '2025-12-01', 'P', 3.1, 49.5, $ceri?->id],
        ];

        foreach ($anak as [$nik, $name, $dob, $gender, $weight, $height, $userId]) {
            if (! $userId) {
                continue;
            }

            Child::updateOrCreate(
                ['nik' => $nik],
                [
                    'user_id' => $userId,
                    'name' => $name,
                    'date_of_birth' => $dob,
                    'gender' => $gender,
                    'birth_weight' => $weight,
                    'birth_height' => $height,
                ]
            );
        }
    }

    /**
     * Master 16 dosis imunisasi (program HB Indonesian).
     *
     * SENGaja memakai `updateOrCreate` dengan kunci `code` + `dose_number`,
     * yang persis sama dengan unique constraint
     * `immunization_types_code_dose_unique` di database. Jadi seeder ini
     * tidak pernah bisa membuat dua baris untuk dosis yang sama.
     *
     * `interval_months` = jarak dari dosis sebelumnya dalam bulan; null untuk
     * dosis pertama. Nilai ini hanya dikirim ke klien untuk ditampilkan di
     * form (jarak antar dosis).
     *
     * Catatan: nilai `interval_months` ini TIDAK dipakai server untuk
     * menghitung tanggal ideal. Validasi yang ada membandingkan tanggal yang
     * benar-benar dicatat pada dosis tetangga N-1 dan N+1 pada vaksin yang
     * sama - bukan mengukum dari `interval_months`. Anak boleh datang dengan
     * dosis 2 tanpa dose 1 (misalnya dosis 1 diberikan di fasilitas lain),
     * jadi menolak berdasarkan master interval akan menghambat.
     */
    private function seedImmunizationTypes(): void
    {
        $types = [
            // Hepatitis B - 4 dosis (0, 2, 4, 6 bulan)
            ['HB', 'Hepatitis B', 1, 0, null],
            ['HB', 'Hepatitis B', 2, 2, 2],
            ['HB', 'Hepatitis B', 3, 4, 2],
            ['HB', 'Hepatitis B', 4, 6, 2],

            // BCG - 1 dosis (2 bulan)
            ['BCG', 'BCG', 1, 2, null],

            // Polio Oral - 5 dosis (0, 2, 3, 4, 6 bulan)
            ['POLIO', 'Polio Oral', 1, 0, null],
            ['POLIO', 'Polio Oral', 2, 2, 2],
            ['POLIO', 'Polio Oral', 3, 3, 1],
            ['POLIO', 'Polio Oral', 4, 4, 1],
            ['POLIO', 'Polio Oral', 5, 6, 2],

            // DPT-HB-Hib - 4 dosis (2, 3, 4, 6 bulan)
            ['DPT-HB-HIB', 'DPT-HB-Hib', 1, 2, null],
            ['DPT-HB-HIB', 'DPT-HB-Hib', 2, 3, 1],
            ['DPT-HB-HIB', 'DPT-HB-Hib', 3, 4, 1],
            ['DPT-HB-HIB', 'DPT-HB-Hib', 4, 6, 2],

            // Campak-Rubella - 2 dosis (9, 18 bulan)
            ['MR', 'Campak-Rubella', 1, 9, null],
            ['MR', 'Campak-Rubella', 2, 18, 9],
        ];

        foreach ($types as [$code, $name, $dose, $target, $interval]) {
            ImmunizationType::updateOrCreate(
                ['code' => $code, 'dose_number' => $dose],
                [
                    'name' => $name,
                    'target_age_months' => $target,
                    'interval_months' => $interval,
                ]
            );
        }
    }

    /**
     * Tiga agenda contoh untuk Kader.
     *
     * Kunci alaminya adalah `title`, bukan `scheduled_date`. Ini penting:
     * tanggal agenda dihitung relatif terhadap hari ini, jadi kalau
     * `scheduled_date` ikut jadi kunci, setiap `db:seed` pada hari yang
     * berbeda akan mencocokkan nol baris dan membuat tiga agenda baru -
     * berulang kali sampai tabel penuh.
     *
     * Dengan `firstOrNew(['title' => ...])` jumlah baris agenda contoh
     * selalu tiga, sekecil apa pun selisih hari antar menjalankan seeder.
     * Nilai `scheduled_date`, jam, dan status tetap ditulis ulang supaya
     * agenda demo tidak lama-lama berubah menjadi "kegagalan" yang lewat
     * tanggal. Status yang sudah diubah Kader (misal `selesai`) juga akan
     * dikembalikan ke `terjadwal`, karena baris ini memang milik seeder.
     */
    private function seedSchedules(): void
    {
        $creator = User::where('role', 'kader')->orderBy('nik')->first();
        $petugas = User::where('role', 'kader')->pluck('id');

        if (! $creator || $petugas->isEmpty()) {
            return;
        }

        $agenda = [
            [
                'title' => 'Penimbangan Rutin Bulanan',
                'description' => 'Penimbangan dan pengukuran tinggi badan balita.',
                'scheduled_date' => now()->addDays(7)->toDateString(),
                'start_time' => '08:00',
                'end_time' => '11:00',
                'status' => PosyanduSchedule::STATUS_TERJADWAL,
            ],
            [
                'title' => 'Vaksinasi Massal',
                'description' => 'Suntikan rutin sesuai jadwal imunisasi nasional.',
                'scheduled_date' => now()->addDays(14)->toDateString(),
                'start_time' => '09:00',
                'end_time' => '12:00',
                'status' => PosyanduSchedule::STATUS_TERJADWAL,
            ],
            [
                'title' => 'Kunjungan Rumah Balita Stunting',
                'description' => 'Monitoring tumbuh kembang balita berisiko.',
                'scheduled_date' => now()->addDays(21)->toDateString(),
                'start_time' => '10:00',
                'end_time' => '13:00',
                'status' => PosyanduSchedule::STATUS_TERJADWAL,
            ],
        ];

        foreach ($agenda as $item) {
            $schedule = PosyanduSchedule::firstOrNew(['title' => $item['title']]);
            $schedule->fill($item);
            $schedule->location = config('posyandu.posyandu_name');
            $schedule->created_by ??= $creator->id;
            $schedule->save();

            // Sinkronkan petugas: agenda contoh ditangani 3 kader pertama.
            $schedule->petugas()->sync($petugas->take(3));
        }
    }

    /**
     * Catatan keluhan contoh.
     *
     * Satu anak satu catatan per hari, jadi kuncinya adalah pasangan
     * `(child_id, note_date)` - persis sama dengan unique constraint
     * `medical_notes_child_date_unique` di database. Dengan begitu seeder ini
     * tidak mungkin membuat baris yang melanggar constraint-nya sendiri, dan
     * aman dijalankan berkali-kali.
     *
     * Tanggal sengaja dihitung relatif terhadap hari ini, bukan tanggal tetap.
     * `subMonthNoOverflow()` dipakai untuk bulan lalu supaya tanggalnya tidak
     * pernah melompat ke bulan yang lebih kecil (31 -> 28/29, bukan 3), dan
     * `now()` untuk bulan ini supaya tanggalnya tidak pernah berada di masa
     * depan ketika `db:seed` dijalankan tanggal 1 - catatan besok bukan
     * riwayat yang masuk akal.
     *
     * Effect-nya: endpoint tanpa filter (default bulan berjalan) langsung punya
     * isi, dan filter `?month=` bulan lalu juga bisa diuji.
     *
     * `measurement_id` sengaja dibiarkan null: keluhan bisa dicatat tanpa
     * penimbangan, dan seeder ini tidak membuat data penimbangan. Kolom yang
     * nullable pun ikut terkexercise.
     */
    private function seedMedicalNotes(): void
    {
        $kader = User::where('role', 'kader')->orderBy('nik')->first();

        if (! $kader) {
            return;
        }

        $bulanIni = now()->toDateString();
        $bulanLalu = now()->subMonthNoOverflow()->toDateString();

        // Ditulis lewat NIK anak, bukan `Child::all()`, supaya data contohnya
        // deterministik dan tidak ikut bertambah kalau tabel anak berisi data
        // lain.
        $catatan = [
            // Demam + rujukan: kasus yang paling sering membuat Ibu bertanya
            // "anak saya harus dirujuk atau tidak", jadi harus ada di data demo.
            [
                'nik' => '1234567890123456',
                'note_date' => $bulanIni,
                'demam' => true,
                'rewel' => false,
                'diare' => false,
                'catatan' => 'Demam sejak dua hari, suhu 38,5C. Sudah diberi paracetamol.',
                'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_RUJUK,
            ],
            // Catatan saran tanpa keluhan yang dicentang. Kasus ini yang
            // membuat CHECK constraint ikut memeriksa `catatan`, bukan hanya
            // kolom boolean.
            [
                'nik' => '1234567890123459',
                'note_date' => $bulanIni,
                'demam' => false,
                'rewel' => true,
                'diare' => false,
                'catatan' => 'Rewel saat ASI. Ibu diminta lebih sering menyusui.',
                'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_RINGAN,
            ],
            // Bulan lalu, supaya filter `?month=` punya isi untuk diuji.
            [
                'nik' => '1234567890123457',
                'note_date' => $bulanLalu,
                'demam' => false,
                'rewel' => false,
                'diare' => true,
                'catatan' => 'Diare 5 kali sehari. Cascara oral 1 sachet per hari.',
                'tindak_lanjut' => MedicalNote::TINDAK_LANJUT_SEDANG,
            ],
        ];

        foreach ($catatan as $item) {
            $anak = Child::where('nik', $item['nik'])->first();

            if (! $anak) {
                continue;
            }

            MedicalNote::updateOrCreate(
                [
                    'child_id' => $anak->id,
                    'note_date' => $item['note_date'],
                ],
                [
                    'kader_id' => $kader->id,
                    'demam' => $item['demam'],
                    'rewel' => $item['rewel'],
                    'diare' => $item['diare'],
                    'catatan' => $item['catatan'],
                    'tindak_lanjut' => $item['tindak_lanjut'],
                ]
            );
        }
    }
}
