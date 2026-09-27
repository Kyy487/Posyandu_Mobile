<#
  =====================================================================
  SKRIP UJI API - SMART POSYANDU
  =====================================================================
  Cara pakai:
    1. Jalankan server dulu (terminal terpisah):
         cd C:\laragon\www\posyandu\posyandu-backend
         php artisan serve
    2. Jalankan skrip ini:
         powershell -ExecutionPolicy Bypass -File .\uji-api.ps1

  Skrip ini membuat user uji sendiri, menguji semua alur API, lalu
  MENGHAPUS semua data ujinya di akhir. Data asli Anda tidak tersentuh.

  Password semua user uji: "Rahasia123"
  =====================================================================
#>

$ErrorActionPreference = 'Continue'
$base    = 'http://127.0.0.1:8000/api'
$backend = 'C:\laragon\www\posyandu\posyandu-backend'
$php     = 'C:\laragon\bin\php\php-8.4.25-Win32-vs17-x64\php.exe'

$script:pass = 0
$script:fail = 0
$script:throttled = $false

# ---------------------------------------------------------------------
# Kode pendaftaran kader dibaca dari .env backend.
# Akun Kader TIDAK LAGI bisa dibuat dengan mengirim role='kader' saja.
# ---------------------------------------------------------------------
$envFile    = Join-Path $backend '.env'
$kaderCode  = $null
if (Test-Path $envFile) {
    $baris = Select-String -Path $envFile -Pattern '^\s*KADER_REGISTRATION_CODE\s*=\s*(.*)$' |
             Select-Object -First 1
    if ($baris) { $kaderCode = $baris.Matches[0].Groups[1].Value.Trim().Trim('"') }
}

function Group($name) {
    Write-Host ''
    Write-Host "--- $name ---" -ForegroundColor Cyan
}

function Check($label, $expected, $actual) {
    if ($expected -eq $actual) {
        $script:pass++
        Write-Host "  [OK]    $label" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "  [GAGAL] $label" -ForegroundColor Red
        Write-Host "          hopes : $expected" -ForegroundColor DarkGray
        Write-Host "          aktual: $actual"  -ForegroundColor DarkGray
    }
}

function Note($text) { Write-Host "          $text" -ForegroundColor DarkGray }

# Permintaan yang TIDAK melempar exception meski status 4xx/5xx
function Req($method, $uri, $token, $body) {
    $headers = @{ Accept = 'application/json' }
    if ($token) { $headers.Authorization = "Bearer $token" }
    $p = @{ Uri = $uri; Method = $method; Headers = $headers; UseBasicParsing = $true; TimeoutSec = 30 }
    if ($null -ne $body) { $p.Body = ($body | ConvertTo-Json -Depth 5); $p.ContentType = 'application/json' }
    try {
        $r = Invoke-WebRequest @p -ErrorAction Stop
        $code = $r.StatusCode; $raw = $r.Content
    } catch {
        if ($_.Exception.Response) {
            $code = $_.Exception.Response.StatusCode.value__
            $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
            $raw = $sr.ReadToEnd(); $sr.Close()
        } else { $code = 0; $raw = $_.Exception.Message }
    }
    $o = $null
    if ($raw) { try { $o = $raw | ConvertFrom-Json } catch { } }
    if ($code -eq 429) { $script:throttled = $true }
    return @{ Status = $code; Body = $o; Raw = $raw }
}

function Reg($nik, $name, $kode) {
    $body = @{ nik = $nik; name = $name; password = 'Rahasia123'; password_confirmation = 'Rahasia123' }
    if ($kode) { $body.role = 'kader'; $body.kader_code = $kode }
    $r = Req 'POST' "$base/register" $null $body
    if ($r.Status -ne 201) { throw "Register gagal ($($r.Status)): $($r.Raw)" }
    return @{ Token = $r.Body.data.token; Id = $r.Body.data.user.id; Role = $r.Body.data.user.role }
}

function Contains($arr, $id) {
    foreach ($d in $arr) { if ($d.id -eq $id) { return $true } }
    return $false
}

function FindById($arr, $id) {
    foreach ($d in $arr) { if ($d.id -eq $id) { return $d } }
    return $null
}

# =====================================================================
Group "0. Koneksi"
$cek = Req 'POST' "$base/login" $null @{}
if ($cek.Status -ne 422) {
    Write-Host "  Server tidak merespons di $base" -ForegroundColor Red
    Write-Host "  Jalankan dulu:  cd $backend ;  php artisan serve" -ForegroundColor Yellow
    exit 1
}
Check "server hidup" 422 $cek.Status
# =====================================================================
Group "1. Autentikasi"
$cek = Req 'POST' "$base/login" $null @{ nik = '123'; password = 'x' }
Check "login NIK ngawur -> 422" 422 $cek.Status
Check "  success = false" $false $cek.Body.success

$cek = Req 'POST' "$base/login" $null @{ nik = '1111111111111111'; password = 'salah' }
Check "login password salah -> 401" 401 $cek.Status
Check "  pesan" 'Kredensial yang diberikan tidak cocok dengan data kami.' $cek.Body.message

$cek = Req 'GET' "$base/children" $null $null
Check "tanpa token -> 401" 401 $cek.Status
Check "  body 401 sudah envelope" $false $cek.Body.success
Note "sebelumnya body 401 = {\"message\":\"Unauthenticated.\"} - sekarang sudah {success,message,errors}"

$cek = Req 'POST' "$base/register" $null @{ nik = '1111111111111111'; name = 'X'; password = '12345678'; password_confirmation = '12345678'; role = 'admin' }
Check "register role tak dikenal -> 422" 422 $cek.Status

