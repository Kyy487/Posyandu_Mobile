import 'package:flutter/material.dart';

import '../../models/child.dart';
import '../../services/auth_service.dart';
import '../../services/child_service.dart';
import '../login_screen.dart';
import 'catatan_keluhan_screen.dart';
import 'jadwal_posyandu_screen.dart';
import 'status_imunisasi_screen.dart';
import 'tambah_anak_dialog.dart';

class DashboardIbuScreen extends StatefulWidget {
  const DashboardIbuScreen({super.key});

  @override
  State<DashboardIbuScreen> createState() => _DashboardIbuScreenState();
}

class _DashboardIbuScreenState extends State<DashboardIbuScreen> {
  final ChildService _childService = ChildService();
  final AuthService _authService = AuthService();

  String _namaIbu = '';
  List<Child> _anak = [];
  int _selectedAnakIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  /// Mengambil nama Ibu dan daftar anaknya langsung dari database.
  Future<void> _muatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Nama ibu dari GET /api/user, daftar anak dari GET /api/children.
    final profile = await _authService.getProfile();
    final result = await _childService.getChildren();

    if (!mounted) return;

    if (result['success'] == true && result['data'] is List) {
      final anak = (result['data'] as List)
          .map((e) => Child.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      setState(() {
        _namaIbu = profile?['name']?.toString() ?? '';
        _anak = anak;
        _selectedAnakIndex = 0;
        _isLoading = false;
      });
      return;
    }

    // Sesi habis -> arahkan ke login, jangan tampilkan layar kosong.
    if (result['status'] == 401) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat data.';
      _isLoading = false;
    });
  }

  Future<void> _tambahAnak() async {
    final child = await showTambahAnakDialog(context, _childService);
    if (child == null || !mounted) return;

    setState(() {
      _anak = [..._anak, child];
      _selectedAnakIndex = _anak.length - 1;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Anak ${child.name} berhasil ditambahkan.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Child? get _anakAktif => _anak.isEmpty ? null : _anak[_selectedAnakIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.pink[400],
        title: const Text(
          'Smart Posyandu Bunda',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isLoading ? null : _muatData,
          ),
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              // Navigator diambil SEBELUM await agar tidak memakai BuildContext
              // setelah async gap.
              final navigator = Navigator.of(context);
              await _authService.logout();
              if (!mounted) return;
              navigator.pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.pink));
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    if (_anak.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: Colors.pink,
      onRefresh: _muatData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildQuickMenu(),
                  const SizedBox(height: 16),
                  _buildImunisasiMenu(),
                  const SizedBox(height: 16),
                  _buildKeluhanMenu(),
                  const SizedBox(height: 24),
                  _buildStatusGizi(),
                  const SizedBox(height: 20),
                  _buildInsight(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Header: sapaan + pemilih anak
  // -----------------------------------------------------------------
  Widget _buildHeader() {
    final sapaan = _namaIbu.isEmpty ? 'Bunda' : 'Bunda $_namaIbu';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 24),
      decoration: BoxDecoration(
        color: Colors.pink[400],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Halo, $sapaan',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Memantau perkembangan anak:',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _anak.length; i++)
                  _buildChildSelector(_anak[i], i == _selectedAnakIndex, () {
                    setState(() => _selectedAnakIndex = i);
                  }),
                _buildAddChildButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChildSelector(Child anak, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              anak.gender == 'P' ? Icons.girl : Icons.boy,
              color: isActive ? Colors.pink[400] : Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anak.shortName,
                  style: TextStyle(
                    color: isActive ? Colors.pink[600] : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (isActive)
                  Text(
                    anak.ageLabel,
                    style: TextStyle(
                      color: Colors.pink[300],
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddChildButton() {
    return GestureDetector(
      onTap: _tambahAnak,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Menu cepat
  // -----------------------------------------------------------------
  Widget _buildQuickMenu() {
    final nama = _anakAktif?.name ?? 'anak';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Menu Cepat',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMenuButton(
                Icons.camera_alt,
                'Sepiring\nBergizi',
                Colors.orange,
                () => _info('Cek gizi makanan $nama'),
              ),
              _buildMenuButton(
                Icons.auto_graph,
                'Grafik\nTumbuh',
                Colors.blue,
                () => _info('Grafik pertumbuhan $nama'),
              ),
              _buildMenuButton(
                Icons.play_circle_fill,
                'Edukasi\n& Tips',
                Colors.purple,
                () => _info('Video edukasi'),
              ),
              _buildMenuButton(
                Icons.calendar_month,
                'Jadwal\nPosyandu',
                Colors.teal,
                _bukaJadwalPosyandu,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _bukaJadwalPosyandu() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const JadwalPosyanduScreen()),
    );
  }

  void _bukaStatusImunisasi() {
    final anak = _anakAktif;
    if (anak == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            StatusImunisasiScreen(childId: anak.id, childName: anak.name),
      ),
    );
  }

  void _bukaCatatanKeluhan() {
    final anak = _anakAktif;
    if (anak == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CatatanKeluhanScreen(childId: anak.id, childName: anak.name),
      ),
    );
  }

  /// Entri catatan keluhan memakai kartu penuh seperti imunisasi, karena
  /// orang tua perlu tahu kalau kader melihat keluhan pada kunjungan
  /// terakhir. Read-only: hanya kader yang boleh mencatat.
  Widget _buildKeluhanMenu() {
    final nama = _anakAktif?.name ?? 'anak';

    return InkWell(
      onTap: _bukaCatatanKeluhan,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.monitor_heart_outlined,
                color: Colors.red,
                size: 26,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan Keluhan $nama',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Keluhan yang dilihat kader, dan tindak lanjut yang disarankan.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  /// Entri imunisasi dibuat kartu penuh, bukan tombol menu, karena status
  /// imunisasi adalah hal yang paling sering dicek orang tua.
  Widget _buildImunisasiMenu() {
    final nama = _anakAktif?.name ?? 'anak';

    return InkWell(
      onTap: _bukaStatusImunisasi,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.pink.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.vaccines, color: Colors.purple, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status Imunisasi $nama',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Lihat dosis yang sudah, belum, dan terlambat.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _info(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  /// Satu tombol di Menu Cepat: ikon, label dua baris, dan aksi saat ditekan.
  Widget _buildMenuButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // Status gizi (dari database)
  // -----------------------------------------------------------------
  Widget _buildStatusGizi() {
    final anak = _anakAktif!;
    final z = anak.latestZScore;
    final status = anak.nutritionLabel;

    final (Color warna, IconData ikon) = _warnaStatus(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warna.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withValues(alpha: 0.05),
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
                  'Status Gizi - ${anak.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!anak.hasMeasurement)
            const Text(
              'Belum ada data penimbangan. Kader akan mencatatnya saat '
              'kunjungan posyandu berikutnya.',
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            )
          else
            Row(
              children: [
                _buildStatBox(
                  label: 'Tercatat',
                  value: _formatTanggal(anak.lastMeasurementDate!),
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
              fontSize: 14,
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

  /// Warna + ikon sesuai klasifikasi status gizi dari trigger WHO.
  (Color, IconData) _warnaStatus(String? status) {
    if (status == null) return (Colors.grey, Icons.help_outline);

    if (status.contains('Buruk') || status.contains('Stunting')) {
      return (Colors.red, Icons.warning_amber);
    }
    if (status.contains('Kurang') || status.contains('Risiko')) {
      return (Colors.orange, Icons.info_outline);
    }
    if (status.contains('Lebih')) {
      return (Colors.deepOrange, Icons.trending_up);
    }
    return (Colors.green, Icons.check_circle_outline);
  }

  // -----------------------------------------------------------------
  // Insight
  // -----------------------------------------------------------------
  Widget _buildInsight() {
    final anak = _anakAktif!;
    final z = anak.latestZScore;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Insight Khusus: ',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Expanded(
              child: Text(
                anak.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.pink[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInsightCard(
          icon: Icons.cake_outlined,
          iconColor: Colors.pink,
          title: 'Kondisi Saat Ini',
          time: anak.lastMeasurementDate == null
              ? 'Belum ada data'
              : _formatTanggal(anak.lastMeasurementDate!),
          content: _isiInsightGizi(anak, z),
        ),
        _buildInsightCard(
          icon: Icons.restaurant,
          iconColor: Colors.orange,
          title: 'Saran Pola Makan',
          time: 'Untuk Ibu',
          content: _saranMakan(anak, z),
        ),
      ],
    );
  }

  String _isiInsightGizi(Child anak, double? z) {
    if (!anak.hasMeasurement) {
      return '${anak.name} (${anak.ageLabel}) belum pernah ditimbang. '
          'Datanya akan muncul setelah kader mencatatnya di posyandu.';
    }

    final status = anak.nutritionLabel ?? 'tidak diketahui';
    return '${anak.name} (${anak.ageLabel}) memiliki Z-Score '
        '${z?.toStringAsFixed(2) ?? '-'} dengan status "$status" pada '
        'penimbangan terakhir. Z-Score dihitung otomatis oleh sistem dari '
        'standar WHO.';
  }

  String _saranMakan(Child anak, double? z) {
    if (z == null) {
      return 'Pastikan ${anak.name} rutin ditimbang setiap bulan agar '
          'pertumbuhan dapat dipantau.';
    }
    if (z < -3) {
      return 'Z-Score di bawah -3 menunjukkan status gizi buruk. Segera '
          'konsultasikan ke puskesmas atau kader posyandu agar ${anak.name} '
          'mendapat penanganan lebih lanjut.';
    }
    if (z < -2) {
      return 'Pertumbuhan ${anak.name} masih di bawah target. Perbanyak '
          'telur, daging, ikan, dan kacang hijau, serta jadwalkan '
          'penimbangan rutin di posyandu.';
    }
    if (z > 1) {
      return 'Pertumbuhan ${anak.name} tergolong cepat. Jaga keragaman '
          'makanan agar tetap seimbang, Bun.';
    }
    return 'Pertumbuhan ${anak.name} sudah sesuai target. Pertahankan pola '
        'makan beragam dan pastikan protein cukup setiap hari.';
  }

  Widget _buildInsightCard({
    required IconData icon,
    required MaterialColor iconColor,
    required String title,
    required String time,
    required String content,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.pink[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.pink.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor[600], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    color: Colors.grey[800],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // Empty & error state
  // -----------------------------------------------------------------
  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.child_care_outlined, size: 72, color: Colors.pink[200]),
            const SizedBox(height: 16),
            const Text(
              'Belum ada data anak',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tambahkan anak pertama Anda agar pertumbuhannya bisa dipantau '
              'oleh kader posyandu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _tambahAnak,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Anak'),
            ),
          ],
        ),
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
            Icon(Icons.cloud_off, size: 64, color: Colors.pink[200]),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat data',
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
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  /// Format `YYYY-MM-DD` menjadi "15 Agustus 2026".
  String _formatTanggal(String isoDate) {
    final d = DateTime.tryParse(isoDate);
    if (d == null) return isoDate;

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
  }
}
