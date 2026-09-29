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
        $code = $r.StatusCode; $raw = $r.Content; $hdr = $r.Headers
    } catch {
        if ($_.Exception.Response) {
            $code = $_.Exception.Response.StatusCode.value__
            $hdr = $_.Exception.Response.Headers
            $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
            $raw = $sr.ReadToEnd(); $sr.Close()
        } else { $code = 0; $raw = $_.Exception.Message; $hdr = $null }
    }
    $o = $null
    if ($raw) { try { $o = $raw | ConvertFrom-Json } catch { } }
    if ($code -eq 429) { $script:throttled = $true }
    # `Headers` dipakai grup 9g (export CSV) untuk memeriksa Content-Type dan
    # Content-Disposition. `Body` sengaja tetap null untuk respons CSV: isinya
    # bukan JSON, jadi `ConvertFrom-Json` gagal dan ditelan `catch`.
    return @{ Status = $code; Body = $o; Raw = $raw; Headers = $hdr }
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
Group "9b-2. Urutan dosis & pembatalan suntikan"
# Dua hal yang ditutup pada Opsi A:
#  1. interval_months divalidasi: dosis N tidak boleh lebih tua dari
#     dosis N-1 pada vaksin yang sama (divalidasi juga saat PATCH).
#  2. DELETE /kader/immunizations/{record} untuk membatalkan suntikan yang
#     salah pilih dosis. Soft delete + unique partial index, jadi dosis yang
#     dibatalkan boleh dicatat ulang.
# =====================================================================

$r = Req 'GET' "$base/immunization-types" $tK $null
$typeMR2 = $null
foreach ($d in $r.Body.data) {
    if ($d.code -eq 'MR' -and $d.dose_number -eq 2) { $typeMR2 = $d.id }
}
Check "ada master MR dosis 2" $true ($typeMR2 -ne $null)

# Tanggal tetap, biar urutan assertion jelas dan tidak ikut berubah harian.
$tMR1 = '2026-01-10'
$tMR2 = '2026-01-20'

$r = Req 'POST' "$base/kader/children/$idA/immunizations" $tK @{ immunization_type_id = $typeMR1; date_given = $tMR1 }
Check "catat MR dosis 1 -> 201" 201 $r.Status
$idMR1 = $r.Body.data.id

# Dosis 2 dengan tanggal lebih tua dari dosis 1 harus ditolak.
$r = Req 'POST' "$base/kader/children/$idA/immunizations" $tK @{ immunization_type_id = $typeMR2; date_given = '2026-01-05' }
Check "dosis 2 lebih tua dari dosis 1 -> 422" 422 $r.Status
Check "  pesan ditaruh di date_given" $true ($r.Body.errors.date_given -ne $null)
Note "sebelumnya tanggal 2026-01-05 untuk dosis 2 diterima begitu saja"

# Tanggal sama dengan dosis sebelumnya tetap boleh: suntik massal bisa
# di hari yang sama.
$r = Req 'POST' "$base/kader/children/$idA/immunizations" $tK @{ immunization_type_id = $typeMR2; date_given = $tMR2 }
Check "dosis 2 tanggal wajar -> 201" 201 $r.Status
$idMR2 = $r.Body.data.id

# PATCH tidak boleh dipakai menembus validasi urutan.
$r = Req 'PATCH' "$base/kader/immunizations/$idMR1" $tK @{ date_given = '2026-01-25' }
Check "PATCH dosis 1 ke tanggal setelah dosis 2 -> 422" 422 $r.Status
$r = Req 'PATCH' "$base/kader/immunizations/$idMR1" $tK @{ date_given = '2026-01-15' }
Check "PATCH dosis 1 ke tanggal antara -> 200" 200 $r.Status

