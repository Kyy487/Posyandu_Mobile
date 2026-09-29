import 'package:flutter/material.dart';

import '../../models/child.dart';
import '../../models/child_timeline.dart';
import '../../models/measurement_model.dart';
import '../../models/medical_note.dart';
import '../../services/child_timeline_service.dart';
import '../../services/kader_service.dart';
import '../../utils/month_label.dart';
import 'catatan_keluhan_screen.dart';
import 'imunisasi_screen.dart';
import 'input_penimbangan_screen.dart';

class DetailAnakScreen extends StatefulWidget {
  final Child childData; // Menerima data anak dari Dashboard

  const DetailAnakScreen({super.key, required this.childData});

  @override
  State<DetailAnakScreen> createState() => _DetailAnakScreenState();
}

class _DetailAnakScreenState extends State<DetailAnakScreen> {
  final KaderService _kaderService = KaderService();
  final ChildTimelineService _timelineService = ChildTimelineService();

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

  // Mengambil riwayat penimbangan anak ini dari API
  Future<void> _loadRiwayat() async {
    setState(() => _isLoading = true);
    try {
      final raw = await _kaderService.getMeasurements(widget.childData.id);
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

    final hasil = await _timelineService.getTimeline(widget.childData.id);

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

    final hasil = await _timelineService.getTimeline(
      widget.childData.id,
      before: cursor,
    );

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
    return (teks != null && teks.isNotEmpty)
        ? teks
        : widget.childData.medicalFlags;
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

  @override
  Widget build(BuildContext context) {
    final terakhir = _terakhir;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue[800],
        title: const Text(
          'Profil Medis Anak',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Catatan Keluhan',
            icon: const Icon(Icons.monitor_heart_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CatatanKeluhanScreen(
                    childId: widget.childData.id,
                    childName: widget.childData.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Imunisasi',
            icon: const Icon(Icons.vaccines),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImunisasiScreen(
                    childId: widget.childData.id,
                    childName: widget.childData.name,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Fitur edit data anak segera hadir'),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER PROFIL ANAK
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      widget.childData.name.isNotEmpty
                          ? widget.childData.name[0].toUpperCase()
                          : 'A',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.childData.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NIK: ${widget.childData.nik}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ibu: ${widget.childData.parentName}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hitungUmur(widget.childData.dateOfBirth ?? ''),
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (_kondisiKhusus != null) ...[
                          const SizedBox(height: 8),
                          _buildBadgeKondisiKhusus(_kondisiKhusus!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. STATISTIK PENIMBANGAN TERAKHIR (diambil dari API, bukan hardcode)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📊 Penimbangan Terakhir',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (terakhir != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    // Muat ulang penimbangan DAN buku medis. Layar ini memang
                    // tidak memakai RefreshIndicator, jadi tombol inilah satu-
                    // satunya jalan memuat ulang - dan tombolnya sudah ada
                    // sebelum timeline dibuat.
                    onPressed: _muatUlangSemua,
                    tooltip: 'Muat ulang',
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (terakhir == null)
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
                    Icon(
                      Icons.monitor_weight_outlined,
                      size: 40,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Belum ada data penimbangan.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tekan tombol "Input Bulan Ini" di bawah untuk mencatat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  _buildStatCard(
                    'Berat (BB)',
                    '${terakhir.weightKg} kg',
                    Colors.blue,
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'Tinggi (TB)',
                    '${terakhir.heightCm} cm',
                    Colors.purple,
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'Status Gizi',
                    terakhir.statusGizi ?? '-',
                    _warnaStatus(terakhir.statusGizi),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _warnaStatus(terakhir.statusGizi)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _warnaStatus(terakhir.statusGizi)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calculate,
                      color: _warnaStatus(terakhir.statusGizi),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Z-Score BB/U: ${terakhir.zScoreWfa?.toStringAsFixed(2) ?? '-'}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _warnaStatus(terakhir.statusGizi),
                            ),
                          ),
                          Text(
                            'Umur saat ditimbang: ${terakhir.ageInMonths ?? '-'} bulan · Standar WHO 2006',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // 3. CATATAN KELUHAN (dari API, Opsi C)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '\u{1F3E5} Catatan Keluhan',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CatatanKeluhanScreen(
                          childId: widget.childData.id,
                          childName: widget.childData.name,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Buka', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Keluhan yang dilihat kader saat penimbangan. Satu anak punya '
              'satu catatan per tanggal.',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),

            // 4. RIWAYAT PEMERIKSAAN BERKESINAMBUNGAN (dari API)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '📅 Riwayat Pemeriksaan (${_riwayat.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_riwayat.length > 1)
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Menampilkan ${_riwayat.length} data penimbangan',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text(
                      'Lihat Semua',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (!_isLoading && _riwayat.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Belum ada riwayat penimbangan.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _riwayat.length,
                itemBuilder: (context, index) {
                  final m = _riwayat[index];
                  final isLatest = index == 0;
                  return _buildHistoryCard(
                    date: _formatTanggal(m.measurementDate),
                    bb: '${m.weightKg} kg',
                    tb: '${m.heightCm} cm',
                    zScore: m.zScoreWfa?.toStringAsFixed(2) ?? '-',
                    statusGizi: m.statusGizi,
                    warnaStatus: _warnaStatus(m.statusGizi),
                    isLatest: isLatest,
                  );
                },
              ),

            const SizedBox(height: 24),

            // 5. BUKU MEDIS: satu timeline per tanggal kunjungan (Opsi B)
            _buildTimeline(),
            const SizedBox(height: 24),

            // Jarak ekstra di bawah agar konten tidak tertutup oleh tombol FAB
            const SizedBox(height: 80),
          ],
        ),
      ),

      // 5. TOMBOL AKSI INPUT e-KMS
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  InputPenimbanganScreen(childId: widget.childData.id),
            ),
          );
          // Muat ulang riwayat agar Z-Score & Status Gizi ter-update otomatis,
          // sekalian timeline supaya kunjungan barunya langsung terlihat.
          if (saved == true) {
            _muatUlangSemua();
          }
        },
        backgroundColor: Colors.blue[800],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Input Bulan Ini',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
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
          'Riwayat lengkap per tanggal kunjungan: penimbangan, suntikan, dan keluhan.',
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
          ],
        ),
      ),
    );
  }

  /// Baris penimbangan: BB, TB, z-score, status gizi, kader.
  Widget _buildBagianPenimbangan(TimelineMeasurement m) {
    final warna = _warnaStatus(m.statusGizi);

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

  /// Pemetaan warna indikator sesuai status gizi hasil hitungan Z-Score.
  Color _warnaStatus(String? status) {
    switch (status) {
      case 'Gizi Buruk':
        return Colors.red;
      case 'Gizi Kurang':
        return Colors.orange[800] ?? Colors.orange;
      case 'Risiko Gizi Lebih':
        return Colors.blueGrey;
      case 'Normal':
        return Colors.green;
      default:
        return Colors.grey;
    }
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

  // Widget Bantuan: Kartu Riwayat Timeline
  Widget _buildHistoryCard({
    required String date,
    required String bb,
    required String tb,
    required String zScore,
    required String? statusGizi,
    required Color warnaStatus,
    required bool isLatest,
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
