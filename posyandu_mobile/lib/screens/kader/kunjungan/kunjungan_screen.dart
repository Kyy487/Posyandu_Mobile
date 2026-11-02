import 'package:flutter/material.dart';

import '/../../models/visit.dart';
import '/../../services/visit_service.dart';
import '/../../utils/month_label.dart';
import '/../../screens/shared/login_screen.dart';
import '/../../screens/kader/data_anak/catatan_keluhan_screen.dart';
import '/../../screens/kader/imunisasi/imunisasi_screen.dart';
import 'input_penimbangan_screen.dart';
import 'rujukan_screen.dart';

// Warna lokal layar ini, mengikuti palet desain Kader.
const Color _teal = Color(0xFF0E7C7B);
const Color _ink = Color(0xFF12302F);
const Color _muted = Color(0xFF5C7F7C);
const Color _koral = Color(0xFFF2845C);
const Color _permukaan = Color(0xFFF2F6F5);
const Color _indigo = Color(0xFF4150B8);
const Color _ungu = Color(0xFF8A3A9B);
const Color _amber = Color(0xFF9A6B00);
const Color _merah = Color(0xFFC4502A);

const _bulanSingkat = [
  'JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN',
  'JUL', 'AGU', 'SEP', 'OKT', 'NOV', 'DES',
];

/// Aksi yang dipilih kader dari lembar detail kunjungan.
enum _AksiKunjungan { ubah }

/// Jenis data yang bisa dicatat pada satu kunjungan.
///
/// Dipakai alur "buat kunjungan → input data → selesai": setelah kunjungan
/// tersimpan, kader memilih data apa yang mau dicatat, dan layar yang dibuka
/// membawa `visit_id` kunjungan itu.
enum _JenisInput { penimbangan, imunisasi, keluhan, rujukan }

/// Bentuk lembar dari bawah yang dipakai semua bottom sheet di layar ini.
const RoundedRectangleBorder _bentukLembar = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
);

/// Kunjungan satu anak: daftar, detail, dan pembuatan (Kader).
///
/// Kunjungan adalah "wadah" satu sesi layanan. Rujukan menempel pada kunjungan,
/// jadi layar ini juga yang membuat rujukan mungkin walau anak belum punya
/// kunjungan sama sekali (lihat `docs/arsip/RANCANGAN_VISIT.md`).
///
/// Tampilan baru: kartu kunjungan dengan blok tanggal dan penghitung data
/// berikon, pilihan jenis data berupa ubin berikon, dan lembar detail dan form
/// yang bergaya sama dengan layar Kader lain. Seluruh logika sama.
class KunjunganScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const KunjunganScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<KunjunganScreen> createState() => _KunjunganScreenState();
}

class _KunjunganScreenState extends State<KunjunganScreen> {
  final VisitService _service = VisitService();

  VisitList? _data;