# Pembatalan suntikan.
$r = Req 'DELETE' "$base/kader/immunizations/$idMR2" $tA $null
Check "Ibu batalkan suntikan -> 403" 403 $r.Status
$r = Req 'DELETE' "$base/kader/immunizations/bukan-uuid" $tK $null
Check "DELETE id ngawur -> 404" 404 $r.Status
$r = Req 'DELETE' "$base/kader/immunizations/11111111-2222-3333-4444-555555555555" $tK $null
Check "DELETE id uuid tidak ada -> 404" 404 $r.Status
$r = Req 'DELETE' "$base/kader/immunizations/$idMR2" $tK $null
Check "DELETE suntikan -> 200" 200 $r.Status
Check "  id agenda dikembalikan" $idMR2 $r.Body.data.id

# Setelah dibatalkan, dosis itu tidak lagi 'sudah' dan record-nya null.
# Anak uji berumur ~32 bulan, sedangkan MR dosis 2 punya target 18 bulan,
# jadi tanpa record statusnya 'terlambat', bukan 'belum'.
$r = Req 'GET' "$base/children/$idA/immunizations" $tA $null
# Item checklist tidak punya field `id`; penandanya `immunization_type_id`.
$itemMR2 = $null
foreach ($d in $r.Body.data.checklist) { if ($d.immunization_type_id -eq $typeMR2) { $itemMR2 = $d } }
Check "dosis dibatalkan -> bukan 'sudah' lagi" 'terlambat' $itemMR2.status
Check "  record jadi null" $null $itemMR2.record
Note "soft delete: baris tetap ada di DB, hanya deleted_at terisi"

# Partial unique index: dosis yang dibatalkan boleh dicatat ulang.
$r = Req 'POST' "$base/kader/children/$idA/immunizations" $tK @{ immunization_type_id = $typeMR2; date_given = $tMR2 }
Check "catat ulang dosis yang dibatalkan -> 201" 201 $r.Status
$idMR2b = $r.Body.data.id
$r = Req 'GET' "$base/children/$idA/immunizations" $tA $null
$itemMR2 = $null
foreach ($d in $r.Body.data.checklist) { if ($d.immunization_type_id -eq $typeMR2) { $itemMR2 = $d } }
Check "  setelah dicatat ulang -> 'sudah'" 'sudah' $itemMR2.status
Check "  sisa_bulan null lagi" $null $itemMR2.sisa_bulan

# Batalkan dua kali harus 404, bukan diam-diam sukses.
$r = Req 'DELETE' "$base/kader/immunizations/$idMR2" $tK $null
Check "DELETE record yang sudah dibatalkan -> 404" 404 $r.Status

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

# =====================================================================
Group "9e. Catatan keluhan (Opsi C)"
# Keluhan disimpan sebagai KOLOM BOOLEAN TERPISAIN (demam/rewel/diare), bukan
# JSON dan bukan satu baris per keluhan - supaya rekap bulan ini ("berapa anak
# demam?") nanti bisa jadi satu aggregate di database.
# Yang diuji di sini:
#  1. Satu anak satu catatan per hari (unique partial
#     medical_notes_child_date_unique).
#  2. Catatan tidak boleh kosong: minimal satu keluhan dicentang ATAU `catatan`
#     terisi. Diperiksa di PHP (422) DAN di CHECK constraint database.
#  3. Ibu baca saja; menulis hanya lewat prefix /kader/.
#  4. `note_date` BOLEH diubah lewat PATCH - berbeda dari suntikan, karena
#     kesalahan tanggal di sini adalah salah pilih hari di kalender.
#  5. `measurement_id` milik anak lain ditolak, dan catatan TETAP ADA walau
#     penimbangan yang ditautkan DIBATALKAN. Catatan masih menunjuk
#     penimbangan itu (lihat catatan kontrak di bawah).
# =====================================================================

# Tanggal uji: mundur beberapa hari supaya tidak bentrok dengan data seed
# seeder, yang memakai tanggal hari ini dan tanggal bulan lalu.
$tglUji  = (Get-Date).AddDays(-4).ToString('yyyy-MM-dd')
$tglUji2 = (Get-Date).AddDays(-5).ToString('yyyy-MM-dd')
$blnIni  = (Get-Date).ToString('yyyy-MM')
$blnLalu = (Get-Date).AddMonths(-1).ToString('yyyy-MM')

