import 'package:flutter/material.dart';

import '/../../models/child.dart';
import '/../../models/child_timeline.dart';
import '/../../models/measurement_model.dart';
import '/../../models/medical_note.dart';
import '/../../services/child_timeline_service.dart';
import '/../../services/kader_service.dart';
import '/../../utils/month_label.dart';
import '/../../utils/status_gizi.dart';
import '/../../screens/shared/login_screen.dart';
import '/../../screens/shared/consent_screen.dart';
import 'catatan_keluhan_screen.dart';
import 'edit_child_screen.dart';
import 'grafik_tumbuh_screen.dart';
import '/../../screens/kader/imunisasi/imunisasi_screen.dart';
import '/../../screens/kader/kunjungan/input_penimbangan_screen.dart';
import '/../../screens/kader/kunjungan/kunjungan_screen.dart';
import '/../../screens/kader/kunjungan/rujukan_screen.dart';

class DetailAnakScreen extends StatefulWidget {
  final Child childData; // Menerima data anak dari Dashboard

  const DetailAnakScreen({super.key, required this.childData});

  @override
  State<DetailAnakScreen> createState() => _DetailAnakScreenState();
}

class _DetailAnakScreenState extends State<DetailAnakScreen> {
  final KaderService _kaderService = KaderService();
  final ChildTimelineService _timelineService = ChildTimelineService();