$cek = Req 'POST' "$base/register" $null @{ nik = '111'; name = 'X'; password = '12345678'; password_confirmation = '12345678' }
Check "register NIK < 16 digit -> 422" 422 $cek.Status

$cek = Req 'POST' "$base/register" $null @{ nik = '1111111111111112'; name = 'X'; password = '12345678' }
Check "register tanpa konfirmasi password -> 422" 422 $cek.Status

# =====================================================================
Group "1b. Role ditentukan server (tidak bisa dipilih sendiri)"
$cek = Req 'POST' "$base/register" $null @{ nik = '2222222222222222'; name = 'Self Kader'; password = 'Rahasia123'; password_confirmation = 'Rahasia123'; role = 'kader' }
Check "daftar kader tanpa kode -> 403" 403 $cek.Status
Check "  success = false" $false $cek.Body.success
Note "INI YANG SEBELUMNYA BOCOR: role=kader tanpa kode langsung jadi 201"

$cek = Req 'POST' "$base/register" $null @{ nik = '2222222222222223'; name = 'Self Kader'; password = 'Rahasia123'; password_confirmation = 'Rahasia123'; role = 'kader'; kader_code = 'KODE-SALAH' }
Check "daftar kader kode salah -> 403" 403 $cek.Status

# =====================================================================
Group "2. Menyiapkan user uji"
if (-not $kaderCode) {
    Write-Host "  KADER_REGISTRATION_CODE kosong di .env - skrip berhenti." -ForegroundColor Red
    Write-Host "  Isi dulu di $envFile lalu ulangi." -ForegroundColor Yellow
    exit 1
}
Note "kode kader terbaca dari .env"

$s = Get-Random -Minimum 100000 -Maximum 999999
$nIbuA   = "95$s" + "00000001"
$nIbuB   = "95$s" + "00000002"
$nKader  = "96$s" + "00000001"
$nKader2 = "96$s" + "00000002"

$ibuA   = Reg $nIbuA   "Uji Ibu A $s"   $null
$ibuB   = Reg $nIbuB   "Uji Ibu B $s"   $null
$kader  = Reg $nKader  "Uji Kader $s"  $kaderCode
$kader2 = Reg $nKader2 "Uji Kader2 $s" $kaderCode
$tA = $ibuA.Token; $tB = $ibuB.Token; $tK = $kader.Token; $tK2 = $kader2.Token
Check "4 user uji dibuat" 4 4
Check "tanpa kode -> role ibu" 'ibu' $ibuA.Role
Check "dengan kode -> role kader" 'kader' $kader.Role

$cek = Req 'GET' "$base/user" $tK $null
Check "GET /user -> 200" 200 $cek.Status
Check "  role benar" 'kader' $cek.Body.data.role

# =====================================================================
Group "3. Menambah anak"
$r = Req 'POST' "$base/children" $tA @{ name = "Anak Ibu A $s"; date_of_birth = '2024-01-15'; gender = 'L' }
Check "Ibu tanpa sebut ibu -> 201" 201 $r.Status
Check "  otomatis milik Ibu A" $ibuA.Id $r.Body.data.user_id
Check "  nama ibu ikut terkirim" "Uji Ibu A $s" $r.Body.data.mother.name
Check "  NIK ibu ikut terkirim"   $nIbuA   $r.Body.data.mother.nik
$idA = $r.Body.data.id

$r = Req 'POST' "$base/children" $tA @{ name = "Anak Kedua A $s"; date_of_birth = '2024-02-20'; gender = 'P' }
Check "Ibu tambah anak kedua -> 201" 201 $r.Status
$idA2 = $r.Body.data.id

$r = Req 'POST' "$base/children" $tB @{ name = "Anak Ibu B $s"; date_of_birth = '2024-03-25'; gender = 'P' }
Check "Ibu B tambah anak -> 201" 201 $r.Status
$idB = $r.Body.data.id

$r = Req 'POST' "$base/children" $tA @{ name = "Anak Gagal Assign $s"; date_of_birth = '2024-01-01'; gender = 'P'; user_id = $ibuB.Id }
Check "Ibu lampirkan anak ke Ibu B -> 201 (diabaikan)" 201 $r.Status
Check "  tetap milik Ibu A" $ibuA.Id $r.Body.data.user_id

$r = Req 'POST' "$base/kader/children" $tK @{ name = "Anak Kader 1 $s"; date_of_birth = '2024-04-10'; gender = 'L'; birth_weight = 3.4; birth_height = 51; ibu_nik = $nIbuA }
Check "Kader sebut ibu via ibu_nik -> 201" 201 $r.Status
Check "  user_id benar" $ibuA.Id $r.Body.data.user_id
$idK1 = $r.Body.data.id

$r = Req 'POST' "$base/kader/children" $tK @{ name = "Anak Kader 2 $s"; date_of_birth = '2024-05-01'; gender = 'P'; user_id = $ibuB.Id }
Check "Kader sebut ibu via user_id -> 201" 201 $r.Status
Check "  user_id benar" $ibuB.Id $r.Body.data.user_id

$r = Req 'POST' "$base/kader/children" $tK @{ name = "Anak Kader 3 $s"; date_of_birth = '2024-06-01'; gender = 'P'; user_id = $ibuA.Id; ibu_nik = $nIbuA }
Check "Kader sebut keduanya (cocok) -> 201" 201 $r.Status

