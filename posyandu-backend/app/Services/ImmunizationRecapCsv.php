<?php

namespace App\Services;

use Carbon\CarbonImmutable;

/**
 * Bentuk CSV dari rekap imunisasi bulanan (`GET /kader/immunizations/recap?format=csv`).
 *
 * File ini adalah bentuk kedua dari data yang sama, bukan sumber data baru.
 * [render()] menerima array hasil `ImmunizationRecapService::recapForMonth()`
 * apa adanya - bukan query sendiri, bukan string yang dirakit di controller.
 * Konsekuensinya angka di CSV dijamin identik dengan angka di JSON: kalau ada
 * perhitungan yang berubah, keduanya berubah bersama karena keduanya membaca
 * satu array yang sama. Export yang angkanya berbeda dari layar adalah kegagalan
 * yang paling mahal untuk BIDAN, karena angka yang salah laporan akan dipakai
 * untuk memutuskan kunjungan.
 *
 * Bentuk file dipilih berdasarkan siapa yang memegang file:
 *
 *  - Satu file, bukan dua. Kader mengpegang satu berkas untuk laporan ke BIDAN
 *    sekaligus untuk rencana kunjungan rumah; dua file berarti dia harus ingat
 *    mana yang mana.
 *  - Tiga bagian berurutan: aktivitas suntikan (stok vaksin), kelengkapan
 *    (angka laporan), daftar anak terlambat (yang dikunjungi). Urutannya sama
 *    dengan urutan di layar rekap.
 *  - `CRLF` plus BOM UTF-8. Kader hampir pasti membuka file ini di Excel di
 *    Windows, dan tanpa BOM Excel membaca UTF-8 sebagai ANSI sehingga nama anak
 *    beraksen jadi berantakan.
 *  - Tanggal ditulis ISO (`2026-09`, `2026-09-30`), bukan nama bulan Indonesia.
 *    Daftar nama bulan bahasa Indonesia sengaja tidak diduplikasi ke sini: satu
 *    daftar sudah ada di sisi Flutter (`utils/month_label.dart`), dan menyalin
 *    daftar kedua ke layer lain berarti layar dan berkas bisa menampilkan
 *    "September" dan "Sep" untuk bulan yang sama. Angka ISO tidak pernah salah
 *    dibaca.
 *
 * Nilai sel teks yang diawali `=`, `+`, `-`, atau `@` diberi awalan tanda kutip
 * tunggal. Nama anak datang dari input kader, dan tanpa awakean tersebut Excel
 * akan memperlakukannya sebagai formula saat file dibuka. Sel angka (jumlah,
 * usia, `sisa_bulan`) tidak diberi awakean apa pun - angka `-2` yang berarti
 * "terlambat 2 bulan" bukan formula.
 */
class ImmunizationRecapCsv
{
    /** Pemisah baris RFC 4180; file rapi di Excel Windows kalau pakai `\r\n`. */
    private const EOL = "\r\n";

    /**
     * BOM UTF-8. Tanpa ini Excel di Windows memaksa file ke ANSI, dan nama anak
     * beraksen berubah jadi karakter aneh saat BIDAN membacanya.
     */
    private const BOM = "\xEF\xBB\xBF";

    /**
     * Nama file unduhan, mis. `rekap-imunisasi-2026-09.csv`.
     *
     * @param  string  $bulan  Format `YYYY-MM` dari `filter.month`
     */
    public function filename(string $bulan): string
    {
        // `Y-m` sudah divalidasi `date_format:Y-m` di controller sebelum
        // `render()` dipanggil, jadi penyaringan di sini hanya penjaga, bukan
        // sumber validasi.
        $aman = preg_replace('/[^A-Za-z0-9\-]/', '', $bulan) ?? '';

        return "rekap-imunisasi-{$aman}.csv";
    }