  /// Spinner penuh hanya untuk muat pertama; muat ulang berikutnya cukup bar
  /// tipis supaya daftar tidak berkedip (penting di alur input data yang
  /// memuat ulang berkali-kali).
  bool _isLoading = true;
  bool _menyegarkan = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() {
      _errorMessage = null;
      _menyegarkan = true;
    });

    final result = await _service.getByChild(widget.childId);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is VisitList) {
      setState(() {
        _data = result['data'] as VisitList;
        _isLoading = false;
        _menyegarkan = false;
      });
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Gagal memuat daftar kunjungan.';
      _isLoading = false;
      _menyegarkan = false;
    });
  }

  /// Membuka form kunjungan. Tanpa [visit] berarti buat baru; dengan [visit]
  /// berarti koreksi.
  ///
  /// Setelah membuat kunjungan baru, lanjut ke alur input data supaya kader
  /// bisa langsung mencatat penimbangan/imunisasi/keluhan/rujukan pada
  /// kunjungan itu - itulah inti "buat kunjungan → input data → selesai".
  Future<void> _bukaForm({Visit? visit}) async {
    final hasil = await showModalBottomSheet<Visit>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: _bentukLembar,
      builder: (context) => _FormKunjungan(
        childId: widget.childId,
        childName: widget.childName,
        service: _service,
        visit: visit,
      ),
    );

    if (!mounted || hasil == null) return;

    await _muatData();

    // Hanya kunjungan BARU yang menawarkan alur. Koreksi kunjungan tidak,
    // supaya kader tidak diarahkan mencatat data setiap kali memperbaiki typo.
    if (mounted && visit == null) {
      await _tawarkanInputData(hasil);
    }
  }

  /// Menawarkan pencatatan data pada [visit] sampai kader memilih "Selesai".
  ///
  /// Diulang, bukan sekali jalan: satu kunjungan biasanya butuh lebih dari satu
  /// jenis data (timbang lalu imunisasi lalu catatan keluhan). Tiap selesai
  /// satu, jumlah data di daftar disegarkan dan pilihan muncul lagi.
  Future<void> _tawarkanInputData(Visit visit) async {
    var pilihan = await _pilihJenisInput(visit);

    while (pilihan != null && mounted) {
      await _bukaInput(pilihan, visit);

      if (!mounted) return;

      await _muatData();
      if (!mounted) return;

      pilihan = await _pilihJenisInput(visit);
    }
  }

  /// Lembar pilihan jenis data. Null berarti kader selesai/menutup lembar.
  Future<_JenisInput?> _pilihJenisInput(Visit visit) {
    return showModalBottomSheet<_JenisInput>(
      context: context,
      backgroundColor: Colors.white,
      shape: _bentukLembar,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: _pegangan()),
                const SizedBox(height: 16),
                const Text(
                  'Catat data untuk kunjungan ini',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  visit.ringkasan,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _ubinInput(
                      context,
                      _JenisInput.penimbangan,
                      Icons.monitor_weight_outlined,
                      'Penimbangan',
                      'Berat & tinggi',
                      _indigo,
                    ),
                    const SizedBox(width: 10),
                    _ubinInput(
                      context,
                      _JenisInput.imunisasi,
                      Icons.vaccines_outlined,
                      'Imunisasi',
                      'Suntikan dosis',
                      _ungu,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _ubinInput(
                      context,
                      _JenisInput.keluhan,
                      Icons.sticky_note_2_outlined,
                      'Keluhan',
                      'Demam, rewel, diare',
                      _amber,
                    ),
                    const SizedBox(width: 10),
                    _ubinInput(
                      context,
                      _JenisInput.rujukan,
                      Icons.local_hospital_outlined,
                      'Rujukan',
                      'Ke fasilitas kesehatan',
                      _merah,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Selesai'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: const BorderSide(color: _teal, width: 2),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ubinInput(
    BuildContext context,
    _JenisInput jenis,
    IconData ikon,
    String judul,
    String keterangan,
    Color warna,
  ) {
    return Expanded(
      child: Material(
        color: warna.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => Navigator.pop(context, jenis),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(ikon, size: 24, color: warna),
                ),
                const SizedBox(height: 10),
                Text(
                  judul,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  keterangan,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pegangan() {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFCFE0DD),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  /// Membuka layar input yang sesuai, membawa `visit_id` kunjungan.
  Future<void> _bukaInput(_JenisInput jenis, Visit visit) async {
    final label = visit.ringkasan;

    final Widget layar;
    switch (jenis) {
      case _JenisInput.penimbangan:
        layar = InputPenimbanganScreen(
          childId: widget.childId,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.imunisasi:
        layar = ImunisasiScreen(
          childId: widget.childId,
          childName: widget.childName,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.keluhan:
        layar = CatatanKeluhanScreen(
          childId: widget.childId,
          childName: widget.childName,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.rujukan:
        layar = RujukanScreen(
          childId: widget.childId,
          childName: widget.childName,
          initialVisitId: visit.id,
        );
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => layar),
    );
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _permukaan,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaForm(),
        backgroundColor: _koral,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Buat Kunjungan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _barAtas(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _barAtas() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Row(
          children: [
            _tombolBar(
              Icons.arrow_back_rounded,
              'Kembali',
              Colors.white,
              _ink,
              () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kunjungan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  Text(
                    widget.childName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            _tombolBar(
              Icons.refresh_rounded,
              'Muat ulang',
              _teal.withValues(alpha: 0.12),
              _teal,
              _menyegarkan ? null : _muatData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tombolBar(
    IconData ikon,
    String tooltip,
    Color latar,
    Color warnaIkon,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              ikon,
              size: 24,
              color: onTap == null ? warnaIkon.withValues(alpha: 0.4) : warnaIkon,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _data == null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
        children: [
          SizedBox(
            height: 3,
            child: _menyegarkan
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          if (data.kosong)
            _buildKosong(data)
          else ...[
            _buildRingkasan(data),
            for (final v in data.visits) _buildKartu(v),
          ],
        ],
      ),
    );
  }

  /// Ringkasan singkat di atas daftar.
  Widget _buildRingkasan(VisitList data) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _teal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(Icons.event_available, color: _teal),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data.jumlah} kunjungan tercatat',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const Text(
                    'Satu kunjungan menampung penimbangan, imunisasi, '
                    'keluhan, dan rujukan pada satu sesi layanan.',
                    style: TextStyle(fontSize: 11, color: _muted, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKosong(VisitList data) {
    final nama = data.childName.isEmpty ? widget.childName : data.childName;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.event_available, size: 60, color: _muted),
          const SizedBox(height: 16),
          const Text(
            'Belum ada kunjungan',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$nama belum punya kunjungan layanan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tekan "Buat Kunjungan" untuk mencatat kunjungan baru. Rujukan '
            'butuh kunjungan, jadi mulai dari sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: _muted, height: 1.4),
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
            const Icon(Icons.cloud_off, size: 64, color: _muted),
            const SizedBox(height: 16),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _muatData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ KARTU

  /// Blok tanggal (bulan + hari) dari teks `YYYY-MM-DD`; ikon kalender bila
  /// tanggal tidak terbaca.
  Widget _blokTanggal(String? iso, {double ukuran = 56}) {
    final d = DateTime.tryParse(iso ?? '');

    return Container(
      width: ukuran,
      height: ukuran + 6,
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: d == null
          ? const Icon(Icons.calendar_today_rounded, color: _teal)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _bulanSingkat[d.month - 1],
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _teal,
                  ),
                ),
                Text(
                  '${d.day}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: _teal,
                  ),
                ),
              ],
            ),
    );
  }

  /// Satu kartu kunjungan. Ketuk untuk membuka detail.
  Widget _buildKartu(Visit visit) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _bukaDetail(visit),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _blokTanggal(visit.visitDate),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              visit.tanggalLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: _ink,
                              ),
                            ),
                          ),
                          _buildChip(visit.tipeLabel, _teal),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: _muted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              visit.kaderName ?? 'Kader tidak diketahui',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildDataTertaut(visit),
                      if (visit.anamnesis != null &&
                          visit.anamnesis!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          visit.anamnesis!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _ink,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Penghitung data yang menempel pada kunjungan ini, berikon.
  Widget _buildDataTertaut(Visit visit) {
    if (!visit.adaDataTertaut) {
      return const Text(
        'Belum ada data tercatat pada kunjungan ini.',
        style: TextStyle(
          fontSize: 11,
          color: _muted,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (visit.jumlahPengukuran > 0)
          _penghitung(
            Icons.monitor_weight_outlined,
            visit.jumlahPengukuran,
            'timbang',
            _indigo,
          ),
        if (visit.jumlahImunisasi > 0)
          _penghitung(
            Icons.vaccines_outlined,
            visit.jumlahImunisasi,
            'imunisasi',
            _ungu,
          ),
        if (visit.jumlahKeluhan > 0)
          _penghitung(
            Icons.sticky_note_2_outlined,
            visit.jumlahKeluhan,
            'keluhan',
            _amber,
          ),
      ],
    );
  }

  Widget _penghitung(IconData ikon, int jumlah, String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 15, color: warna),
          const SizedBox(width: 5),
          Text(
            '$jumlah $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: warna,
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- DETAIL

  /// Detail lengkap satu kunjungan, dengan aksi koreksi.
  ///
  /// Data yang ditampilkan cukup yang dibawa daftar - anamnesis, catatan kader,
  /// dan jumlah data tertaut. Detail penimbangan/imunisasi/keluhan dibuka lewat
  /// layarnya masing-masing, bukan di sini.
  Future<void> _bukaDetail(Visit visit) async {
    final aksi = await showModalBottomSheet<_AksiKunjungan>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: _bentukLembar,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: _pegangan()),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _blokTanggal(visit.visitDate, ukuran: 52),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Detail Kunjungan',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            Text(
                              visit.tanggalLabel,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _tombolTutup(context),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _statDetail(
                        Icons.monitor_weight_outlined,
                        visit.jumlahPengukuran,
                        'Timbang',
                        _indigo,
                      ),
                      const SizedBox(width: 10),
                      _statDetail(
                        Icons.vaccines_outlined,
                        visit.jumlahImunisasi,
                        'Imunisasi',
                        _ungu,
                      ),
                      const SizedBox(width: 10),
                      _statDetail(
                        Icons.sticky_note_2_outlined,
                        visit.jumlahKeluhan,
                        'Keluhan',
                        _amber,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _baris(Icons.event_note_outlined, 'Jenis', visit.tipeLabel),
                  _baris(
                    Icons.person_outline_rounded,
                    'Kader',
                    visit.kaderName ?? 'Tidak diketahui',
                  ),
                  _baris(
                    Icons.chat_bubble_outline_rounded,
                    'Anamnesis',
                    visit.anamnesis?.isNotEmpty == true
                        ? visit.anamnesis!
                        : '-',
                  ),
                  _baris(
                    Icons.edit_note_rounded,
                    'Catatan Kader',
                    visit.catatanKader?.isNotEmpty == true
                        ? visit.catatanKader!
                        : '-',
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _AksiKunjungan.ubah),
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      label: const Text('Ubah'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal, width: 2),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || aksi == null) return;

    if (aksi == _AksiKunjungan.ubah) {
      await _bukaForm(visit: visit);
    }
  }

  Widget _tombolTutup(BuildContext context) {
    return Tooltip(
      message: 'Tutup',
      child: Material(
        color: _permukaan,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(),
          borderRadius: BorderRadius.circular(14),
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close_rounded, color: _ink),
          ),
        ),
      ),
    );
  }

  Widget _statDetail(IconData ikon, int jumlah, String label, Color warna) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: warna.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(ikon, size: 22, color: warna),
            const SizedBox(height: 4),
            Text(
              '$jumlah',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: warna,
              ),
            ),
            Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
    );
  }

  Widget _baris(IconData ikon, String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: _muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form kunjungan dalam bottom sheet: buat baru, atau koreksi bila [visit]
/// diisi.
///
/// `child_id` sengaja tidak bisa diubah: kunjungan yang salah anak dibatalkan
/// lalu dibuat ulang (lihat `VisitController@update`).
class _FormKunjungan extends StatefulWidget {
  final String childId;
  final String childName;
  final VisitService service;

  /// Bila tidak null, form berjalan dalam mode koreksi.
  final Visit? visit;

  const _FormKunjungan({
    required this.childId,
    required this.childName,
    required this.service,
    this.visit,
  });

  @override
  State<_FormKunjungan> createState() => _FormKunjunganState();
}

class _FormKunjunganState extends State<_FormKunjungan> {
  final _formKey = GlobalKey<FormState>();
  final _anamnesisController = TextEditingController();
  final _catatanController = TextEditingController();

  late DateTime _tanggal;
  String? _tipe = VisitTipe.posyandu;
  bool _isSaving = false;

  bool get _isEdit => widget.visit != null;

  @override
  void initState() {
    super.initState();

    if (_isEdit) {
      final v = widget.visit!;
      _tanggal = _parseTanggal(v.visitDate) ?? DateTime.now();
      _tipe = VisitTipe.semua.contains(v.visitType)
          ? v.visitType
          : VisitTipe.posyandu;
      _anamnesisController.text = v.anamnesis ?? '';
      _catatanController.text = v.catatanKader ?? '';
      return;
    }

    _tanggal = DateTime.now();
  }

  @override
  void dispose() {
    _anamnesisController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  /// Membaca tanggal `YYYY-MM-DD` dari server. Tanggal rusak/kosong dianggap
  /// tidak ada supaya form jatuh ke hari ini, bukan crash.
  DateTime? _parseTanggal(String? nilai) {
    if (nilai == null || nilai.trim().isEmpty) return null;
    return DateTime.tryParse(nilai);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final anamnesis = _anamnesisController.text.trim();
    final catatan = _catatanController.text.trim();

    final result = _isEdit
        ? await widget.service.update(
            visitId: widget.visit!.id,
            visitDate: tanggal,
            visitType: _tipe,
            anamnesis: anamnesis,
            catatanKader: catatan,
          )
        : await widget.service.create(
            childId: widget.childId,
            visitDate: tanggal,
            visitType: _tipe ?? VisitTipe.posyandu,
            anamnesis: anamnesis,
            catatanKader: catatan,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit
                    ? 'Kunjungan berhasil diperbarui.'
                    : 'Kunjungan berhasil disimpan.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      // Kembalikan kunjungan hasil simpan supaya layar bisa menawarkan input
      // data yang menempel padanya.
      Navigator.of(context).pop(result['data'] as Visit?);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_pesanError(result)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Menggabungkan pesan utama dengan detail validasi per field dari Laravel.
  String _pesanError(Map<String, dynamic> result) {
    var pesan = result['message']?.toString() ?? 'Gagal menyimpan kunjungan.';
    final errors = result['errors'];

    if (errors is Map) {
      final detail = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
      if (detail.isNotEmpty) pesan = '$pesan\n$detail';
    }

    return pesan;
  }

  InputDecoration _dekor(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: _permukaan,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  IconData _ikonTipe(String tipe) {
    final t = VisitTipe.label(tipe).toLowerCase();
    if (t.contains('rumah')) return Icons.home_outlined;
    if (t.contains('puskesmas')) return Icons.local_hospital_outlined;
    if (t.contains('posyandu')) return Icons.groups_rounded;
    return Icons.event_note_outlined;
  }

  Widget _pilihTipe(String tipe) {
    final aktif = _tipe == tipe;

    return Material(
      color: aktif ? _teal : _permukaan,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: _isSaving ? null : () => setState(() => _tipe = tipe),
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _ikonTipe(tipe),
                size: 18,
                color: aktif ? Colors.white : _muted,
              ),
              const SizedBox(width: 6),
              Text(
                VisitTipe.label(tipe),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: aktif ? Colors.white : _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFE0DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.event_available,
                      size: 28,
                      color: _teal,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEdit ? 'Koreksi Kunjungan' : 'Buat Kunjungan',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        Text(
                          widget.childName,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: 'Tutup',
                    child: Material(
                      color: _permukaan,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(14),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.close_rounded, color: _ink),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Material(
                color: _permukaan,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _isSaving ? null : _pickDate,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: _amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tanggal kunjungan',
                                style: TextStyle(fontSize: 12, color: _muted),
                              ),
                              Text(
                                labelTanggal(
                                  _tanggal.toIso8601String().substring(0, 10),
                                ),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                              const Text(
                                'Tidak boleh melebihi hari ini',
                                style: TextStyle(fontSize: 10.5, color: _muted),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Ubah',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Text(
                'Jenis kunjungan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final tipe in VisitTipe.semua) _pilihTipe(tipe)],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _anamnesisController,
                maxLines: 3,
                maxLength: 2000,
                decoration: _dekor(
                  'Anamnesis (opsional)',
                  'Contoh: Ibu melaporkan anak demam sejak 2 hari.',
                ),
              ),
              const SizedBox(height: 4),

              TextFormField(
                controller: _catatanController,
                maxLines: 3,
                maxLength: 2000,
                decoration: _dekor(
                  'Catatan Kader (opsional)',
                  'Contoh: Diarahkan kembali bulan depan.',
                ),
              ),
              const SizedBox(height: 16),

              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _koral.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _simpan,
                    style: FilledButton.styleFrom(
                      backgroundColor: _koral,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _isEdit ? 'Simpan Perubahan' : 'Simpan Kunjungan',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}