# =====================================================================
Group "4. Menambah anak - penolakan"
$r = Req 'POST' "$base/kader/children" $tK @{ name = "X1 $s"; date_of_birth = '2024-01-01'; gender = 'P' }
Check "Kader tidak sebut ibu -> 422" 422 $r.Status
Check "  ada error user_id" $true ($null -ne $r.Body.errors.user_id)
Check "  ada error ibu_nik" $true ($null -ne $r.Body.errors.ibu_nik)

$r = Req 'POST' "$base/kader/children" $tK @{ name = "X2 $s"; date_of_birth = '2024-01-01'; gender = 'P'; ibu_nik = '9999999999999999' }
Check "ibu_nik tidak terdaftar -> 404" 404 $r.Status
Check "  pesan" 'NIK Ibu tidak ditemukan di sistem. Pastikan akun Ibu sudah terdaftar.' $r.Body.message

$r = Req 'POST' "$base/kader/children" $tK @{ name = "X3 $s"; date_of_birth = '2024-01-01'; gender = 'P'; user_id = $ibuA.Id; ibu_nik = $nIbuB }
Check "user_id & ibu_nik tidak sinkron -> 422" 422 $r.Status
Check "  pesan" 'user_id dan ibu_nik harus menunjuk Ibu yang sama.' $r.Body.message

$r = Req 'POST' "$base/kader/children" $tK @{ name = "X4 $s"; date_of_birth = '2024-01-01'; gender = 'P'; user_id = $kader2.Id }
Check "tuju user role kader -> 422" 422 $r.Status
Check "  pesan" 'Data anak hanya dapat ditambahkan pada akun dengan role ibu.' $r.Body.message

$r = Req 'POST' "$base/kader/children" $tK @{ name = "X5 $s"; date_of_birth = 'bukan-tanggal'; gender = 'P'; ibu_nik = $nIbuA }
Check "tanggal tidak valid -> 422" 422 $r.Status
Check "  success = false" $false $r.Body.success

$r = Req 'POST' "$base/kader/children" $tK @{ name = "X6 $s"; date_of_birth = '2024-01-01'; gender = 'X'; ibu_nik = $nIbuA }
Check "gender tidak valid -> 422" 422 $r.Status

# =====================================================================
Group "4b. Format tanggal wajib ISO (Y-m-d)"
# Regresi: rule `date` hanya mengandalkan strtotime(), jadi "26-09-2026" LOLOS
# validasi lalu ditolak PostgreSQL saat insert -> 500 + stack trace di log.
# Karena itu store/update kini pakai date_format:Y-m-d.
$badTanggal = @(
  @{ nilai = '26-09-2026'; label = 'DD-MM-YYYY' },
  @{ nilai = '2026-9-5';     label = 'bulan/hari tanpa nol' },
  @{ nilai = '2026/09/26';   label = 'garis miring' },
  @{ nilai = '26 Sep 2026';  label = 'nama bulan' }
)
foreach ($bt in $badTanggal) {
  $r = Req 'POST' "$base/children" $tA @{ name = "Format $s $($bt.label)"; date_of_birth = $bt.nilai; gender = 'P' }
  Check "tanggal $($bt.label) -> 422" 422 $r.Status
  Check "  bukan 500 (tidak sampai ke PostgreSQL)" $true ($r.Status -ne 500)
  Check "  ada pesan di errors.date_of_birth" $true ($null -ne $r.Body.errors.date_of_birth)
}

$r = Req 'POST' "$base/children" $tA @{ name = "Tanggal Lalu $s"; date_of_birth = '2026-09-26'; gender = 'P' }
Check "tanggal ISO YYYY-MM-DD -> 201" 201 $r.Status
$idTanggalOk = $r.Body.data.id

$r = Req 'POST' "$base/children" $tA @{ name = "Tanggal Depan $s"; date_of_birth = '2099-01-01'; gender = 'P' }
Check "tanggal masa depan -> 422" 422 $r.Status

$r = Req 'PATCH' "$base/children/$idTanggalOk" $tA @{ date_of_birth = '26-09-2026' }
Check "PATCH tanggal DD-MM-YYYY -> 422" 422 $r.Status
Check "  bukan 500" $true ($r.Status -ne 500)

$r = Req 'POST' "$base/kader/measurements" $tK @{ child_id = $idTanggalOk; measurement_date = '26-09-2026'; weight_kg = 7.1; height_cm = 75 }
Check "penimbangan tanggal DD-MM-YYYY -> 422" 422 $r.Status
Check "  bukan 500" $true ($r.Status -ne 500)

# =====================================================================
Group "5. Daftar & detail anak"
$cekMilikA = @($idA, $idA2, $idK1)
$r = Req 'GET' "$base/children" $tA $null
Check "Ibu A daftar anak -> 200" 200 $r.Status
Check "  anak milik Ibu A ada semua (3)" $true (Contains $r.Body.data $idA)
Check "  anak kedua ada" $true (Contains $r.Body.data $idA2)
Check "  anak dari kader ada" $true (Contains $r.Body.data $idK1)
Check "  anak Ibu B tidak bocor" $false (Contains $r.Body.data $idB)
$semuaAdaIbu = $true
foreach ($d in $r.Body.data) { if ($null -eq $d.mother.name) { $semuaAdaIbu = $false } }
Check "  semua anak punya nama ibu" $true $semuaAdaIbu