    /**
     * @param  array{
     *     filter: array{month: string, reference_date: string},
     *     activity: array{total_doses: int, total_children: int, by_type: list<array<string, mixed>>},
     *     coverage: array{total_children: int, complete: int, incomplete: int, overdue: int, excluded_archived: int, overdue_children: list<array<string, mixed>>}
     * }  $rekap  Hasil `ImmunizationRecapService::recapForMonth()`, apa adanya
     */
    public function render(array $rekap): string
    {
        $baris = [
            ...$this->kepala($rekap),
            ...$this->bagianAktivitas($rekap['activity']),
            ...$this->bagianKelengkapan($rekap['coverage']),
            ...$this->bagianAnakTerlambat($rekap['coverage']['overdue_children']),
        ];

        return self::BOM.implode(self::EOL, $baris).self::EOL;
    }

    /**
     * Kop laporan: nama Posyandu, bulan, dan tanggal acuan.
     *
     * Baris "Dicetak" adalah satu-satunya isi file yang berubah kalau berkas yang
     * sama diunduh dua kali - angka di dalamnya tetap sama, itu yang dijamin
     * oleh `filter.reference_date`. Cap waktu tetap berguna untuk arsip: BIDAN
     * perlu tahu berkas mana yang terbaru kalau dua berkas ada di satu folder.
     *
     * @param  array{filter: array{month: string, reference_date: string}}  $rekap
     * @return list<string>
     */
    private function kepala(array $rekap): array
    {
        return [
            $this->teks('Rekap Imunisasi - '.config('posyandu.posyandu_name')),
            $this->teks('Bulan: '.$rekap['filter']['month']),
            $this->teks('Dihitung sampai: '.$rekap['filter']['reference_date']),
            $this->teks('Dicetak: '.CarbonImmutable::now()->format('Y-m-d H:i').' WIB'),
            '',
        ];
    }

    /**
     * Aktivitas suntikan per jenis vaksin, untuk menghitung stok.
     *
     * Baris dengan jumlah nol TETAP ditulis. Kader perlu bisa melihat "bulan ini
     * tidak ada yang disuntik untuk vaksin ini", dan kalau baris nol dihapus
     * seperti yang dilakukan di layar, "memang tidak ada suntikan" jadi tidak
     * bisa dibedakan dari "tidak sempat dicatat".
     *
     * @param  array{total_doses: int, total_children: int, by_type: list<array<string, mixed>>}  $activity
     * @return list<string>
     */
    private function bagianAktivitas(array $activity): array
    {
        $baris = [
            'AKTIVITAS SUNTIKAN',
            $this->row(['Kode', 'Dosis', 'Nama Vaksin', 'Jumlah Disuntik']),
        ];

        foreach ($activity['by_type'] as $tipe) {
            $baris[] = $this->row([
                $this->teks((string) $tipe['code']),
                $this->angka((int) $tipe['dose_number']),
                $this->teks((string) $tipe['label']),
                $this->angka((int) $tipe['count']),
            ]);
        }

        $baris[] = $this->row([
            $this->teks('TOTAL'),
            '',
            '',
            $this->angka((int) $activity['total_doses']),
        ]);

        $baris[] = '';
        $baris[] = $this->row([
            $this->teks('Anak yang disuntik bulan ini'),
            $this->angka((int) $activity['total_children']),
        ]);

        $baris[] = '';

        return $baris;
    }