  /// Penanda perubahan data. Halaman riwayat/linimasa yang dibuka dari ikon
  /// mendengarkan ini supaya ikut berubah setelah edit, batalkan, atau muat
  /// ulang - karena halaman itu tidak ikut dibangun ulang oleh setState induk.
  final ValueNotifier<int> _versi = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _versi.value++;
  }

  @override
  void dispose() {
    _versi.dispose();
    super.dispose();
  }

  /// Salinan lokal data anak, bukan `widget.childData` langsung.
  ///
  /// Setelah form edit disimpan, seluruh layar ini harus langsung mengikuti
  /// nilai baru. `widget.childData` datang dari dashboard dan tidak berubah
  /// selama layar ini terbuka, jadi tanpa salinan ini kadernya masih melihat
  /// nama lama sampai menekan back.
  late Child _anak = widget.childData;

  List<MeasurementModel> _riwayat = [];
  bool _isLoading = true;

  // Riwayat medis gabungan (Opsi B). Dipisah dari `_riwayat` karena sumbernya
  // berbeda: penimbangan untuk statistik, timeline untuk buku medis. Yang
  // tampil di timeline dibaca apa adanya dari server - tidak ada z-score atau
  // status gizi yang dihitung di layar ini.
  ChildTimeline? _timeline;
  bool _timelineMemuat = false;
  String? _timelineGalat;
  bool _memuatHalamanBerikutnya = false;

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
    _loadTimeline();
  }

  /// Membuka form edit dan menjalankan perubahan bila kader menyimpannya.
  ///
  /// Form mengembalikan [Child] yang sudah diperbarui, jadi layar ini cukup
  /// menukar salinan lokalnya - tidak perlu fetch ulang seluruh daftar anak.
  Future<void> _bukaEditAnak() async {
    final hasil = await Navigator.of(context).push<Child>(
      MaterialPageRoute(builder: (_) => EditChildScreen(child: _anak)),
    );
    if (hasil == null || !mounted) return;

    setState(() => _anak = hasil);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Data ${hasil.name} berhasil diperbarui.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Membuka form koreksi penimbangan, lalu memuat ulang bila tersimpan.
  ///
  /// Z-score & status gizi dihitung ulang di server, jadi kartu riwayat,
  /// statistik "Penimbangan Terakhir", dan buku medis wajib ditarik ulang -
  /// tidak cukup hanya mengganti teks di layar.
  Future<void> _bukaEditPenimbangan(MeasurementModel m) async {
    final hasil = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InputPenimbanganScreen(childId: _anak.id, existing: m),
      ),
    );
    if (hasil != true || !mounted) return;

    await _muatUlangSemua();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Data penimbangan berhasil diperbarui.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Konfirmasi kader lalu batalkan (soft delete) satu penimbangan.
  ///
  /// Penghapusan tidak permanen: baris tetap ada dengan `deleted_at` terisi,
  /// sehingga satu anak boleh ditimbang ulang pada tanggal yang sama setelah
  /// salah input - aturan yang sama dengan "salah pilih dosis" di imunisasi.
  Future<void> _hapusPenimbangan(MeasurementModel m) async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan penimbangan?'),
        content: Text(
          'Penimbangan ${_formatTanggal(m.measurementDate)} '
          '(${m.weightKg} kg · ${m.heightCm} cm) akan dibatalkan. '
          'Riwayat, buku medis, dan grafik ikut diperbarui.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Batalkan', style: TextStyle(color: Colors.red[700])),
          ),
        ],
      ),
    );
    if (setuju != true || !mounted) return;

    final berhasil = await _kaderService.deleteMeasurement(m.id);
    if (!mounted) return;

    if (!berhasil) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal membatalkan penimbangan.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Penimbangan berhasil dibatalkan.'),
        backgroundColor: Colors.green,
      ),
    );
    await _muatUlangSemua();
  }

  // Mengambil riwayat penimbangan anak ini dari API
  Future<void> _loadRiwayat() async {
    setState(() => _isLoading = true);
    try {
      final raw = await _kaderService.getMeasurements(_anak.id);
      final parsed = raw
          .whereType<Map<String, dynamic>>()
          .map((e) => MeasurementModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted) {
        setState(() {
          _riwayat = parsed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat riwayat: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Mengambil halaman pertama timeline. Cursor dikosongkan supaya tombol
  // "Muat lebih banyak" yang sempat ditekan tidak mencegah muat ulang manual
  // dari melihat perubahan yang baru saja dicatat.
  Future<void> _loadTimeline() async {
    if (mounted) {
      setState(() {
        _timelineMemuat = true;
        _timelineGalat = null;
      });
    }

    final hasil = await _timelineService.getTimeline(_anak.id);

    if (!mounted) return;

    if (hasil['success'] == true) {
      setState(() {
        _timeline = hasil['data'] as ChildTimeline;
        _timelineMemuat = false;
      });
    } else {
      setState(() {
        _timelineMemuat = false;
        _timelineGalat =
            hasil['message']?.toString() ?? 'Gagal memuat riwayat medis.';
      });
    }
  }

  // Muat halaman berikutnya memakai cursor dari server. Cursor tidak dikarang
  // dari tanggal entri terakhir: satu hari meleset akan membuat satu kunjungan
  // hilang atau tampil dua kali.
  Future<void> _loadHalamanBerikutnya() async {
    final cursor = _timeline?.meta.cursorValid;
    if (cursor == null || _memuatHalamanBerikutnya) return;

    setState(() => _memuatHalamanBerikutnya = true);

    final hasil = await _timelineService.getTimeline(_anak.id, before: cursor);

    if (!mounted) return;

    setState(() {
      _memuatHalamanBerikutnya = false;

      if (hasil['success'] == true) {
        _timeline = _timeline?.gabung(hasil['data'] as ChildTimeline);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasil['message']?.toString() ?? 'Gagal memuat riwayat lama.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  // Muat ulang kedua sumber sekaligus. Dipakai tombol refresh yang sudah ada
  // di baris "Penimbangan Terakhir" dan setelah penimbangan baru disimpan, jadi
  // buku medis selalu punya kunjungan yang sama dengan statistik di atasnya.
  Future<void> _muatUlangSemua() async {
    await Future.wait([_loadRiwayat(), _loadTimeline()]);
  }

  // Fungsi bantuan untuk menghitung umur berdasarkan tanggal lahir
  String _hitungUmur(String tglLahir) {
    try {
      DateTime dob = DateTime.parse(tglLahir);
      DateTime now = DateTime.now();
      int years = now.year - dob.year;
      int months = now.month - dob.month;
      if (months < 0) {
        years--;
        months += 12;
      }
      return '$years Tahun, $months Bulan';
    } catch (e) {
      return '-';
    }
  }

  // Format YYYY-MM-DD menjadi "15 Agustus 2026"
  String _formatTanggal(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      const bulan = [
        'Januari',
        'Februari',
        'Maret',
        'April',
        'Mei',
        'Juni',
        'Juli',
        'Agustus',
        'September',
        'Oktober',
        'November',
        'Desember',
      ];
      return '${d.day} ${bulan[d.month - 1]} ${d.year}';
    } catch (e) {
      return isoDate;
    }
  }

  MeasurementModel? get _terakhir => _riwayat.isEmpty ? null : _riwayat.first;

  /// Penanda kondisi khusus anak, diambil dari sumber yang paling segar.
  ///
  /// Timeline lebih dulu karena dikirim sebagai bagian dari respons buku medis;
  /// kalau timeline belum selesai dimuat, teks dari daftar anak di dashboard
  /// tetap dipakai supaya badge tidak ikut hilang-ganti setiap kali layar dibuka.
  String? get _kondisiKhusus {
    final teks = _timeline?.child.medicalFlags;
    return (teks != null && teks.isNotEmpty) ? teks : _anak.medicalFlags;
  }

  /// Badge penanda kondisi khusus.
  ///
  /// Warnanya merah kalau teksnya menyebut alergi, kuning selain itu. Teksnya
  /// ditampilkan apa adanya karena daftar jenis kondisi tidak dikunci database -
  /// memecah dan menebak arti tiap baris hanya membuka pintu ke tebakan yang
  /// salah, sedangkan kader yang menulisnya adalah orang yang paling tahu
  /// maksudnya.
  Widget _buildBadgeKondisiKhusus(String teks) {
    final warna = TimelineChild.menyebutAlergi(teks)
        ? Colors.red
        : Colors.amber[800] ?? Colors.amber;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warna.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.healing_outlined, size: 16, color: warna),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              teks,
              style: TextStyle(fontSize: 12, color: warna, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== TAMPILAN BARU (Profil Medis) =====================

  static const Color _teal = Color(0xFF0E7C7B);
  static const Color _ink = Color(0xFF12302F);
  static const Color _muted = Color(0xFF5C7F7C);
  static const Color _koral = Color(0xFFF2845C);
  static const Color _permukaan = Color(0xFFF2F6F5);

  Widget _kartu({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Membuka form input penimbangan; muat ulang semuanya bila tersimpan.
  Future<void> _catatPenimbangan() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => InputPenimbanganScreen(childId: _anak.id),
      ),
    );
    // Muat ulang riwayat agar Z-Score & Status Gizi ter-update otomatis,
    // sekalian timeline supaya kunjungan barunya langsung terlihat.
    if (saved == true) {
      _muatUlangSemua();
    }
  }

  void _buka(Widget layar) {
    Navigator.push(context, MaterialPageRoute(builder: (context) => layar));
  }

  void _bukaHalamanDalam(String judul, Widget Function() bangun) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _HalamanDalam(
          judul: judul,
          versi: _versi,
          onRefresh: _muatUlangSemua,
          bangun: bangun,
          tombolBawah: _tombolCatat(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final terakhir = _terakhir;

    return Scaffold(
      backgroundColor: _permukaan,
      bottomNavigationBar: _tombolCatat(),
      body: Column(
        children: [
          _BarAtas(
            judul: 'Profil Medis',
            aksiIkon: Icons.edit_outlined,
            aksiTooltip: 'Edit Data Anak',
            onAksi: _bukaEditAnak,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _muatUlangSemua,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _kartuIdentitas(),
                  const SizedBox(height: 14),
                  _kartuRingkasan(terakhir),
                  const SizedBox(height: 24),
                  const Text(
                    'Riwayat & layanan',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _gridLayanan(),
                  if (terakhir != null) ...[
                    const SizedBox(height: 22),
                    _kartuTerakhir(terakhir),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tombolCatat() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: DecoratedBox(
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
            width: double.infinity,
            height: 58,
            child: FilledButton.icon(
              onPressed: _catatPenimbangan,
              icon: const Icon(Icons.monitor_weight_outlined, size: 24),
              label: const Text('Catat Penimbangan'),
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
            ),
          ),
        ),
      ),
    );
  }

  // ---- identitas
  Widget _kartuIdentitas() {
    final ibu = '${_anak.parentName}'.trim();
    final adaIbu = ibu.isNotEmpty && ibu != 'null';

    return _kartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0E7C7B), Color(0xFF14A39A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  _anak.name.isNotEmpty ? _anak.name[0].toUpperCase() : 'A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _anak.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'NIK: ${_anak.nik}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chipInfo(
                          Icons.schedule_rounded,
                          _hitungUmur(_anak.dateOfBirth ?? ''),
                        ),
                        if (adaIbu)
                          _chipInfo(Icons.family_restroom_rounded, 'Ibu $ibu'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_kondisiKhusus != null) ...[
            const SizedBox(height: 12),
            _buildBadgeKondisiKhusus(_kondisiKhusus!),
          ],
        ],
      ),
    );
  }

  Widget _chipInfo(IconData ikon, String teks) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: _teal),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              teks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- ringkasan penimbangan terakhir
  Widget _kartuRingkasan(MeasurementModel? terakhir) {
    if (_isLoading) {
      return _kartu(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (terakhir == null) {
      return _kartu(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: const Column(
          children: [
            Icon(Icons.monitor_weight_outlined, size: 40, color: _muted),
            SizedBox(height: 8),
            Text(
              'Belum ada data penimbangan.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              'Tekan "Catat Penimbangan" di bawah untuk mencatat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    final warnaStatus = warnaStatusGizi(terakhir.statusGizi).warna;
    final double? z = terakhir.zScoreWfa?.toDouble();

    return _kartu(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _metrik(
                  Icons.monitor_weight_outlined,
                  const Color(0xFF2F7DE1),
                  '${terakhir.weightKg} kg',
                  'Berat',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metrik(
                  Icons.straighten_rounded,
                  const Color(0xFF8A3A9B),
                  '${terakhir.heightCm} cm',
                  'Tinggi',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metrik(
                  Icons.check_circle_outline_rounded,
                  warnaStatus,
                  terakhir.statusGizi ?? '-',
                  'Status gizi',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Z-Score BB/U',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              Text(
                z?.toStringAsFixed(2) ?? '-',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: warnaStatus,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _GaugeZ(z: z),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-3', style: TextStyle(fontSize: 10, color: _muted)),
              Text('0', style: TextStyle(fontSize: 10, color: _muted)),
              Text('+3', style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Umur saat ditimbang: ${terakhir.ageInMonths ?? '-'} bulan · '
            'Standar WHO 2006',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _metrik(IconData ikon, Color warna, String nilai, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(ikon, size: 22, color: warna),
          const SizedBox(height: 4),
          Text(
            nilai,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: warna,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
        ],
      ),
    );
  }

  // ---- grid ikon layanan
  Widget _gridLayanan() {
    final jumlahKunjungan = _timeline?.jumlahKunjungan;

    final daftar = <_Layanan>[
      _Layanan(
        ikon: Icons.show_chart_rounded,
        label: 'Grafik',
        warna: _teal,
        onTap: () => _buka(
          GrafikTumbuhScreen(childId: _anak.id, childName: _anak.name),
        ),
      ),
      _Layanan(
        ikon: Icons.monitor_weight_outlined,
        label: 'Timbang',
        warna: const Color(0xFF4150B8),
        badge: _riwayat.isEmpty ? null : '${_riwayat.length}',
        onTap: () => _bukaHalamanDalam('Riwayat Timbang', _isiRiwayatTimbang),
      ),
      _Layanan(
        ikon: Icons.vaccines_outlined,
        label: 'Imunisasi',
        warna: const Color(0xFF8A3A9B),
        onTap: () =>
            _buka(ImunisasiScreen(childId: _anak.id, childName: _anak.name)),
      ),
      _Layanan(
        ikon: Icons.sticky_note_2_outlined,
        label: 'Keluhan',
        warna: const Color(0xFF9A6B00),
        onTap: () => _buka(
          CatatanKeluhanScreen(childId: _anak.id, childName: _anak.name),
        ),
      ),
      _Layanan(
        ikon: Icons.assignment_outlined,
        label: 'Kunjungan',
        warna: const Color(0xFF2E7D3A),
        onTap: () =>
            _buka(KunjunganScreen(childId: _anak.id, childName: _anak.name)),
      ),
      _Layanan(
        ikon: Icons.local_hospital_outlined,
        label: 'Rujukan',
        warna: const Color(0xFFC4502A),
        onTap: () =>
            _buka(RujukanScreen(childId: _anak.id, childName: _anak.name)),
      ),
      _Layanan(
        ikon: Icons.lock_outline_rounded,
        label: 'Persetujuan',
        warna: _ink,
        // Kader hanya melihat status persetujuan; memberi/mencabut khusus
        // Ibu/wali, jadi layar dibuka tanpa tombol pengelola.
        onTap: () =>
            _buka(ConsentScreen(childId: _anak.id, childName: _anak.name)),
      ),
      _Layanan(
        ikon: Icons.history_rounded,
        label: 'Linimasa',
        warna: const Color(0xFF2563A8),
        badge: (jumlahKunjungan == null || '$jumlahKunjungan' == '0')
            ? null
            : '$jumlahKunjungan',
        onTap: () => _bukaHalamanDalam('Linimasa', _isiLinimasa),
      ),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 0,
      childAspectRatio: 0.92,
      children: daftar.map((l) => _TileLayanan(layanan: l)).toList(),
    );
  }

  Widget _kartuTerakhir(MeasurementModel m) {
    return GestureDetector(
      onTap: () => _bukaHalamanDalam('Riwayat Timbang', _isiRiwayatTimbang),
      child: _kartu(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF4150B8).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.monitor_weight_outlined,
                size: 22,
                color: Color(0xFF4150B8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Terakhir dicatat',
                    style: TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Penimbangan · ${_formatTanggal(m.measurementDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted),
          ],
        ),
      ),
    );
  }

  // ---- isi halaman dalam: Riwayat Timbang
  Widget _isiRiwayatTimbang() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_riwayat.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(
              child: Text(
                'Belum ada riwayat penimbangan.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          )
        else ...[
          _kartuTren(),
          const SizedBox(height: 14),
          for (var index = 0; index < _riwayat.length; index++)
            _kartuRiwayat(index),
        ],
      ],
    );
  }

  Widget _kartuRiwayat(int index) {
    final m = _riwayat[index];
    return _buildHistoryCard(
      date: _formatTanggal(m.measurementDate),
      bb: '${m.weightKg} kg',
      tb: '${m.heightCm} cm',
      zScore: m.zScoreWfa?.toStringAsFixed(2) ?? '-',
      statusGizi: m.statusGizi,
      warnaStatus: warnaStatusGizi(m.statusGizi).warna,
      isLatest: index == 0,
      onEdit: () => _bukaEditPenimbangan(m),
      onBatalkan: () => _hapusPenimbangan(m),
    );
  }

  Widget _kartuTren() {
    // `_riwayat` terurut terbaru dulu; grafik butuh yang terlama di kiri.
    final nilai = _riwayat
        .take(10)
        .map((m) => double.tryParse('${m.weightKg}'))
        .whereType<double>()
        .toList()
        .reversed
        .toList();

    String? selisih;
    if (_riwayat.length >= 2) {
      final baru = double.tryParse('${_riwayat[0].weightKg}');
      final lama = double.tryParse('${_riwayat[1].weightKg}');
      if (baru != null && lama != null) {
        final d = baru - lama;
        selisih = d == 0
            ? 'Tetap'
            : '${d > 0 ? '+' : '-'}${d.abs().toStringAsFixed(1)} kg';
      }
    }

    return _kartu(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.show_chart_rounded, size: 20, color: _teal),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tren berat badan',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              if (selisih != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    selisih,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: _teal,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            width: double.infinity,
            child: CustomPaint(painter: _TrenPainter(nilai, _teal)),
          ),
          const SizedBox(height: 4),
          Text(
            '${_riwayat.length} penimbangan tercatat',
            style: const TextStyle(fontSize: 11.5, color: _muted),
          ),
        ],
      ),
    );
  }

  // ---- isi halaman dalam: Linimasa (buku medis apa adanya)
  Widget _isiLinimasa() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [_buildTimeline()],
    );
  }

  // ==================== BUKU MEDIS (Opsi B) ====================

  /// Section 5: Buku Medis — timeline per tanggal kunjungan.
  ///
  /// Dikelompokkan per bulan memakai `labelBulan()` supaya konsisten dengan
  /// layar lain. Di dalam satu tanggal, urutannya: penimbangan, suntikan,
  /// keluhan. Tanggal dengan keluhan tapi tanpa penimbangan tetap tampil.
  Widget _buildTimeline() {
    final timeline = _timeline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '\u{1F4D6} Buku Medis Anak',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            if (timeline != null)
              Text(
                '${timeline.jumlahKunjungan} kunjungan',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Riwayat lengkap per tanggal kunjungan: penimbangan, suntikan, '
          'keluhan, dan rujukan.',
          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.3),
        ),
        const SizedBox(height: 12),

        if (_timelineMemuat)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_timelineGalat != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.error_outline, color: Colors.red[400], size: 32),
                const SizedBox(height: 8),
                Text(
                  _timelineGalat!,
                  style: TextStyle(color: Colors.red[700], fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _loadTimeline,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Coba lagi'),
                ),
              ],
            ),
          )
        else if (timeline == null || timeline.kosong)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: const Column(
              children: [
                Icon(Icons.menu_book_outlined, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'Belum ada riwayat medis.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                SizedBox(height: 4),
                Text(
                  'Catat penimbangan, suntikan, atau keluhan untuk memulai buku medis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          )
        else ...[
          for (final grup in timeline.perBulan.entries) ...[
            _buildBulanHeader(grup.key, grup.value.length),
            for (final entry in grup.value) _buildTimelineEntry(entry),
          ],
          if (timeline.meta.cursorValid != null) ...[
            const SizedBox(height: 12),
            _buildTombolMuatLebihBanyak(),
          ],
        ],
      ],
    );
  }

  /// Header grup bulan, mis. "September 2026 · 3 kunjungan".
  Widget _buildBulanHeader(String bulan, int jumlah) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Text(
              labelBulan(bulan, saatKosong: 'Tanpa bulan'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$jumlah kunjungan',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// Satu kartu timeline per tanggal kunjungan.
  ///
  /// Urutan isi: penimbangan, suntikan, keluhan. Tanggal tanpa penimbangan
  /// tetap tampil dengan catatan visual bahwa penimbangan tidak ada.
  Widget _buildTimelineEntry(TimelineEntry entry) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header tanggal
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.calendar_today,
                    size: 14,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.tanggalLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 1. Penimbangan
            if (entry.adaPenimbangan)
              _buildBagianPenimbangan(entry.measurement!)
            else
              _buildBagianKosongPenimbangan(),

            // 2. Suntikan
            if (entry.adaSuntikan) ...[
              const SizedBox(height: 8),
              _buildBagianSuntikan(entry.immunizations),
            ],

            // 3. Keluhan
            if (entry.adaKeluhan) ...[
              const SizedBox(height: 8),
              _buildBagianKeluhan(entry.medicalNote!),
            ],

            // 4. Rujukan
            if (entry.adaRujukan) ...[
              const SizedBox(height: 8),
              _buildBagianRujukan(entry.referrals),
            ],
          ],
        ),
      ),
    );
  }

  /// Baris rujukan pada satu tanggal kunjungan.
  ///
  /// Satu tanggal boleh punya lebih dari satu rujukan, jadi tiap rujukan
  /// ditampilkan sebagai baris tersendiri. Rujukan yang belum selesai diberi
  /// warna merah supaya menonjol di buku medis, sementara yang sudah selesai
  /// hijau.
  Widget _buildBagianRujukan(List<TimelineReferral> rujukan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_hospital_outlined, size: 16, color: Colors.red[700]),
              const SizedBox(width: 6),
              const Text(
                'Rujukan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          for (final r in rujukan) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.facilityName?.isNotEmpty == true
                            ? r.facilityName!
                            : r.tipeLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.tipeLabel,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      if (r.reason != null && r.reason!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          r.reason!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[700],
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (r.selesai ? Colors.green[700] : Colors.red[700])!
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: r.selesai
                          ? Colors.green[700]
                          : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Baris penimbangan: BB, TB, z-score, status gizi, kader.
  Widget _buildBagianPenimbangan(TimelineMeasurement m) {
    final warna = warnaStatusGizi(m.statusGizi).warna;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_weight, size: 16, color: warna),
              const SizedBox(width: 6),
              const Text(
                'Penimbangan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (m.kaderName != null)
                Text(
                  'oleh ${m.kaderName}',
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMiniStat(
                'BB',
                '${m.weightKg?.toStringAsFixed(1) ?? '-'} kg',
              ),
              const SizedBox(width: 16),
              _buildMiniStat(
                'TB',
                '${m.heightCm?.toStringAsFixed(1) ?? '-'} cm',
              ),
              const SizedBox(width: 16),
              _buildMiniStat('Z-Score', m.labelZScore),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              m.labelStatus,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: warna,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Catatan visual bahwa tanggal ini tidak ada penimbangan.
  Widget _buildBagianKosongPenimbangan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.monitor_weight_outlined,
            size: 14,
            color: Colors.grey[400],
          ),
          const SizedBox(width: 6),
          Text(
            'Tidak ada penimbangan',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Baris suntikan: chip per kode dosis.
  Widget _buildBagianSuntikan(List<TimelineImmunization> suntikan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.vaccines, size: 16, color: Colors.teal[700]),
              const SizedBox(width: 6),
              const Text(
                'Suntikan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in suntikan)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    s.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[800],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Baris keluhan: chips + catatan + tindak lanjut.
  Widget _buildBagianKeluhan(TimelineNote note) {
    final warna = note.perluRujukan
        ? Colors.red
        : Colors.orange[700] ?? Colors.orange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: warna.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, size: 16, color: warna),
              const SizedBox(width: 6),
              const Text(
                'Keluhan',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (note.tindakLanjut != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: warna.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    TindakLanjut.label(note.tindakLanjut),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: warna,
                    ),
                  ),
                ),
            ],
          ),
          if (note.keluhan.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in note.keluhan)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      k,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: warna,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (note.catatan != null && note.catatan!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note.catatan!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tombol "Muat lebih banyak" untuk pagination.
  ///
  /// Hanya muncul kalau server bilang masih ada halaman berikutnya
  /// (`meta.has_more` + `meta.next_before`). Cursor tidak dikarang dari
  /// tanggal entri terakhir.
  Widget _buildTombolMuatLebihBanyak() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _memuatHalamanBerikutnya ? null : _loadHalamanBerikutnya,
        icon: _memuatHalamanBerikutnya
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more, size: 18),
        label: Text(
          _memuatHalamanBerikutnya ? 'Memuat...' : 'Muat lebih banyak',
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// Stat kecil di dalam kartu penimbangan.
  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  // Widget Bantuan: Kartu Statistik
  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Menu aksi per baris riwayat: koreksi dan pembatalan penimbangan.
  ///
  /// Dipakai menu popup alih-alih dua ikon bersebelahan supaya tidak
  /// menambah tinggi kartu dan tetap punya label yang jelas.
  Widget _menuAksiPenimbangan(VoidCallback? onEdit, VoidCallback? onBatalkan) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi penimbangan',
      onSelected: (nilai) {
        if (nilai == 'edit') onEdit?.call();
        if (nilai == 'batalkan') onBatalkan?.call();
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
        if (onBatalkan != null)
          PopupMenuItem(
            value: 'batalkan',
            child: Text('Batalkan', style: TextStyle(color: Colors.red[700])),
          ),
      ],
    );
  }

  // Widget Bantuan: Kartu Riwayat Timeline
  Widget _buildHistoryCard({
    required String date,
    required String bb,
    required String tb,
    required String zScore,
    required String? statusGizi,
    required Color warnaStatus,
    required bool isLatest,
    VoidCallback? onEdit,
    VoidCallback? onBatalkan,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isLatest ? warnaStatus : Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: warnaStatus.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.monitor_weight,
                    color: warnaStatus,
                    size: 20,
                  ),
                ),
                Container(height: 45, width: 2, color: Colors.grey[100]),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          date,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLatest)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: warnaStatus.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'TERAKHIR',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      if (onEdit != null || onBatalkan != null)
                        _menuAksiPenimbangan(onEdit, onBatalkan),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.monitor_weight,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        bb,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.height, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        tb,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: warnaStatus.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: warnaStatus.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calculate, size: 14, color: warnaStatus),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Z-Score: $zScore  ·  ${statusGizi ?? 'Di luar rentang WHO'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: warnaStatus,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ======================= WIDGET PENDUKUNG TAMPILAN BARU =====================

/// Bar atas: tombol kembali kotak putih, judul, satu tombol aksi opsional.
class _BarAtas extends StatelessWidget {
  final String judul;
  final IconData? aksiIkon;
  final String? aksiTooltip;
  final VoidCallback? onAksi;

  const _BarAtas({
    required this.judul,
    this.aksiIkon,
    this.aksiTooltip,
    this.onAksi,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Row(
          children: [
            _tombol(
              Icons.arrow_back_rounded,
              'Kembali',
              Colors.white,
              const Color(0xFF12302F),
              () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                judul,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF12302F),
                ),
              ),
            ),
            if (aksiIkon != null && onAksi != null)
              _tombol(
                aksiIkon!,
                aksiTooltip ?? '',
                const Color(0xFF0E7C7B).withValues(alpha: 0.12),
                const Color(0xFF0E7C7B),
                onAksi!,
              ),
          ],
        ),
      ),
    );
  }

  Widget _tombol(
    IconData ikon,
    String tooltip,
    Color latar,
    Color warnaIkon,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(ikon, color: warnaIkon, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Halaman dalam (Riwayat Timbang / Linimasa). Isinya dibangun oleh induk dan
/// dibangun ulang tiap [versi] berubah, jadi edit, batalkan, dan muat ulang
/// langsung terlihat tanpa menutup halaman.
class _HalamanDalam extends StatelessWidget {
  final String judul;
  final ValueNotifier<int> versi;
  final Future<void> Function() onRefresh;
  final Widget Function() bangun;
  final Widget? tombolBawah;

  const _HalamanDalam({
    required this.judul,
    required this.versi,
    required this.onRefresh,
    required this.bangun,
    this.tombolBawah,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      bottomNavigationBar: tombolBawah,
      body: Column(
        children: [
          _BarAtas(judul: judul),
          Expanded(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: ValueListenableBuilder<int>(
                valueListenable: versi,
                builder: (context, _, __) => bangun(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Data satu ikon pada grid "Riwayat & layanan".
class _Layanan {
  final IconData ikon;
  final String label;
  final Color warna;
  final String? badge;
  final VoidCallback onTap;

  const _Layanan({
    required this.ikon,
    required this.label,
    required this.warna,
    required this.onTap,
    this.badge,
  });
}

class _TileLayanan extends StatelessWidget {
  final _Layanan layanan;

  const _TileLayanan({required this.layanan});

  @override
  Widget build(BuildContext context) {
    final l = layanan;

    return InkWell(
      onTap: l.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: l.warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(l.ikon, color: l.warna, size: 27),
              ),
              if (l.badge != null)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2845C),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      l.badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            l.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF12302F),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar Z-Score -3..+3 dengan penanda posisi anak (bergeser pelan dari tengah).
class _GaugeZ extends StatelessWidget {
  final double? z;

  const _GaugeZ({required this.z});

  @override
  Widget build(BuildContext context) {
    final posisi = z == null ? null : (z!.clamp(-3.0, 3.0) + 3) / 6;

    return LayoutBuilder(
      builder: (context, box) {
        final lebar = box.maxWidth;
        // Stack ada di dalam builder karena Positioned harus anak langsung Stack.
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: posisi ?? 0.5),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, p, _) => SizedBox(
            height: 16,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  top: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE0645A),
                          Color(0xFFF2C14E),
                          Color(0xFF4CB86B),
                          Color(0xFF4CB86B),
                          Color(0xFFF2C14E),
                          Color(0xFFE0645A),
                        ],
                        stops: [0, 0.22, 0.4, 0.6, 0.78, 1],
                      ),
                    ),
                  ),
                ),
                if (posisi != null)
                  Positioned(
                    left: p * lebar - 8,
                    top: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF12302F),
                          width: 3,
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
}

/// Garis tren mini: area lembut, garis, dan titik.
class _TrenPainter extends CustomPainter {
  final List<double> nilai;
  final Color warna;

  const _TrenPainter(this.nilai, this.warna);

  @override
  void paint(Canvas canvas, Size size) {
    if (nilai.isEmpty) return;

    const pad = 10.0;
    final lebar = size.width - pad * 2;
    final tinggi = size.height - pad * 2;
    final minV = nilai.reduce((a, b) => a < b ? a : b);
    final maxV = nilai.reduce((a, b) => a > b ? a : b);
    final rata = (maxV - minV) == 0;

    Offset titik(int i) {
      final x = nilai.length == 1
          ? size.width / 2
          : pad + lebar * i / (nilai.length - 1);
      final y = rata
          ? size.height / 2
          : pad + tinggi * (1 - (nilai[i] - minV) / (maxV - minV));
      return Offset(x, y);
    }

    final semua = [for (var i = 0; i < nilai.length; i++) titik(i)];

    if (semua.length > 1) {
      final garis = Path()..moveTo(semua.first.dx, semua.first.dy);
      for (final p in semua.skip(1)) {
        garis.lineTo(p.dx, p.dy);
      }
      final area = Path.from(garis)
        ..lineTo(semua.last.dx, size.height)
        ..lineTo(semua.first.dx, size.height)
        ..close();

      canvas.drawPath(area, Paint()..color = warna.withValues(alpha: 0.12));
      canvas.drawPath(
        garis,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = warna,
      );
    }

    for (final p in semua) {
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = warna,
      );
    }
  }

  @override
  bool shouldRepaint(_TrenPainter old) =>
      old.nilai != nilai || old.warna != warna;
}