# Kontrak field ringkasan gizi yang dipakai Dashboard Ibu.
$adaKolomRingkas = $true
$tanpaRelasi = $true
foreach ($d in $r.Body.data) {
  foreach ($k in 'last_measurement_date', 'latest_z_score', 'nutritional_status') {
    if (-not $d.PSObject.Properties.Name.Contains($k)) { $adaKolomRingkas = $false }
  }
  # Objek measurement penuh tidak boleh ikut terkirim - payload jadi membengkak.
  if ($d.PSObject.Properties.Name.Contains('latest_measurement')) { $tanpaRelasi = $false }
}
Check "  semua anak punya 3 field ringkasan gizi" $true $adaKolomRingkas
Check "  relasi latest_measurement tidak bocor" $true $tanpaRelasi
$tk1 = FindById $r.Body.data $idK1
Check "  anak tanpa penimbangan: tanggal null" $true ($null -eq $tk1.last_measurement_date)
Check "  anak tanpa penimbangan: z-score null" $true ($null -eq $tk1.latest_z_score)
Check "  anak tanpa penimbangan: status null" $true ($null -eq $tk1.nutritional_status)

$r = Req 'GET' "$base/children" $tK $null
Check "Kader daftar anak -> 200" 200 $r.Status
Check "  melihat anak Ibu B juga" $true (Contains $r.Body.data $idB)

$r = Req 'GET' "$base/children/$idA" $tA $null
Check "Ibu A buka anak sendiri -> 200" 200 $r.Status
Check "  nama ibu tampil" "Uji Ibu A $s" $r.Body.data.mother.name

$r = Req 'GET' "$base/children/$idB" $tK $null
Check "Kader buka anak siapa pun -> 200" 200 $r.Status

$r = Req 'GET' "$base/children/$idB" $tA $null
Check "Ibu A buka anak Ibu B -> 403" 403 $r.Status

$r = Req 'GET' "$base/children/bukan-uuid" $tK $null
Check "id bukan UUID -> 404 (bukan 500)" 404 $r.Status

# =====================================================================
Group "6. Mengubah anak"
$r = Req 'PATCH' "$base/children/$idA" $tA @{ name = "Anak A Direvisi $s" }
Check "PATCH nama -> 200" 200 $r.Status
Check "  nama baru" "Anak A Direvisi $s" $r.Body.data.name
Check "  tanggal lahir tidak berubah" '2024-01-15' $r.Body.data.date_of_birth
Check "  nama ibu tetap ikut" "Uji Ibu A $s" $r.Body.data.mother.name

$r = Req 'PUT' "$base/children/$idA" $tA @{ gender = 'P' }
Check "PUT gender -> 200" 200 $r.Status
Check "  gender baru" 'P' $r.Body.data.gender
Check "  nama hasil PATCH tidak hilang" "Anak A Direvisi $s" $r.Body.data.name

# Çocokkan authorization: $idB adalah anak Ibu B, jadi Ibu A HARUS ditolak
$r = Req 'PATCH' "$base/children/$idB" $tA @{ name = "Dibajak" }
Check "Ibu A ubah anak Ibu B -> 403" 403 $r.Status
Check "  pesan" 'Akses ditolak. Anda tidak berhak mengubah data anak ini.' $r.Body.message
$r = Req 'GET' "$base/children/$idB" $tB $null
Check "  data Ibu B tidak berubah" "Anak Ibu B $s" $r.Body.data.name

$r = Req 'PATCH' "$base/children/$idA" $tA @{}
Check "body kosong -> 422" 422 $r.Status
Check "  pesan" 'Tidak ada data yang diperbarui.' $r.Body.message

$r = Req 'PATCH' "$base/children/$idA" $tA @{ gender = 'X' }
Check "gender salah -> 422" 422 $r.Status

$r = Req 'PATCH' "$base/children/$idA" $tA @{ date_of_birth = 'xx' }
Check "tanggal salah -> 422" 422 $r.Status

$r = Req 'PATCH' "$base/children/$idK1" $tK @{ name = "Anak Kader 1 Direvisi $s" }
Check "Kader ubah anak siapa pun -> 200" 200 $r.Status

$r = Req 'PATCH' "$base/children/$idK1" $tK @{ name = "Pindah Ibu $s"; ibu_nik = $nIbuB }
Check "Kader pindahkan ibu anak -> 200" 200 $r.Status
Check "  jadi milik Ibu B" $ibuB.Id $r.Body.data.user_id
Check "  nama ibu baru" "Uji Ibu B $s" $r.Body.data.mother.name

$r = Req 'PATCH' "$base/children/$idK1" $tK @{ ibu_nik = '7777777777777777' }
Check "pindah ke ibu tidak terdaftar -> 404" 404 $r.Status

$r = Req 'PATCH' "$base/children/$idK1" $tK @{ user_id = $ibuA.Id; ibu_nik = $nIbuB }
Check "user_id & ibu_nik beda -> 422" 422 $r.Status

$r = Req 'PATCH' "$base/children/$idB" $tB @{ name = "Coba Pindah $s"; ibu_nik = $nIbuA }
Check "Ibu coba pindahkan anaknya -> 200 (diabaikan)" 200 $r.Status
Check "  tetap milik Ibu B" $ibuB.Id $r.Body.data.user_id

# =====================================================================
Group "7. Penimbangan & Z-Score"
$cek = Req 'POST' "$base/kader/measurements" $tK @{ child_id = $idK1; measurement_date = '2026-09-26'; weight_kg = 7.1; height_cm = 75 }
Check "input penimbangan -> 201" 201 $cek.Status
$idUkur = $cek.Body.data.id
$zAwal  = $cek.Body.data.z_score_wfa
Check "  umur terhitung"    $true ($null -ne $cek.Body.data.age_in_months)
Check "  z-score terhitung" $true ($null -ne $zAwal)
Check "  status gizi ada"   $true ($null -ne $cek.Body.data.status_gizi)
Note "umur $($cek.Body.data.age_in_months) bln | z $zAwal | $($cek.Body.data.status_gizi)"

