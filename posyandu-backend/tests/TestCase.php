<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use RuntimeException;

/**
 * Basis untuk semua test di project ini.
 *
 * Test berjalan di PostgreSQL, bukan SQLite, karena aplikasi memakai partial
 * unique index, trigger plpgsql untuk z-score WFA, dan CHECK constraint yang
 * tidak ada di SQLite. Detail koneksi ada di `.env.testing`.
 */
abstract class TestCase extends BaseTestCase
{
    /**
     * Database yang boleh dipakai test.
     *
     * Dipakai sebagai pengaman, bukan sekadar dokumentasi: `RefreshDatabase`
     * menghapus dan membuat ulang seluruh tabel, jadi kalau `.env.testing` salah
     * diisi dan menunjuk database dev, data Posyandu hilang tanpa bisa
     * dibatalkan. Pemeriksaan ini membuat kegagalan itu berhenti di awal dengan
     * pesan yang jelas.
     */
    protected const DATABASE_TEST = 'posyandu_test';

    /**
     * Nama database yang tidak boleh pernah disentuh test, apa pun isi
     * `.env.testing`.
     *
     * Daftar kedua adalah jaring pengaman tambahan: kalau nama database test
     * diganti karena konvensi tim, `posyandu_db` tetap tidak bisa tersentuh.
     */
    protected const DATABASE_TERLARANG = [
        'posyandu_db',
        'postgres',
        'template0',
        'template1',
    ];

    /**
     * Urutan `setUp()` di `Illuminate\Foundation\Testing\TestCase`:
     *
     *   1. `refreshApplication()` -> `createApplication()`
     *   2. `setUpTraits()` -> `RefreshDatabase` mulai migrate
     *
     * Jadi pemeriksaan di dalam `createApplication()` - setelah
     * `parent::createApplication()`, sebelum `return` - berjalan tepat di
     * antara keduanya: environment sudah termuat, tapi belum ada tabel yang
     * disentuh. Di situ `config()` sudah bisa dipakai.
     */
    public function createApplication()
    {
        $app = parent::createApplication();

        $this->guardDatabaseTest();

        return $app;
    }

    /**
     * Gagal cepat kalau test diarahkan ke database yang salah.
     *
     * Dicek sebelum `RefreshDatabase` sempat menjalankan `migrate:fresh`.
     */
    private function guardDatabaseTest(): void
    {
        $koneksi = config('database.default');
        $nama = (string) config("database.connections.{$koneksi}.database");

        if ($koneksi !== 'pgsql') {
            throw new RuntimeException(
                "Test harus jalan di PostgreSQL, tapi connection default adalah '{$koneksi}'. "
                .'Aplikasi ini memakai partial unique index dan trigger plpgsql yang tidak '
                .'ada di SQLite, jadi test di SQLite akan hijau tanpa menguji bagian yang '
                .'paling rawan salah.'
            );
        }

        if ($nama === '') {
            throw new RuntimeException(
                'Database test belum terkonfigurasi. Salin .env.testing.example jadi '
                .'.env.testing, lalu isi DB_DATABASE dengan '.self::DATABASE_TEST
                .' (database itu harus dibuat lebih dulu di PostgreSQL).'
            );
        }

        if (in_array($nama, self::DATABASE_TERLARANG, true)) {
            throw new RuntimeException(
                "Test tidak boleh memakai database '{$nama}'. "
                .'Buat database terpisah dan arahkan .env.testing ke sana: '
                .'RefreshDatabase akan menghapus seluruh tabel di database yang dipilih.'
            );
        }

        if ($nama !== self::DATABASE_TEST) {
            throw new RuntimeException(
                "Test harus memakai database '".self::DATABASE_TEST
                ."', tapi .env.testing menunjuk '{$nama}'."
            );
        }
    }
}