$r = Req 'GET' "$base/children/$idA/medical-notes" $tK $null
Check "GET daftar keluhan -> 200" 200 $r.Status
Check "  default filter = bulan berjalan" $blnIni $r.Body.data.filter.month
Check "  default bukan mode all" $false $r.Body.data.filter.all
Check "  awal: tidak ada catatan" 0 $r.Body.data.summary.total
Check "  respons kirim info anak" $idA $r.Body.data.child.id

$r = Req 'GET' "$base/children/$idA/medical-notes?month=$blnLalu" $tK $null
Check "filter ?month= -> 200" 200 $r.Status
Check "  bulan yang diminta" $blnLalu $r.Body.data.filter.month

$r = Req 'GET' "$base/children/$idA/medical-notes?all=1" $tK $null
Check "filter ?all=1 -> 200" 200 $r.Status
Check "  month = null saat all" $null $r.Body.data.filter.month
Check "  all = true" $true $r.Body.data.filter.all

# month tidak valid harus 422, bukan 500 dari PostgreSQL.
$r = Req 'GET' "$base/children/$idA/medical-notes?month=2026-13" $tK $null
Check "?month=2026-13 -> 422" 422 $r.Status
Note "date_format:Y-m menolak bulan yang tidak ada"
$r = Req 'GET' "$base/children/$idA/medical-notes?month=202602" $tK $null
Check "?month=202602 (tanpa garis) -> 422" 422 $r.Status

# Penimbangan milik anak uji ini, untuk menguji tautan opsional.
$r = Req 'POST' "$base/kader/measurements" $tK @{ child_id = $idA; measurement_date = $tglUji2; weight_kg = 7.2; height_cm = 75 }
$idUkurKeluhan = $r.Body.data.id

# POST valid, ditautkan ke penimbangan anak yang sama.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{
    measurement_id = $idUkurKeluhan
    note_date      = $tglUji
    demam          = $true
    rewel          = $false
    diare          = $false
    catatan        = 'Demam 38,5C sejak sore'
    tindak_lanjut  = 'rujuk'
}
Check "POST catatan keluhan -> 201" 201 $r.Status
$idKeluhan = $r.Body.data.id
Check "  kader_id = akun yg login" $kader.Id $r.Body.data.kader_id
Check "  boolean demam terkirim true" $true $r.Body.data.demam
Check "  boolean rewel terkirim false" $false $r.Body.data.rewel
Check "  tanggal terkirim Y-m-d" $tglUji $r.Body.data.note_date
Check "  daftar keluhan ikut dikirim" 'Demam' $r.Body.data.keluhan[0]
Check "  ringkasan digabung di server" 'Demam - Demam 38,5C sejak sore' $r.Body.data.ringkasan
Check "  nama kader ikut dikirim" "Uji Kader $s" $r.Body.data.kader.name
Check "  measurement_id ikut tersimpan" $true ($null -ne $r.Body.data.measurement_id)

# Satu anak satu catatan per hari.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji; demam = $true }
Check "catat tanggal sama dua kali -> 422" 422 $r.Status
Note "medical_notes_child_date_unique yang menahan"

# Catatan kosong: tidak ada keluhan dicentang dan `catatan` hanya spasi.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji2; demam = $false; rewel = $false; diare = $false; catatan = '   ' }
Check "catatan kosong -> 422" 422 $r.Status
Check "  pesan ramah" 'Catatan keluhan masih kosong.' $r.Body.message
Check "  ada petunjuk di field Demam" $true ($null -ne $r.Body.errors.demam)