$r = Req 'GET' "$base/kader/measurements?child_id=$idK1" $tK $null
Check "daftar penimbangan (child_id) -> 200" 200 $r.Status
Check "  1 baris" 1 @($r.Body.data).Count
$tr = FindById $r.Body.data $idUkur
Check "  z-score di respons daftar sama" $zAwal $tr.z_score_wfa

# Setelah ada penimbangan, ringkasan gizi di daftar anak harus terisi dan
# harus sama dengan measurement terbaru (dipakai Dashboard Ibu).
# idK1 sudah dipindahkan ke Ibu B di grup 6, jadi dibaca dengan token Ibu B.
$cekAnak = Req 'GET' "$base/children/$idK1" $tB $null
Check "buka anak yang ditimbang -> 200" 200 $cekAnak.Status
$dAnak = $cekAnak.Body.data
Check "ringkasan gizi anak terisi setelah ditimbang" $true ($null -ne $dAnak.last_measurement_date)
Check "  tanggal = tanggal penimbangan" $tr.measurement_date $dAnak.last_measurement_date
Check "  z-score = z-score measurement" $tr.z_score_wfa $dAnak.latest_z_score
Check "  status = status measurement" $tr.status_gizi $dAnak.nutritional_status
Note "ringkasan: $($dAnak.last_measurement_date) | z $($dAnak.latest_z_score) | $($dAnak.nutritional_status)"

$cekAnakIbuLain = Req 'GET' "$base/children/$idK1" $tA $null
Check "Ibu A buka anak milik Ibu B -> 403" 403 $cekAnakIbuLain.Status

$r = Req 'GET' "$base/kader/measurements" $tK $null
Check "tanpa child_id -> 400" 400 $r.Status
Note "endpoint WAJIB ?child_id= - belum ada validasi yang jelas di pesan error"

$r = Req 'GET' "$base/kader/measurements?child_id=$idK1" $tA $null
Check "Ibu buka riwayat anak -> 403" 403 $r.Status
Note "Ibu belum bisa lihat riwayat anaknya - fitur belum ada"

$cek = Req 'POST' "$base/kader/measurements" $tK @{ child_id = $idK1; measurement_date = '2020-01-01'; weight_kg = 7.1; height_cm = 75 }
Check "tanggal sebelum lahir -> 422" 422 $cek.Status

# =====================================================================
Group "8. Z-Score ikut dihitung ulang saat data anak berubah"
$cek = Req 'PATCH' "$base/children/$idK1" $tK @{ gender = 'P' }
Check "ubah gender anak (L -> P) -> 200" 200 $cek.Status
Note "pesan: $($cek.Body.message)"
$r = Req 'GET' "$base/kader/measurements?child_id=$idK1" $tK $null
$tr2 = FindById $r.Body.data $idUkur
Note "z-score: $zAwal -> $($tr2.z_score_wfa)  ($($tr2.status_gizi))"
Check "  z-score dihitung ulang" $true ($tr2.z_score_wfa -ne $zAwal)

$cek = Req 'PATCH' "$base/children/$idK1" $tK @{ name = "Cuma Ganti Nama $s" }
Check "ganti nama tidak memicu hitung ulang" 'Data balita berhasil diperbarui.' $cek.Body.message

# =====================================================================
Group "9. Menghapus anak (soft delete)"
$r = Req 'DELETE' "$base/children/$idB" $tB $null
Check "Ibu hapus anak -> 403" 403 $r.Status
Check "  pesan" 'Akses ditolak' $r.Body.message
$r = Req 'GET' "$base/children/$idB" $tB $null
Check "  anak belum terhapus" 200 $r.Status

$r = Req 'DELETE' "$base/children/$idA2" $tK $null
Check "Kader hapus anak -> 200" 200 $r.Status
Note $r.Body.message
Check "  jumlah measurement diarsipkan" 0 $r.Body.data.archived_measurements

$r = Req 'GET' "$base/children/$idA2" $tA $null
Check "  detail anak terhapus -> 404" 404 $r.Status
$r = Req 'PATCH' "$base/children/$idA2" $tA @{ name = 'X' }
Check "  ubah anak terhapus -> 404" 404 $r.Status
$r = Req 'DELETE' "$base/children/$idA2" $tK $null
Check "  hapus kedua kali -> 404" 404 $r.Status
$r = Req 'GET' "$base/children" $tA $null
Check "  anak terhapus tidak muncul lagi" $false (Contains $r.Body.data $idA2)
Check "  anak Ibu A lainnya tetap ada" $true (Contains $r.Body.data $idA)

# =====================================================================
Group "9b. Imunisasi (master, checklist, catat, koreksi)"
# Checklist dihitung di PHP dari tanggal lahir anak; tidak ada kolom status
# di database. Unique constraint (child_id, immunization_type_id) yang
# mencegah satu anak punya dua record untuk dosis yang sama.
# =====================================================================

$r = Req 'GET' "$base/immunization-types" $tK $null
Check "GET /immunization-types -> 200" 200 $r.Status
Check "  master berisi 16 dosis" 16 $r.Body.data.Count
$typeHB0 = $null
$typeMR1 = $null
foreach ($d in $r.Body.data) {
    if ($d.code -eq 'HB'  -and $d.dose_number -eq 1) { $typeHB0 = $d.id }
    if ($d.code -eq 'MR'  -and $d.dose_number -eq 1) { $typeMR1 = $d.id }
}
Check "  ada master HB dosis 1" $true ($typeHB0 -ne $null)
Check "  ada master MR dosis 1" $true ($typeMR1 -ne $null)

