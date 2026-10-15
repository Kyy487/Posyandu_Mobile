import 'package:flutter/material.dart';

import '../models/growth_chart.dart';
import '../services/growth_chart_service.dart';
import '../screens/login_screen.dart';
import '../utils/status_gizi.dart';
import 'growth_line_chart.dart';

/// Warna yang membedakan tampilan grafik Ibu dan Kader.
///
/// Lima warna ini satu-satunya bedanya. Seluruh isi layar - grafik, pita WHO,
/// kartu status gizi, state kosong, dan state gagal - identik untuk kedua role,
/// karena keduanya membaca endpoint dan model yang sama persis.
///
/// Kalau nanti ditambah warna, tambahkan di sini, bukan di dalam [GrowthChartView].
/// `warnaStatusGizi()` sengaja **tidak** masuk ke palet: palet ini memetakan
/// perbedaan antar role, sedangkan warna status gizi berlaku sama di semua
/// layar. Karena itu pemetaan status gizi hidup di `utils/status_gizi.dart`.
class GrowthChartPalette {
  /// Warna `AppBar`.
  final Color appBar;

  /// Warna latar `Scaffold`.
  final Color latar;

  /// Warna aksen: tombol metrik aktif, judul kartu status, spinner.
  final Color aksen;

  /// Warna teks aksen yang dipakai di atas latar putih.
  final Color warnaTeksAksen;

  /// Warna ikon pada state kosong dan state gagal.
  final Color warnaIkonKosong;

  const GrowthChartPalette({
    required this.appBar,
    required this.latar,
    required this.aksen,
    required this.warnaTeksAksen,
    required this.warnaIkonKosong,
  });

  /// Palet layar Ibu. Pink sudah jadi warna semua layar Ibu yang lain.
  static const ibu = GrowthChartPalette(
    appBar: Color(0xFFE91E63),
    latar: Color(0xFFFFF5F8),
    aksen: Color(0xFFD81B60),
    warnaTeksAksen: Color(0xFF880E4F),
    warnaIkonKosong: Color(0xFFF8BBD0),
  );

  /// Palet layar Kader. Biru `Colors.blue[800]`, sama dengan dashboard Kader,
  /// profil anak, catatan keluhan, dan imunisasi.
  static const kader = GrowthChartPalette(
    appBar: Color(0xFF1565C0),
    latar: Color(0xFFF5F7FA),
    aksen: Color(0xFF1E88E5),
    warnaTeksAksen: Color(0xFF0D47A1),
    warnaIkonKosong: Color(0xFFBBDEFB),
  );
}

/// Seluruh isi layar grafik tumbuh kembang.
///
/// Dipakai oleh Ibu dan Kader tanpa perbedaan apa pun selain [palette].
/// Bentuknya dikunci di `docs/RANCANGAN_GRAFIK_TUMBUH_KEMBANG.md` bagian 8 dan
/// 8.7; kalau perlu berubah, dokumennya yang diubah lebih dulu.
///
/// Yang read-only untuk kedua role: layar ini hanya menampilkan. Kader mencatat
/// penimbangan lewat `input_penimbangan_screen.dart`, bukan dari sini, supaya
/// tidak ada dua jalan menulis ke `measurements`.
///
/// Angka z-score, status gizi, dan umur **tidak ada yang dihitung di sini** -
/// semuanya dibaca apa adanya dari server, karena sudah dihitung trigger
/// PostgreSQL saat penimbangan dicatat.
class GrowthChartView extends StatefulWidget {
  final String childId;
  final String childName;
  final GrowthChartPalette palette;

  const GrowthChartView({
    super.key,
    required this.childId,
    required this.childName,
    this.palette = GrowthChartPalette.ibu,
  });

  @override
  State<GrowthChartView> createState() => _GrowthChartViewState();
}

class _GrowthChartViewState extends State<GrowthChartView> {
  final GrowthChartService _service = GrowthChartService();

  GrowthChart? _data;
  bool _isLoading = true;
  String? _errorMessage;

  /// Garis mana yang digambar. Sekarang benar-benar pemilih data: satu metrik
  /// per kanvas, karena IMT/U bersatuan `kg/m²` yang tidak bisa dipetakan ke
  /// kanvas kg atau cm.
  GrowthMetric _metrik = GrowthMetric.weightForAge;

  GrowthChartPalette get _warna => widget.palette;

  /// Pita WHO untuk metrik yang sedang dipilih, atau `null` kalau server tidak
  /// mengirimnya. Dicocokkan lewat `metric`, bukan label tampilan.
  WhoBandReference? get _bandAktif => _data?.bandUntuk(_metrik.metricKey);