# Tidak ada keluhan dicentang, tapi `catatan` terisi: harus diterima. Inilah
# kasus yang membuat CHECK constraint ikut memeriksa `catatan`.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{
    note_date     = $tglUji2
    demam         = $false
    rewel         = $false
    diare         = $false
    catatan       = 'Ibu diminta lebih sering menyusui'
    tindak_lanjut = 'ringan'
}
Check "hanya catatan saran (tanpa keluhan) -> 201" 201 $r.Status
Check "  keluhan kosong" 0 $r.Body.data.keluhan.Count
Check "  ringkasan jatuh ke catatan" 'Ibu diminta lebih sering menyusui' $r.Body.data.ringkasan
$idCatatanSaja = $r.Body.data.id

# Validasi lain.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = (Get-Date).AddDays(2).ToString('yyyy-MM-dd'); demam = $true }
Check "tanggal masa depan -> 422" 422 $r.Status
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = '05-10-2026'; demam = $true }
Check "tanggal format salah -> 422" 422 $r.Status
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji; demam = $true; tindak_lanjut = 'semangat' }
Check "tindak_lanjut ngawur -> 422" 422 $r.Status
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji; demam = $true; measurement_id = 'bukan-uuid' }
Check "measurement_id ngawur -> 422" 422 $r.Status

# Penimbangan milik anak lain tidak boleh dilampirkan.
$ukurAnakLain = (Req 'POST' "$base/kader/measurements" $tK @{ child_id = $idB; measurement_date = $tglUji2; weight_kg = 7.3; height_cm = 76 }).Body.data.id
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji2; demam = $true; measurement_id = $ukurAnakLain }
Check "lampirkan penimbangan anak lain -> 422" 422 $r.Status
Check "  pesan menyebut milik anak tersebut" $true ($null -ne $r.Body.errors.measurement_id)
Req 'DELETE' "$base/kader/measurements/$ukurAnakLain" $tK $null | Out-Null

# Ibu: baca boleh, tulis tidak.
$r = Req 'GET' "$base/children/$idA/medical-notes" $tA $null
Check "Ibu baca keluhan anaknya -> 200" 200 $r.Status
Check "  2 catatan" 2 $r.Body.data.summary.total
Check "  1 demam" 1 $r.Body.data.summary.demam
Check "  1 perlu rujuk" 1 $r.Body.data.summary.perlu_rujuk
$r = Req 'GET' "$base/children/$idB/medical-notes" $tA $null
Check "Ibu baca keluhan anak orang -> 403" 403 $r.Status
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tA @{ note_date = $tglUji; demam = $true }
Check "Ibu catat keluhan -> 403" 403 $r.Status
$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tA @{ demam = $false }
Check "Ibu koreksi keluhan -> 403" 403 $r.Status
$r = Req 'DELETE' "$base/kader/medical-notes/$idKeluhan" $tA $null
Check "Ibu batalkan keluhan -> 403" 403 $r.Status

# PATCH: koreksi keluhan, termasuk menggeser tanggal.
$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tK @{ demam = $false; diare = $true; catatan = 'Ternyata diare' }
Check "PATCH koreksi keluhan -> 200" 200 $r.Status
Check "  demam mati" $false $r.Body.data.demam
Check "  diare nyala" $true $r.Body.data.diare
Check "  ringkasan dihitung ulang" 'Diare - Ternyata diare' $r.Body.data.ringkasan

$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tK @{ note_date = (Get-Date).AddDays(-7).ToString('yyyy-MM-dd') }
Check "PATCH geser tanggal -> 200" 200 $r.Status
Check "  tanggal berubah" (Get-Date).AddDays(-7).ToString('yyyy-MM-dd') $r.Body.data.note_date
Note "berbeda dari suntikan, tanggal boleh digeser lewat PATCH"

# PATCH yang membuat catatan kosong harus ditolak.
$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tK @{ diare = $false; catatan = '' }
Check "PATCH jadi catatan kosong -> 422" 422 $r.Status
Note "isi dinilai dari gabungan nilai lama + baru, bukan hanya field yang dikirim"

$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tK @{}
Check "PATCH tanpa field -> 422" 422 $r.Status
$r = Req 'PATCH' "$base/kader/medical-notes/bukan-uuid" $tK @{ demam = $true }
Check "PATCH id ngawur -> 404" 404 $r.Status
$r = Req 'GET' "$base/children/bukan-uuid/medical-notes" $tK $null
Check "GET child id ngawur -> 404" 404 $r.Status
Note "Str::isUuid dicek dulu supaya bukan 500 dari PostgreSQL"