$r = Req 'GET' "$base/immunization-types" $tA $null
Check "Ibu boleh baca master -> 200" 200 $r.Status

# Anak uji: lahir 2024-01-15, jadi ~32 bulan pada 2026-09.
$r = Req 'GET' "$base/children/$idA/immunizations" $tA $null
Check "GET checklist anak -> 200" 200 $r.Status
Check "  checklist 16 baris" 16 $r.Body.data.checklist.Count
Check "  summary total 16" 16 $r.Body.data.summary.total
Check "  belum ada yang suntik" 0 $r.Body.data.summary.sudah
Check "  anak jauh lewat target -> terlambat" 16 $r.Body.data.summary.terlambat
Check "  tidak ada sisa 'belum'" 0 $r.Body.data.summary.belum
Check "  tanggal lahir anak ikut dikirim" '2024-01-15' $r.Body.data.child.date_of_birth

# Anak yang baru lahir: semua dosis masih di masa depan -> belum.
$idBayi = (Req 'POST' "$base/children" $tA @{ name = "Bayi Baru $s"; date_of_birth = (Get-Date -Format 'yyyy-MM-dd'); gender = 'P' }).Body.data.id
$r = Req 'GET' "$base/children/$idBayi/immunizations" $tA $null
Check "checklist bayi baru -> semua belum" 16 $r.Body.data.summary.belum
Check "  tidak ada yang terlambat" 0 $r.Body.data.summary.terlambat
Note "sisa_bulan = sisa bulan menuju status terlambat, negatif = sudah lewat"

# Kader mencatat suntikan.
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tK @{ immunization_type_id = $typeHB0; date_given = (Get-Date -Format 'yyyy-MM-dd'); batch_number = 'BATCH-001'; notes = 'uji otomatis' }
Check "POST suntikan -> 201" 201 $r.Status
Check "  kader_id = akun yg login" $kader.Id $r.Body.data.kader_id
Check "  tanggal terkirim Y-m-d" (Get-Date -Format 'yyyy-MM-dd') $r.Body.data.date_given
Check "  label dosis ikut dikirim" 'Hepatitis B' $r.Body.data.immunization_type.label
$idImun = $r.Body.data.id

# Dosis sama tidak boleh dicatat dua kali.
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tK @{ immunization_type_id = $typeHB0; date_given = (Get-Date -Format 'yyyy-MM-dd') }
Check "suntik dosis sama dua kali -> 422" 422 $r.Status
Note "unique constraint immunization_child_type_unique yang menahan"

# Ibu tidak boleh mencatat.
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tA @{ immunization_type_id = $typeMR1; date_given = (Get-Date -Format 'yyyy-MM-dd') }
Check "Ibu catat suntikan -> 403" 403 $r.Status

# Ibu tidak boleh melihat checklist anak orang.
$r = Req 'GET' "$base/children/$idK1/immunizations" $tA $null
Check "Ibu lihat checklist anak orang -> 403" 403 $r.Status

# Validasi.
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tK @{ immunization_type_id = 'bukan-uuid'; date_given = '2024-01-01' }
Check "tipe dosis ngawur -> 422" 422 $r.Status
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tK @{ immunization_type_id = $typeMR1; date_given = '01-15-2024' }
Check "tanggal format salah -> 422" 422 $r.Status
Note "date_format:Y-m-d mencegah 500 dari PostgreSQL"
$r = Req 'POST' "$base/kader/children/$idBayi/immunizations" $tK @{ immunization_type_id = $typeMR1; date_given = '2099-01-01' }
Check "tanggal masa depan -> 422" 422 $r.Status

# Status checklist berubah jadi 'sudah'.
$r = Req 'GET' "$base/children/$idBayi/immunizations" $tA $null
Check "setelah suntik: summary sudah = 1" 1 $r.Body.data.summary.sudah
$itemHB0 = $null
foreach ($d in $r.Body.data.checklist) { if ($d.immunization_type_id -eq $typeHB0) { $itemHB0 = $d } }
Check "  item HB0 status = sudah" 'sudah' $itemHB0.status
Check "  item HB0 punya record" $true ($itemHB0.record -ne $null)
Check "  sisa_bulan null setelah suntik" $null $itemHB0.sisa_bulan

# Koreksi lewat PATCH (bukan hapus-lalu-simpan).
$r = Req 'PATCH' "$base/kader/immunizations/$idImun" $tK @{ date_given = '2024-01-20'; notes = 'dikoreksi' }
Check "PATCH koreksi suntikan -> 200" 200 $r.Status
Check "  tanggal berubah" '2024-01-20' $r.Body.data.date_given
Check "  notes berubah" 'dikoreksi' $r.Body.data.notes

$r = Req 'PATCH' "$base/kader/immunizations/$idImun" $tA @{ date_given = '2024-01-25' }
Check "Ibu koreksi suntikan -> 403" 403 $r.Status
$r = Req 'PATCH' "$base/kader/immunizations/$idImun" $tK @{}
Check "PATCH tanpa field -> 422" 422 $r.Status
$r = Req 'PATCH' "$base/kader/immunizations/bukan-uuid" $tK @{ date_given = '2024-01-20' }
Check "PATCH id ngawur -> 404" 404 $r.Status