    /**
     * Kelengkapan tiap anak di akhir bulan, untuk laporan ke BIDAN.
     *
     * `excluded_archived` ditulis sebagai baris tersendiri, bukan disembunyikan.
     * Kalau angkanya tidak muncul, total anak di file terlihat lebih kecil dari
     * kenyataan tanpa ada penjelasan apa pun.
     *
     * @param  array{total_children: int, complete: int, incomplete: int, overdue: int, excluded_archived: int, overdue_children: list<array<string, mixed>>}  $coverage
     * @return list<string>
     */
    private function bagianKelengkapan(array $coverage): array
    {
        return [
            'KELENGKAPAAN IMUNISASI (pada akhir bulan)',
            $this->row(['Keterangan', 'Jumlah Anak']),
            $this->row([$this->teks('Total anak'), $this->angka((int) $coverage['total_children'])]),
            $this->row([$this->teks('Imunisasi lengkap'), $this->angka((int) $coverage['complete'])]),
            $this->row([$this->teks('Imunisasi belum lengkap'), $this->angka((int) $coverage['incomplete'])]),
            $this->row([$this->teks('Ada dosis terlambat'), $this->angka((int) $coverage['overdue'])]),
            $this->row([$this->teks('Tidak dihitung (arsip / pindah)'), $this->angka((int) $coverage['excluded_archived'])]),
            '',
        ];
    }

    /**
     * Daftar anak yang punya dosis terlambat, dengan urutan dari server.
     *
     * Satu baris per ANAK, bukan satu baris per dosis. Kader sedang memilih siapa
     * yang dikunjungi berikutnya, dan satu anak dengan tiga dosis telat tetap
     * hanya butuh satu kunjungan. Nama dosis digabung ke satu sel dengan
     * pemisah `; ` supaya daftar nama anak masih bisa disalin ke daftar
     * kunjungan.
     *
     * Kolom "Terlambat (bulan)" diambil dari `sisa_bulan` paling negatif milik
     * anak itu, angka yang sama dengan dasar urutan di server. Dosis tanpa usia
     * target punya `sisa_bulan` null dan tidak ikut dihitung, persis seperti di
     * `ImmunizationRecapService::oldestSisaBulan()`.
     *
     * @param  list<array<string, mixed>>  $anakTerlambat
     * @return list<string>
     */
    private function bagianAnakTerlambat(array $anakTerlambat): array
    {
        $baris = [
            'DAFTAR ANAK TERLAMBAT',
            $this->row([
                'No',
                'Nama',
                'Tanggal Lahir',
                'Usia (bulan)',
                'Jumlah Dosis Terlambat',
                'Dosis Terlambat',
                'Terlambat (bulan)',
            ]),
        ];

        if ($anakTerlambat === []) {
            // Baris "(tidak ada)" menjaga bentuk tabel tetap seragam, sehingga
            // pembaca file ini tidak salah mengira tabelnya rusak.
            $baris[] = $this->row([
                '',
                $this->teks('(tidak ada anak dengan dosis terlambat)'),
                '',
                '',
                '',
                '',
                '',
            ]);

            return [...$baris, ''];
        }

        foreach ($anakTerlambat as $urutan => $anak) {
            $baris[] = $this->row([
                $this->angka($urutan + 1),
                $this->teks((string) $anak['name']),
                $this->teks((string) $anak['date_of_birth']),
                $this->angka((int) $anak['age_in_months']),
                $this->angka(count($anak['overdue_doses'])),
                $this->teks($this->gabungDosis($anak['overdue_doses'])),
                $this->angka($this->palingLamaTelat($anak['overdue_doses'])),
            ]);
        }

        $baris[] = '';

        return $baris;
    }

    /**
     * Nama seluruh dosis telat milik satu anak, digabung dengan `; `.
     *
     * Urutannya mengikuti `overdue_doses` apa adanya, yang urutannya sudah dari
     * server - supaya file dan layar menampilkan urutan dosis yang sama.
     *
     * @param  list<array<string, mixed>>  $dosis
     */
    private function gabungDosis(array $dosis): string
    {
        return implode('; ', array_map(
            fn (array $d): string => (string) $d['label'],
            $dosis,
        ));
    }

