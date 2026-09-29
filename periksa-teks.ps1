<#
  =====================================================================
  PEMERIKSA TEKS - memblokir karakter asing & ketikan tergesaet
  =====================================================================
  Dipakai karena berulang kali ada karakter Mandarin atau potongan kata
  asing yang ikut terketik ke komentar dan dokumentasi. Keduanya sulit
  dikenali mata saat review, tapi merusak isi dokumen.

  Yang DIPERIKSA:
    1. Aksara non-Latin (CJK, kana, hangul) dan karakter pengganti U+FFFD.
       Tidak pernah dipakai di dokumen projek ini.
    2. Potongan ketikan tergesaet - kata yang TIDAK MUNGKIN muncul di
       kalimat Indonesia dan hanya muncul kalau ada salah ketik.

  Yang SENGAJA TIDAK diperiksa:
    Kata teknis bahasa Inggris yang sah dipakai di dokumen ini, seperti
    `hardcode`, `fallback`, `payload`, atau `endpoint`. Memeriksa kata
    Inggris secara umum menghasilkan banyak false positive dan membuat
    pemeriksa ini diabaikan.

  Cara pakai:
    powershell -ExecutionPolicy Bypass -File .\periksa-teks.ps1
    powershell -ExecutionPolicy Bypass -File .\periksa-teks.ps1 -Path .\posyandu-backend\app
  =====================================================================
#>

param(
    [string]$Path = '.'
)

$ErrorActionPreference = 'Stop'

# Folder yang isinya bukan tulisan tangan kita: dependency, hasil build,
# dan dokumen skill bawaan yang memang berbahasa Inggris.
#
# `ephemeral` masuk daftar pada 29 September 2026: `posyandu_mobile/*/
# flutter/ephemeral/.plugin_symlinks/` berisi salinan test dari paket
# `jni` yang sengaja memakai karakter non-Latin, dan folder itu dibuat
# ulang oleh `flutter pub get`, bukan oleh kita.
$lewatiDirektori = '\\(\.git|vendor|node_modules|\.dart_tool|build|storage|bootstrap|\.agents|\.claude|ios|android|\.vscode|\.idea|ephemeral)\\';

# Aksara non-Latin yang tidak pernah dipakai di dokumen projek ini.
#
# CJK/kana/hangul catches the most common case. Cyrillic, Greek, dan
# Arab/Heber ditambahkan karena pada 29 September 2026 enam kata asing
# sempat lolos ke dokumen (Cyrillic "тест", Arab di dalam kalimat Indonesia,
# kata Prancis "obtenir"). Semuanya lolos dari pola lama karena hanya CJK
# dan U+FFFD yang diperiksa, padahal tidak satu pun dari aksara itu punya
# alasan muncul di dokumentasi projek ini.
$polaAksaraAsing = '[\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af\ufffd\u0370-\u03ff\u0400-\u04ff\u0590-\u05ff\u0600-\u06ff\u0e00-\u0e7f]'

# Hanya potongan yang mustahil terjadi di teks Indonesia yang benar.
$ketikanTergesaet = @(
    'iftedatan', 'terasauct', 'yangdesired', 'sulitatonin', 'kVrastinya',
    'Eq subset', 'disrespect', 'dijaga mata'
)

$file = Get-ChildItem -Path $Path -Recurse -File -Include '*.php', '*.ps1', '*.md', '*.dart', '*.xml', '*.json', '*.yml', '*.yaml' -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FullName -notmatch $lewatiDirektori -and
        $_.Name -ne 'periksa-teks.ps1'
    }

$temuan = @()

foreach ($f in $file) {
    $baris = Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue

    for ($i = 0; $i -lt $baris.Count; $i++) {
        $teks = $baris[$i]

        if ($teks -match $polaAksaraAsing) {
            $temuan += [pscustomobject]@{
                Tipe   = 'aksara-asing'
                Lokasi = "$($f.FullName):$($i + 1)"
                Isi    = $teks.Trim()
            }
        }

        foreach ($potongan in $ketikanTergesaet) {
            if ($teks -match [regex]::Escape($potongan)) {
                $temuan += [pscustomobject]@{
                    Tipe   = "ketikan-tergesaet ($potongan)"
                    Lokasi = "$($f.FullName):$($i + 1)"
                    Isi    = $teks.Trim()
                }
            }
        }
    }
}

if ($temuan.Count -eq 0) {
    Write-Host "BERSIH - $($file.Count) file diperiksa" -ForegroundColor Green
    exit 0
}

Write-Host "DITEMUKAN $($temuan.Count) MASALAH:" -ForegroundColor Red
foreach ($t in $temuan) {
    Write-Host "  [$($t.Tipe)] $($t.Lokasi)" -ForegroundColor Red
    Write-Host "      $($t.Isi)" -ForegroundColor DarkGray
}
exit 1