# =====================================================================
Group "9c. Daftar petugas (privasi NIK)"
# Endpoint terbuka untuk Ibu & Kader, jadi NIK tidak boleh bocor.
# =====================================================================
$r = Req 'GET' "$base/petugas" $tA $null
Check "GET /petugas -> 200" 200 $r.Status
Check "  ada petugas" $true ($r.Body.data.Count -gt 0)
$adaNik = $false
foreach ($d in $r.Body.data) { if ($d.PSObject.Properties.Name -contains 'nik') { $adaNik = $true } }
Check "  TIDAK ada field nik" $false $adaNik
Note "Ibu hanya melihat nama, jabatan, dan nomor HP petugas"
$r = Req 'GET' "$base/petugas" $tK $null
Check "Kader juga boleh baca -> 200" 200 $r.Status
Check "  tidak ada NIK juga untuk kader" $false ($r.Raw -match '"nik"')

# =====================================================================
Group "9d. Jadwal posyandu"
# =====================================================================
$r = Req 'GET' "$base/schedules" $tA $null
Check "GET /schedules -> 200" 200 $r.Status
Check "  success true" $true $r.Body.success

$petugasIds = @()
$r2 = Req 'GET' "$base/petugas" $tK $null
foreach ($d in $r2.Body.data) { $petugasIds += $d.id }
Check "  punya minimal 1 petugas untuk uji" $true ($petugasIds.Count -gt 0)

$r = Req 'POST' "$base/kader/schedules" $tK @{ title = "Agenda Uji $s"; description = 'dibuat uji-api'; scheduled_date = '2026-12-25'; start_time = '08:00'; end_time = '10:00'; petugas_ids = @($petugasIds[0]) }
Check "POST jadwal -> 201" 201 $r.Status
Check "  status default terjadwal" 'terjadwal' $r.Body.data.status
Check "  petugas terpasang 1" 1 $r.Body.data.petugas_ids.Count
Check "  ada location_name" $true ($r.Body.data.location_name -ne $null)
Note "location_name jatuh ke config posyandu.posyandu_name saat location kosong"
$idSch = $r.Body.data.id

# Ibu hanya boleh membaca.
$r = Req 'POST' "$base/kader/schedules" $tA @{ title = "Ibu Coba"; scheduled_date = '2026-12-26' }
Check "Ibu buat jadwal -> 403" 403 $r.Status
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tA @{ status = 'selesai' }
Check "Ibu ubah jadwal -> 403" 403 $r.Status
$r = Req 'DELETE' "$base/kader/schedules/$idSch" $tA $null
Check "Ibu hapus jadwal -> 403" 403 $r.Status

# Status harus salah satu dari empat yang diizinkan CHECK constraint.
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tK @{ status = 'ngada' }
Check "status ngawur -> 422" 422 $r.Status
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tK @{ status = 'berlangsung' }
Check "PATCH status -> 200" 200 $r.Status
Check "  status berubah" 'berlangsung' $r.Body.data.status
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tK @{}
Check "PATCH tanpa field -> 422" 422 $r.Status

# Hanya akun kader boleh ditugaskan.
$r = Req 'POST' "$base/kader/schedules" $tK @{ title = "Petugas Salah $s"; scheduled_date = '2026-12-27'; petugas_ids = @($ibuA.Id) }
Check "petugas_ids role ibu -> 422" 422 $r.Status
Note "akun ibu tidak boleh masuk daftar petugas"

# Ganti daftar petugas.
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tK @{ petugas_ids = @($petugasIds[0], $kader2.Id) }
Check "PATCH petugas_ids -> 200" 200 $r.Status
Check "  dua petugas terpasang" 2 $r.Body.data.petugas_ids.Count
$r = Req 'PATCH' "$base/kader/schedules/$idSch" $tK @{ petugas_ids = @() }
Check "PATCH kosongkan petugas -> 200" 200 $r.Status
Check "  tidak ada petugas" 0 $r.Body.data.petugas_ids.Count

# Filter tanggal.
$r = Req 'GET' "$base/schedules?date=2026-12-25" $tA $null
Check "filter per tanggal -> 200" 200 $r.Status
Check "  ketemu 1 agenda" 1 $r.Body.data.Count
Check "  judul benar" "Agenda Uji $s" $r.Body.data[0].title
$r = Req 'GET' "$base/schedules?date=2020-01-01" $tA $null
Check "tanggal tanpa agenda -> 0 hasil" 0 $r.Body.data.Count

# Validasi & validasi id.
$r = Req 'POST' "$base/kader/schedules" $tK @{ title = 'Tanpa Tanggal' }
Check "jadwal tanpa tanggal -> 422" 422 $r.Status
$r = Req 'POST' "$base/kader/schedules" $tK @{ title = 'Jam Ngawur'; scheduled_date = '2026-12-25'; start_time = '10:00'; end_time = '08:00' }
Check "end sebelum start -> 422" 422 $r.Status
$r = Req 'PATCH' "$base/kader/schedules/bukan-uuid" $tK @{ status = 'selesai' }
Check "id ngawur -> 404" 404 $r.Status
$r = Req 'DELETE' "$base/kader/schedules/bukan-uuid" $tK $null
Check "hapus id ngawur -> 404" 404 $r.Status

# Hapus agenda -> pivot ikut terhapus.
$r = Req 'DELETE' "$base/kader/schedules/$idSch" $tK $null
Check "DELETE jadwal -> 200" 200 $r.Status
$r = Req 'GET' "$base/schedules?date=2026-12-25" $tA $null
Check "  agenda hilang" 0 $r.Body.data.Count
$r = Req 'DELETE' "$base/kader/schedules/$idSch" $tK $null
Check "  hapus kedua kali -> 404" 404 $r.Status