  bool get _pitaAktifAda {
    final band = _bandAktif;
    return band != null && !band.kosong;
  }

  /// Metrik aktif punya minimal satu titik yang bisa digambar.
  bool get _metrikAktifPunyaTitik {
    final data = _data;
    if (data == null) return false;
    return data.series.points.any(
      (p) => p.umurTahun != null && _metrik.nilaiDari(p) != null,
    );
  }

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _service.getGrowthChart(widget.childId);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is GrowthChart) {
      setState(() {
        _data = result['data'] as GrowthChart;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Gagal memuat grafik tumbuh.';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _warna.latar,
      appBar: AppBar(
        backgroundColor: _warna.appBar,
        foregroundColor: Colors.white,
        title: const Text('Grafik Tumbuh'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: _warna.aksen));
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      color: _warna.aksen,
      onRefresh: _muatData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildHeader(data),
          const SizedBox(height: 16),
          if (!_pitaAktifAda) _buildPitaTidakTersedia(data),
          _buildChart(data),
          const SizedBox(height: 12),
          if (_pitaAktifAda) _buildLegend(data),
          const SizedBox(height: 20),
          _buildStatusTerakhir(data),
          const SizedBox(height: 16),
          _buildKartuMultidim(data),
        ],
      ),
    );
  }

  Widget _buildHeader(GrowthChart data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _warna.aksen.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.child_care, color: _warna.aksen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.child.name.isEmpty ? widget.childName : data.child.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Usia saat ditimbang terakhir: ${data.child.labelUmur}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tiga tombol metrik, bukan `SegmentedButton` atau `TabBar`.
  ///
  /// Grafik menggambar satu metrik per kanvas dengan satu sumbu y, jadi tombol
  /// ini benar-benar memilih data. `TabBar` tidak dipakai karena tampilannya
  /// menyiratkan halaman yang berbeda, padahal ini satu kartu yang sama.
  Widget _buildChart(GrowthChart data) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _warna.aksen.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _buildMetrikButton(
                  metrik: GrowthMetric.weightForAge,
                  unit: data.series.weightUnit,
                ),
                const SizedBox(width: 8),
                _buildMetrikButton(
                  metrik: GrowthMetric.heightForAge,
                  unit: data.series.heightUnit,
                ),
                const SizedBox(width: 8),
                _buildMetrikButton(
                  metrik: GrowthMetric.bmiForAge,
                  unit: data.series.bmiUnit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 280,
            child: data.tanpaData
                ? _buildBelumAdaData()
                : _metrikAktifPunyaTitik
                ? GrowthLineChart(
                    series: data.series,
                    whoBands: data.whoBands,
                    metrikAktif: _metrik,
                  )
                : _buildMetrikKosong(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrikButton({
    required GrowthMetric metrik,
    required String unit,
  }) {
    final aktif = _metrik == metrik;
    final warnaGaris = GrowthLineChart.warnaMetrik(metrik);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _metrik = metrik),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: aktif
                ? _warna.aksen.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: aktif ? _warna.aksen : const Color(0xFFE0E0E0),
              width: aktif ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: warnaGaris,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    metrik.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: aktif ? _warna.warnaTeksAksen : Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 10,
                  color: aktif ? _warna.aksen : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Legenda satu baris untuk pita WHO.
  ///
  /// Pengguna tidak boleh menebak artinya dari warna saja - area abu-abu tanpa
  /// keterangan akan sering dibaca sebagai "area yang salah". Teksnya sengaja
  /// generik karena pita yang digambar bisa BB/U, TB/U, atau IMT/U.
  Widget _buildLegend(GrowthChart data) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Area abu = rentang normal WHO (median -/+2 SD)',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// Catatan saat WHO tidak punya acuan untuk gender anak ini.
  ///
  /// Pita tidak diinterpolasi di sisi klien: pita yang dikarang dari dua titik
  /// akan terlihat meyakinkan tapi tidak benar.
  Widget _buildPitaTidakTersedia(GrowthChart data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Standar WHO belum tersedia untuk data ini, jadi area abu-abu '
              'tidak digambar. Garis anak tetap ditampilkan.',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Kartu status gizi terakhir.
  ///
  /// Isinya sengaja sama dengan kartu di dashboard Ibu - z-score, status, dan
  /// umur - supaya tidak ada dua definisi "status terakhir" di aplikasi yang
  /// sama. Semua angka dibaca dari server, tidak ada yang dihitung di sini.
  Widget _buildStatusTerakhir(GrowthChart data) {
    final titik = data.series.titikStatusTerakhir;
    final z = titik?.zScoreWfa;
    final status = titik?.statusGizi;

    final ({Color warna, IconData ikon}) gizi = warnaStatusGizi(status);
    final Color warna = gizi.warna;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warna.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: _warna.aksen.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_weight_outlined, color: warna, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Status Gizi - ${data.child.name.isEmpty ? widget.childName : data.child.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (titik == null)
            Text(
              'Belum ada data penimbangan. Kader akan mencatatnya '
              'saat kunjungan posyandu berikutnya.',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 13,
                height: 1.4,
              ),
            )
          else
            Row(
              children: [
                _buildStatBox(
                  label: 'Tercatat',
                  // `labelTanggal()` yang sudah dipakai timeline dan rekap,
                  // supaya tanggal penimbangan tidak tampil dengan tiga bentuk
                  // berbeda di tiga layar.
                  value: titik.labelTanggal,
                  warna: warna,
                ),
                _buildStatBox(
                  label: 'Z-Score',
                  value: z?.toStringAsFixed(2) ?? '-',
                  warna: warna,
                ),
                _buildStatBox(
                  label: 'Status',
                  value: status ?? '-',
                  warna: warna,
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Siapa yang akan mencatat penimbangan berikutnya.
  ///
  Widget _buildStatBox({
    required String label,
    required String value,
    required Color warna,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: warna,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Kartu ringkas indikator multidimensi.
  /// TB/U, IMT/U, dan BB/TB dari penimbangan terakhir yang punya salah satunya.
  ///
  /// Terpisah dari kartu BB/U di atas, karena masing-masing indikator WHO
  /// punya statusnya sendiri dan layar tidak boleh menyimpulkan satu dari yang
  /// lain. Angkanya dibaca apa adanya dari trigger; tidak ada yang dihitung di
  /// sini. Warna memakai pemetaan yang sama dengan kartu BB/U.
  Widget _buildKartuMultidim(GrowthChart data) {
    final titik = data.series.titikMultidimTerakhir;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _warna.aksen.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.straighten, color: _warna.aksen, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Indikator Pertumbuhan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (titik == null)
            const Text(
              'Belum ada data TB/U, IMT/U, atau BB/TB untuk anak ini.',
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            )
          else ...[
            _barisIndikator('TB/U - Stunting', titik.statusStunting),
            const SizedBox(height: 10),
            _barisIndikator('IMT/U', titik.statusGiziImt),
            const SizedBox(height: 10),
            // BB/TB tidak punya acuan di atas 24 bulan, jadi barisnya
            // menjelaskan itu alih-alih menampilkan "-" tanpa sebab.
            if (titik.ageInMonths != null && titik.ageInMonths! < 24)
              _barisIndikator('BB/TB', titik.statusWfh, nilaiZ: titik.zScoreWfh)
            else
              _barisIndikatorTidakBerlaku(
                'BB/TB',
                'Tidak berlaku untuk usia 24 bulan ke atas.',
              ),
          ],
        ],
      ),
    );
  }

  Widget _barisIndikator(String label, String? status, {double? nilaiZ}) {
    final teks = status ?? (nilaiZ == null ? null : 'z ${nilaiZ.toStringAsFixed(2)}');
    final warna = status == null ? Colors.grey : warnaStatusGizi(status).warna;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Expanded(
          child: Text(
            teks ?? '-',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: warna,
            ),
          ),
        ),
      ],
    );
  }

  Widget _barisIndikatorTidakBerlaku(String label, String keterangan) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ),
        Expanded(
          child: Text(
            keterangan,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------------
  // Empty state di dalam kanvas.
  /// Kartu pesan muncul di dalam area grafik, bukan menggantikannya, supaya
  /// pengguna tetap tahu tempat di mana grafiknya akan tampil begitu ada
  /// penimbangan.
  Widget _buildBelumAdaData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.child_care_outlined,
            size: 72,
            color: _warna.warnaIkonKosong,
          ),
          const SizedBox(height: 12),
          const Text(
            'Belum ada penimbangan yang tercatat',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Metrik aktif tidak punya satu titik pun untuk digambar.
  ///
  /// Terjadi misalnya saat IMT/U dipilih tapi tinggi badan belum pernah diukur,
  /// sehingga BMI semua titik `null`. Dibedakan dari [._buildBelumAdaData]:
  /// di sini anak **sudah** ditimbang, cuma metrik ini yang belum ada datanya.
  Widget _buildMetrikKosong() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.show_chart,
            size: 60,
            color: _warna.warnaIkonKosong,
          ),
          const SizedBox(height: 12),
          Text(
            'Belum ada data ${_metrik.label} yang bisa digambar',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String pesan) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: _warna.warnaIkonKosong),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat grafik',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _muatData,
              style: FilledButton.styleFrom(backgroundColor: _warna.aksen),
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