# PATCH ke tanggal milik catatan lain.
$r = Req 'PATCH' "$base/kader/medical-notes/$idKeluhan" $tK @{ note_date = $tglUji2 }
Check "PATCH tabrak tanggal catatan lain -> 422" 422 $r.Status

# Catatan yang dibatalkan (soft delete) tidak muncul lagi di daftar.
$r = Req 'DELETE' "$base/kader/medical-notes/$idCatatanSaja" $tK $null
Check "DELETE batalkan catatan -> 200" 200 $r.Status
$r = Req 'GET' "$base/children/$idA/medical-notes?all=1" $tA $null
Check "catatan dibatalkan hilang dari daftar" 1 $r.Body.data.summary.total
Note "soft delete: baris tetap ada di DB, hanya ditandai deleted_at"

# Tanggal yang sama boleh dicatat ulang setelah pembatalan.
$r = Req 'POST' "$base/kader/children/$idA/medical-notes" $tK @{ note_date = $tglUji2; rewel = $true; catatan = 'Dicatat ulang setelah pembatalan' }
Check "catat ulang tanggal yang dibatalkan -> 201" 201 $r.Status
$idCatatUlang = $r.Body.data.id
Req 'DELETE' "$base/kader/medical-notes/$idCatatUlang" $tK $null | Out-Null
Note "unique index-nya partial (WHERE deleted_at IS NULL)"

# Catatan tetap hidup walau penimbangan yang ditautkan DIBATALKAN.
$r = Req 'DELETE' "$base/kader/measurements/$idUkurKeluhan" $tK $null
Check "batalkan penimbangan tertaut -> 200" 200 $r.Status
$r = Req 'GET' "$base/children/$idA/medical-notes?all=1" $tK $null
$catatanHidup = FindById $r.Body.data.notes $idKeluhan
Check "catatan tetap ada setelah penimbangan dibatalkan" $true ($null -ne $catatanHidup)

# PERUBAHAN KONTRAK (migration 2026_09_27_020000, soft delete pada `measurements`).
# Sebelumnya `measurement_id` jadi null di sini karena `delete()` menghapus
# baris secara fisik sehingga FK `ON DELETE SET NULL` menyala. Sekarang tabel
# `measurements` memakai soft delete, jadi barisnya tidak hilang dan FK tidak
# pernah menyala: catatan MASIH menunjuk penimbangan yang sudah dibatalkan.
#
# Ini disengaja dan lebih berguna untuk audit - "keluhan ini dicatat saat
# penimbangan 18 Sep, yang lalu dibatalkan" lebih berharga daripada tautan
# yang hilang. Yang tetap dijamin adalah isi catatan itu sendiri utuh.
# Kalau suatu saat tautan benar-benar harus dilepas, itu harus dilakukan
# eksplisit (mis. saat forceDelete), bukan diharapkan dari efek samping delete.
Check "  measurement_id masih menunjuk penimbangan yg dibatalkan" $idUkurKeluhan $catatanHidup.measurement_id
Note "soft delete: FK nullOnDelete hanya menyala untuk hapus fisik"
Check "  keluhan tetap utuh" $true $catatanHidup.diare
Note "keluhan adalah informasi kesehatan, tidak boleh ikut hilang"

$r = Req 'GET' "$base/children/$idA/medical-notes?all=1" $tK $null
Check "total akhir: 1 catatan aktif" 1 $r.Body.data.summary.total
Note "sisa baris fisik 3 (1 aktif + 2 dibatalkan), dicek di grup 12"