# Bersihkan agenda uji yang gagal dihapus (mis. aborted di tengah).
if (Test-Path $php) {
    $cleanSch = @"
<?php
require '$backend/vendor/autoload.php';
`$app = require '$backend/bootstrap/app.php';
`$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
`$n = Illuminate\Support\Facades\DB::table('posyandu_schedules')->where('title', 'like', '%$s%')->delete();
echo '  agenda uji dihapus: ' . `$n . PHP_EOL;
"@
    $tmpS = Join-Path $env:TEMP 'posyandu_cleanup_sched.php'
    Set-Content -Path $tmpS -Value $cleanSch -Encoding UTF8
    & $php $tmpS 2>&1 | ForEach-Object { Write-Host "  $_" }
    Remove-Item $tmpS -Force -ErrorAction SilentlyContinue
}

$r = Req 'DELETE' "$base/kader/measurements/$idUkur" $tK $null
Check "hapus penimbangan -> 200" 200 $r.Status

# =====================================================================
Group "10. Logout"
$r = Req 'POST' "$base/logout" $tK2 $null
Check "logout -> 200" 200 $r.Status
$r = Req 'GET' "$base/children" $tK2 $null
Check "token dibatalkan -> 401" 401 $r.Status

# =====================================================================
Group "10b. Request API tanpa header Accept: application/json"
# Aplikasi ini API-only, jadi tidak ada route web `login`. Kalau middleware
# Authenticate tetap memanggil route('login') untuk tamu, hasilnya 500 dan
# Flutter tidak bisa membedakan "sesi habis" dari "server rusak".
$plain = @()
foreach ($p in @(
        @{ M = 'GET'; U = "$base/immunization-types" }
        @{ M = 'GET'; U = "$base/children" }
        @{ M = 'GET'; U = "$base/schedules" }
        @{ M = 'GET'; U = "$base/petugas" })) {
    try {
        $resp = Invoke-WebRequest -Uri $p.U -Method $p.M -UseBasicParsing -TimeoutSec 20
        $plain += $resp.StatusCode
    } catch {
        if ($_.Exception.Response) { $plain += $_.Exception.Response.StatusCode.value__ }
        else { $plain += 0 }
    }
}
Check "tamu tanpa Accept dapat 401" 401 $plain[0]
Check "tamu tanpa Accept dapat 401" 401 $plain[1]
Check "tamu tanpa Accept dapat 401" 401 $plain[2]
Check "tamu tanpa Accept dapat 401" 401 $plain[3]

# =====================================================================
Group "11. Tidak ada kebocoran pesan internal"
$bad = Req 'PATCH' "$base/children/bukan-uuid" $tA @{ name = 'X' }
Check "tidak ada SQLSTATE"   $false ($bad.Raw -match 'SQLSTATE')
Check "tidak ada PostgreSQL" $false ($bad.Raw -match 'PostgreSQL')
Check "tidak ada path file"  $false ($bad.Raw -match 'Controller\.php|bootstrap\\app|vendor\\')
$bad2 = Req 'POST' "$base/kader/children" $tK @{ name = "Y $s"; date_of_birth = '2024-01-01'; gender = 'P'; ibu_nik = '0000000000000000' }
Check "respons 404 bersih"   $false ($bad2.Raw -match 'SQLSTATE|PostgreSQL')

# =====================================================================
Group "12. Membersihkan data uji"
if (Test-Path $php) {
    $nikList = "['$nIbuA','$nIbuB','$nKader','$nKader2']"
    $cleanup = @"
<?php
require '$backend/vendor/autoload.php';
`$app = require '$backend/bootstrap/app.php';
`$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
`$niks = $nikList;
`$users = Illuminate\Support\Facades\DB::table('users')->whereIn('nik', `$niks)->get();
foreach (`$users as `$u) {
    Illuminate\Support\Facades\DB::table('personal_access_tokens')->where('tokenable_id', `$u->id)->delete();
    Illuminate\Support\Facades\DB::table('children')->where('user_id', `$u->id)->delete();
    Illuminate\Support\Facades\DB::table('users')->where('id', `$u->id)->delete();
}
echo '  user uji dihapus: ' . `$users->count() . PHP_EOL;
echo '  sisa user    : ' . Illuminate\Support\Facades\DB::table('users')->count() . PHP_EOL;
echo '  sisa anak    : ' . Illuminate\Support\Facades\DB::table('children')->count() . PHP_EOL;
echo '  sisa archived: ' . Illuminate\Support\Facades\DB::table('children')->whereNotNull('deleted_at')->count() . PHP_EOL;
echo '  sisa suntikan: ' . Illuminate\Support\Facades\DB::table('immunization_records')->count() . PHP_EOL;
echo '  sisa jadwal  : ' . Illuminate\Support\Facades\DB::table('posyandu_schedules')->count() . PHP_EOL;
"@
    $tmp = Join-Path $env:TEMP 'posyandu_cleanup.php'
    Set-Content -Path $tmp -Value $cleanup -Encoding UTF8
    & $php $tmp 2>&1 | ForEach-Object { Write-Host "  $_" }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  PHP tidak ditemukan - data uji perlu dihapus manual" -ForegroundColor Yellow
}

# =====================================================================
Write-Host ''
Write-Host "==================================================" -ForegroundColor Cyan
if ($script:throttled) {
    Write-Host " CATATAN: ada respons 429 (throttle). Tunggu ~1 menit lalu ulangi." -ForegroundColor Yellow
}
if ($script:fail -eq 0) {
    Write-Host " HASIL: $script:pass pemeriksaan LULUS, 0 gagal" -ForegroundColor Green
} else {
    Write-Host " HASIL: $script:pass lulus, $script:fail GAGAL" -ForegroundColor Yellow
}
Write-Host "==================================================" -ForegroundColor Cyan
exit $script:fail