    /**
     * `sisa_bulan` paling negatif milik satu anak.
     *
     * Null berarti dosis itu tidak punya usia target sehingga tidak bisa
     * dihitung. Kalau semua null, kolom dikosongkan - bukan diisi `0`, yang akan
     * terbaca oleh kader sebagai "tepat waktu".
     *
     * @param  list<array<string, mixed>>  $dosis
     */
    private function palingLamaTelat(array $dosis): ?int
    {
        $sisa = array_filter(
            array_map(fn (array $d): ?int => $d['sisa_bulan'], $dosis),
            fn (?int $n): bool => $n !== null,
        );

        return $sisa === [] ? null : min($sisa);
    }

    // -----------------------------------------------------------------
    // Helper sel CSV
    // -----------------------------------------------------------------

    /**
     * Satu baris CSV, selnya sudah di-escape.
     *
     * @param  list<string>  $sel
     */
    private function row(array $sel): string
    {
        return implode(',', $sel);
    }

    /**
     * Sel teks bebas, dengan penjaga formula Excel.
     *
     * Tiga lapis berurutan: baris baru diratakan lebih dulu, lalu awakean
     * anti-formula, lalu pengutipan RFC 4180. Urutannya penting - kalau
     * pengutipan dilakukan lebih dulu, awakean tanda kutip ikut ter-escape dan
     * hasilnya berubah.
     *
     * Baris baru diratakan supaya satu baris di file selalu satu record.
     * `children.name` hanya divalidasi sebagai `string|max:255`, jadi nama anak
     * secara teknis boleh memuat newline, dan satu sel ber-newline akan membuat
     * file ini gagal dibaca oleh apa pun yang memecah per baris - termasuk saat
     * kader menempelkan isinya ke WhatsApp atau email.
     */
    private function teks(string $nilai): string
    {
        return $this->quote($this->antiFormula($this->satuBaris($nilai)));
    }

    /** Ganti semua jenis baris baru dengan satu spasi. */
    private function satuBaris(string $nilai): string
    {
        return preg_replace('/\R/u', ' ', $nilai) ?? $nilai;
    }

    /**
     * Sel angka atau kosong.
     *
     * Tidak mendapat awakean apa pun: kolom ini hanya berisi hasil perhitungan
     * server, tidak pernah input pengguna.
     */
    private function angka(?int $nilai): string
    {
        return $nilai === null ? '' : (string) $nilai;
    }

    /**
     * Cegah Excel mengeksekusi sel sebagai formula.
     *
     * Nilai yang diawali `=`, `+`, `-`, atau `@` dianggap perintah saat file
     * dibuka. Nama anak adalah input kader, jadi tanpa penjaga ini nama anak
     * bisa menyisipkan formula ke komputer BIDAN hanya karena berkasnya dibuka.
     * Spasi di depan ikut diperhitungkan karena Excel membuang whitespace dulu
     * sebelum memindai karakter pembuka formula.
     */
    private function antiFormula(string $nilai): string
    {
        return preg_match('/^\s*[=+\-@]/', $nilai) === 1 ? "'".$nilai : $nilai;
    }

    /**
     * Pengutipan RFC 4180: bungkus dengan tanda kutip kalau sel memuat koma,
     * tanda kutip, newline, atau spasi di tepi; setiap tanda kutip di dalam sel
     * jadi dua tanda kutip.
     *
     * Sel kosong sengaja tidak jadi `""` - `,,` sudah berarti kosong di CSV,
     * sedangkan `""` akan terbaca sebagai karakter kutip oleh pembaca sederhana.
     * Pemeriksaan newline sengaja tetap ada walau `teks()` sudah meratakan
     * baris baru: `quote()` boleh dipakai sel apa pun, jadi tidak boleh
     * bergantung pada pemanggil tertentu.
     */
    private function quote(string $nilai): string
    {
        if ($nilai === '') {
            return '';
        }

        $perluQuote = str_contains($nilai, ',')
            || str_contains($nilai, '"')
            || str_contains($nilai, "\n")
            || str_contains($nilai, "\r")
            || trim($nilai) !== $nilai;

        if (! $perluQuote) {
            return $nilai;
        }

        return '"'.str_replace('"', '""', $nilai).'"';
    }
}