# =====================================================================
Group "9f. Rekap imunisasi bulanan (Opsi E)"
# Grup ini yang pertama kali benar-benar menyentuh
# `GET /kader/immunizations/recap`. Sebelumnya endpoint-nya tidak pernah
# dipanggil oleh uji-api sama sekali, jadi 288 pemeriksaan yang lulus tidak
# berarti apa-apa untuk fitur ini. TypeError di
# `ImmunizationRecapService::coverageAt()` yang bikin 500 di setiap request
# baru ketahuan setelah feature test ditambahkan.
# =====================================================================

# Ibu tidak boleh: rekap mengekspos seluruh Posyandu.
$r = Req 'GET' "$base/kader/immunizations/recap" $tA $null
Check "Ibu buka rekap -> 403" 403 $r.Status
Check "  success false" $false $r.Body.success
Note "Ibu tetap bisa lihat anaknya sendiri lewat /children/{id}/immunizations"

# Validasi bulan.
$r = Req 'GET' "$base/kader/immunizations/recap?month=2026-13" $tK $null
Check "bulan 13 -> 422" 422 $r.Status
Check "  ada error di field month" $true ($r.Body.errors.PSObject.Properties.Name -contains 'month')
$r = Req 'GET' "$base/kader/immunizations/recap?month=202602" $tK $null
Check "bulan tanpa garis -> 422" 422 $r.Status

# Bentuk respons. `filter` sengaja diletakkan di dalam `data`, bukan di root:
# ia menggabungkan echo permintaan dengan tanggal acuan hasil perhitungan.
$bulanUji = Get-Date -Format 'yyyy-MM'
$hariIni  = Get-Date -Format 'yyyy-MM-dd'
$akhirBulanUji = ([datetime]::ParseExact($bulanUji, 'yyyy-MM', $null)).AddMonths(1).AddDays(-1).ToString('yyyy-MM-dd')

$r = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null
Check "Kader buka rekap -> 200" 200 $r.Status
Check "  success true" $true $r.Body.success
Check "  filter.month = bulan diminta" $bulanUji $r.Body.data.filter.month
Check "  filter.reference_date = akhir bulan" $akhirBulanUji $r.Body.data.filter.reference_date
Check "  activity ada" $true ($r.Body.data.activity.PSObject.Properties.Name -contains 'total_doses')
Check "  coverage ada" $true ($r.Body.data.coverage.PSObject.Properties.Name -contains 'excluded_archived')
Check "  by_type = master 16 dosis" 16 $r.Body.data.activity.by_type.Count
Note "semua master dosis muncul, termasuk yang count-nya 0"
Check "  overdue_children berupa array" $true ($r.Body.data.coverage.overdue_children -is [array])
Check "  total = lengkap + kurang" ($r.Body.data.coverage.complete + $r.Body.data.coverage.incomplete) $r.Body.data.coverage.total_children

# Aktivitas: suntikan bulan berjalan terhitung per jenis vaksin.
$anakUji = Req 'POST' "$base/children" $tA @{ name = "Anak Rekap $s"; date_of_birth = '2024-01-15'; gender = 'P' }
Check "anak untuk rekap -> 201" 201 $anakUji.Status
$idAnakRekap = $anakUji.Body.data.id

$r = Req 'POST' "$base/kader/children/$idAnakRekap/immunizations" $tK @{ immunization_type_id = $typeHB0; date_given = $hariIni; batch_number = 'REKAP-001' }
Check "suntikan tanggal hari ini -> 201" 201 $r.Status

$countHB0 = 0
foreach ($d in (Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null).Body.data.activity.by_type) {
    if ($d.immunization_type_id -eq $typeHB0) { $countHB0 = $d.count }
}
Check "  HB0 terhitung di aktivitas bulan ini" 1 $countHB0

# Batalkan suntikannya. Aktivitas harus turun karena global scope soft delete,
# dan barisnya tetap ada di database (dicek di grup 12 lewat "sisa suntikan").
$r2 = Req 'GET' "$base/children/$idAnakRekap/immunizations" $tK $null
$idRecordRekap = $null
foreach ($d in $r2.Body.data.checklist) { if ($d.record -ne $null) { $idRecordRekap = $d.record.id } }
Check "  suntikan ada di checklist anak" $true ($idRecordRekap -ne $null)

$r3 = Req 'DELETE' "$base/kader/immunizations/$idRecordRekap" $tK $null
Check "batalkan suntikan rekap -> 200" 200 $r3.Status

$countHB0Sesudah = 0
foreach ($d in (Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null).Body.data.activity.by_type) {
    if ($d.immunization_type_id -eq $typeHB0) { $countHB0Sesudah = $d.count }
}
Check "  count HB0 turun jadi 0" 0 $countHB0Sesudah
Note "suntikan dibatalkan tidak boleh masuk rekap (soft delete)"

# Laporan historis harus reproduktif: bulan yang sama diminta dua kali
# menghasilkan angka yang sama, karena acuan waktunya akhir bulan.
$rA = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null
$rB = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null
Check "rekap dua kali -> total anak sama" $rA.Body.data.coverage.total_children $rB.Body.data.coverage.total_children
Check "  jumlah anak terlambat sama" $rA.Body.data.coverage.overdue_children.Count $rB.Body.data.coverage.overdue_children.Count
Check "  total dosis sama" $rA.Body.data.activity.total_doses $rB.Body.data.activity.total_doses

# Bulan yang tidak ada aktivitas tetap harus 200 dengan angka nol, bukan 404.
$r = Req 'GET' "$base/kader/immunizations/recap?month=2019-01" $tK $null
Check "rekap bulan kosong -> 200" 200 $r.Status
Check "  total dosis 0" 0 $r.Body.data.activity.total_doses
Check "  by_type tetap 16" 16 $r.Body.data.activity.by_type.Count
Note "kader perlu melihat 'tidak ada suntikan', bukan pesan 404"


# =====================================================================
Group "9g. Export CSV rekap (Opsi E - butir terakhir)"
# `?format=csv` memakai route yang sama dengan JSON, jadi grup ini juga
# menguji hal yang paling mahal dari fitur ini: angka di berkas CSV harus
# sama dengan angka di JSON. Kalau tidak, BIDAN menerima laporan yang
# berbeda dari yang dilihat kader di layar.
#
# BOM UTF-8 dan pemisah CRLF TIDAK diperiksa di sini. `Invoke-WebRequest`
# mendecode body dan membuang BOM sebelum skrip menyentuhnya, jadi yang
# tersisa hanyalah teks UTF-8 yang kelihatan benar. Dua hal itu diuji di
# `tests/Feature/ImmunizationRecapCsvTest.php` yang membaca respons mentah.
# =====================================================================

# Ibu tidak boleh, sama seperti JSON. File CSV adalah laporan seluruh
# Posyandu; membocorkannya lewat unduhan sama saja membocorkan lewat JSON.
$r = Req 'GET' "$base/kader/immunizations/recap?format=csv" $tA $null
Check "Ibu unduh CSV -> 403" 403 $r.Status

# Format yang tidak dikenal ditolak, bukan diam-diam diabaikan.
$r = Req 'GET' "$base/kader/immunizations/recap?format=excel" $tK $null
Check "format tak dikenal -> 422" 422 $r.Status
Check "  ada error di field format" $true ($r.Body.errors.PSObject.Properties.Name -contains 'format')

# `format=csv` tidak boleh melewati validasi bulan. Kalau lolos, kader
# mengunduh file header tanpa pesan error dan menyimpannya tanpa tahu ada
# yang salah.
$r = Req 'GET' "$base/kader/immunizations/recap?month=2026-13&format=csv" $tK $null
Check "CSV + bulan salah -> 422" 422 $r.Status
Check "  badan tetap JSON, bukan CSV" $true ($r.Raw -like '*"errors"*')
Check "  tidak ada isi laporan di badan" $false ($r.Raw -like '*AKTIVITAS SUNTIKAN*')

# Kontrak file: tipe konten dan nama unduhan.
$r = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji&format=csv" $tK $null
Check "Kader unduh CSV -> 200" 200 $r.Status
Check "  Content-Type text/csv" 'text/csv; charset=UTF-8' $r.Headers['Content-Type']
Check "  nama file ikut bulan" "attachment; filename=`"rekap-imunisasi-$bulanUji.csv`"" $r.Headers['Content-Disposition']
Note "BOM UTF-8 dan CRLF dicek di feature test, bukan di sini"

$csv = $r.Raw
Check "  ada kop bulan" $true ($csv -like "*Bulan: $bulanUji*")
Check "  ada tanggal acuan" $true ($csv -like "*Dihitung sampai: $akhirBulanUji*")
Check "  bagian aktivitas ada" $true ($csv -like '*AKTIVITAS SUNTIKAN*')
Check "  bagian kelengkapan ada" $true ($csv -like '*KELENGKAPAAN IMUNISASI*')
Check "  bagian daftar anak ada" $true ($csv -like '*DAFTAR ANAK TERLAMBAT*')

# Guard utama: angka CSV harus sama persis dengan angka JSON.
$j = (Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null).Body.data
Check "  total dosis CSV = JSON" $true ($csv -like "*TOTAL,,,$($j.activity.total_doses)*")
Check "  total anak CSV = JSON" $true ($csv -like "*Total anak,$($j.coverage.total_children)*")
Check "  anak terlambat CSV = JSON" $true ($csv -like "*Ada dosis terlambat,$($j.coverage.overdue)*")
Check "  arsip CSV = JSON" $true ($csv -like "*Tidak dihitung (arsip / pindah),$($j.coverage.excluded_archived)*")
Note "CSV dibangun dari array yang sama dengan JSON, jadi angkanya tidak mungkin beda"

# Semua 16 baris master harus muncul di file, termasuk yang count-nya 0.
$barisHilang = @()
foreach ($d in $j.activity.by_type) {
    if ($csv -notlike "*$($d.code),$($d.dose_number),$($d.label),$($d.count)*") { $barisHilang += $d.code }
}
Check "  semua 16 master dosis ada di CSV" 0 $barisHilang.Count
if ($barisHilang.Count -gt 0) { Note "hilang: $($barisHilang -join ', ')" }
Note "baris count=0 ikut ditulis, tidak disembunyikan seperti di layar"

# Jumlah baris anak terlambat di file harus sama dengan di JSON. Hitung per
# baris tabel "DAFTAR ANAK TERLAMBAT": baris yang 7 kolomnya semua terisi
# setelah kolom No.
$jumlahBarisAnak = 0
foreach ($baris in ($csv -split "`r`n")) {
    if ($baris -match '^\d+,[^,]') { $jumlahBarisAnak++ }
}
Check "  baris anak terlambat = JSON" $j.coverage.overdue_children.Count $jumlahBarisAnak
Note "satu anak = satu baris, jadi daftar kunjungan tidak kembar"

# Klien lama tidak mengirim `format`. Kontrak JSON tidak boleh bergeser.
$tanpa = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji" $tK $null
$eksplisit = Req 'GET' "$base/kader/immunizations/recap?month=$bulanUji&format=json" $tK $null
Check "tanpa format = format=json" $tanpa.Raw $eksplisit.Raw

# Bulan kosong harus tetap menghasilkan file utuh, bukan 404 atau file kosong.
$r = Req 'GET' "$base/kader/immunizations/recap?month=2019-01&format=csv" $tK $null
Check "CSV bulan kosong -> 200" 200 $r.Status
Check "  file tetap utuh" $true ($r.Raw -like '*DAFTAR ANAK TERLAMBAT*')
Check "  ada penanda tidak ada anak telat" $true ($r.Raw -like '*(tidak ada anak dengan dosis terlambat)*')



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
echo '  sisa keluhan : ' . Illuminate\Support\Facades\DB::table('medical_notes')->count() . PHP_EOL;
echo '  sisa keluhan dibatalkan: ' . Illuminate\Support\Facades\DB::table('medical_notes')->whereNotNull('deleted_at')->count() . PHP_EOL;
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
