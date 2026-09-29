import 'package:flutter/material.dart';

import '../../models/immunization_recap.dart';
import '../../services/immunization_recap_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/month_label.dart';
import '../login_screen.dart';

/// Rekap imunisasi bulanan untuk Kader (Opsi E).
///
/// Layar ini read-only. Kader tidak mengetik angka apa pun di sini: semua
/// angka berasal dari suntikan yang sudah tercatat lewat endpoint lain, jadi
/// rekap tidak bisa melenceng dari catatan asli.
///
/// Dua bagian ditampilkan TERPISAH dan tidak pernah dijumlahkan, mengikuti
/// aturan di `docs/API_CONTRACT.md`:
///
/// * **Aktivitas suntikan** - berapa dosis keluar bulan itu, untuk stok vaksin.
/// * **Kelengkapan anak** - siapa yang belum lengkap, untuk kunjungan rumah.
///
/// Navigasi bulan memakai helper [geserBulan], bukan `DateTime`, supaya
/// perpindahan dari Desember ke Januari tidak melewati tahun dengan benar.
class RekapImunisasiScreen extends StatefulWidget {
  const RekapImunisasiScreen({super.key});

  @override
  State<RekapImunisasiScreen> createState() => _RekapImunisasiScreenState();
}

class _RekapImunisasiScreenState extends State<RekapImunisasiScreen> {
  final ImmunizationRecapService _service = ImmunizationRecapService();

  ImmunizationRecap? _rekap;
  bool _isLoading = true;
  String? _errorMessage;

  /// Bulan yang sedang dilihat, format `YYYY-MM`.
  late String _bulan = _bulansekarang();

  /// Toggle untuk baris master dosis yang `count`-nya 0.
  bool _tampilkanTanpaSuntikan = false;

  static String _bulansekarang() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
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

    final result = await _service.getRecap(month: _bulan);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is ImmunizationRecap) {
      setState(() {
        _rekap = result['data'] as ImmunizationRecap;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Gagal memuat rekap imunisasi.';
      _isLoading = false;
    });
  }

  void _geserBulan(int delta) {
    setState(() => _bulan = geserBulan(_bulan, delta: delta));
    _muatData();
  }

  /// Bulan yang sedang dilihat sudah bulan berjalan atau yang lebih baru?
  ///
  /// Tombol maju dimatikan di situation itu. Rekap bulan depan tidak berarti
  /// apa-apa untuk laporan, dan membiarkan kader menekan tombolnya lalu melihat
  /// angka nol akan menyesatkan - terlihat seperti datanya hilang.
  bool get _sudahBulanTerbaru {
    final ini = _bulansekarang();
    return _bulan.compareTo(ini) >= 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text('Rekap Imunisasi Bulanan'),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    final rekap = _rekap;
    if (rekap == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildMonthBar(rekap),
          const SizedBox(height: 16),
          if (rekap.kosong)
            _buildKosongState()
          else ...[
            _buildActivitySection(rekap.activity),
            const SizedBox(height: 16),
            _buildCoverageSection(rekap.coverage),
            const SizedBox(height: 16),
            _buildOverdueSection(rekap.coverage),
          ],
        ],
      ),
    );
  }

  /// Baris navigasi bulan + tanggal acuan server.
  Widget _buildMonthBar(ImmunizationRecap rekap) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Bulan sebelumnya',
                onPressed: () => _geserBulan(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      rekap.labelBulanRekap,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _bulan == _bulansekarang()
                          ? 'Bulan berjalan'
                          : 'Bulan lampau',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _sudahBulanTerbaru
                    ? 'Sudah bulan terbaru'
                    : 'Bulan berikutnya',
                onPressed: _sudahBulanTerbaru ? null : () => _geserBulan(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.event_available,
                size: 14,
                color: AppTheme.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Dihitung sampai ${rekap.labelAcuan}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bagian aktivitas: berapa dosis keluar. Untuk stok vaksin.
  Widget _buildActivitySection(RecapActivity activity) {
    final terpakai = activity.terpakai;
    final kosong = activity.byType.where((e) => e.kosong).toList();
    final perVaksin = activity.totalPerVaksin;

    return _section(
      judul: 'Aktivitas Suntikan',
      subjudul: 'Dosis yang keluar bulan ini - untuk stok vaksin',
      ikon: Icons.vaccines,
      anak: [
        Row(
          children: [
            Expanded(
              child: _statBox(
                '${activity.totalDoses}',
                'Total dosis',
                AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statBox(
                '${activity.totalChildren}',
                'Anak disuntik',
                AppTheme.primaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (terpakai.isEmpty)
          const _InfoBar(
            ikon: Icons.info_outline,
            teks: 'Tidak ada suntikan tercatat pada bulan ini.',
            warna: AppTheme.muted,
          )
        else
          ...terpakai.map(
            (dosis) => _barisVaksin(
              label: dosis.name,
              jumlah: perVaksin[dosis.code] ?? dosis.count,
            ),
          ),
        if (kosong.isNotEmpty) ...[
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(
              () => _tampilkanTanpaSuntikan = !_tampilkanTanpaSuntikan,
            ),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    _tampilkanTanpaSuntikan
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${kosong.length} master dosis tidak ada suntikan bulan ini',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_tampilkanTanpaSuntikan)
            ...kosong.map(
              (dosis) => Padding(
                padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.remove, size: 16, color: AppTheme.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${dosis.name} (Dosis ${dosis.doseNumber})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                    const Text(
                      '0',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _barisVaksin({required String label, required int jumlah}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.ink),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$jumlah',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bagian kelengkapan: untuk laporan dan kunjungan rumah.
  Widget _buildCoverageSection(RecapCoverage coverage) {
    return _section(
      judul: 'Kelengkapan Anak',
      subjudul: 'Keadaan di akhir bulan - untuk laporan & kunjungan',
      ikon: Icons.fact_check_outlined,
      anak: [
        Row(
          children: [
            Expanded(
              child: _statBox(
                '${coverage.totalChildren}',
                'Anak terdaftar',
                AppTheme.ink,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statBox(
                '${coverage.complete}',
                'Lengkap',
                AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _statBox(
                '${coverage.incomplete}',
                'Belum lengkap',
                AppTheme.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: coverage.totalChildren == 0
                ? 0
                : coverage.complete / coverage.totalChildren,
            minHeight: 10,
            backgroundColor: AppTheme.border,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${coverage.percentComplete}% anak sudah lengkap '
          '($coverage.complete dari ${coverage.totalChildren})',
          style: const TextStyle(fontSize: 12, color: AppTheme.muted),
        ),
        if (coverage.excludedArchived > 0) ...[
          const SizedBox(height: 10),
          _InfoBar(
            ikon: Icons.archive_outlined,
            teks:
                '${coverage.excludedArchived} anak tidak dihitung karena '
                'sudah dilepas dari Posyandu. Angka mereka sengaja tidak '
                'ikut dihitung dan ditampilkan terpisah di sini.',
            warna: AppTheme.muted,
          ),
        ],
      ],
    );
  }

  /// Daftar anak yang perlu dikunjungi. Urutannya sudah dari server
  /// (paling banyak dosis terlambat dulu), jadi layar tidak mengurutkan ulang.
  Widget _buildOverdueSection(RecapCoverage coverage) {
    if (coverage.overdueChildren.isEmpty) {
      return _section(
        judul: 'Anak Perlu Dikunjungi',
        subjudul: 'Tidak ada anak dengan dosis terlambat',
        ikon: Icons.people_outline,
        anak: const [
          _InfoBar(
            ikon: Icons.check_circle_outline,
            teks: 'Semua anak sudah lengkap imunisasinya pada bulan ini.',
            warna: AppTheme.success,
          ),
        ],
      );
    }

    return _section(
      judul: 'Anak Perlu Dikunjungi',
      subjudul: 'Paling banyak dosis terlambat dulu - urutan dari server',
      ikon: Icons.people_outline,
      anak: [
        for (final anak in coverage.overdueChildren)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildAnakCard(anak),
          ),
      ],
    );
  }

  Widget _buildAnakCard(RecapOverdueChild anak) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        // ExpansionTile bawaan memberi garis pemisah abu yang clashes dengan
        // kartu putih; di sini dilepas supaya kartu terlihat sendiri.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: CircleAvatar(
            backgroundColor: AppTheme.danger.withValues(alpha: 0.10),
            child: Text(
              anak.name.isNotEmpty ? anak.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppTheme.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(
            anak.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${anak.ageLabel} - ${anak.jumlahDosis} dosis terlambat, '
            'paling lama ${anak.terlambatTerlama} bulan',
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
          children: [
            for (final dosis in anak.overdueDoses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 15,
                      color: AppTheme.danger,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dosis.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      dosis.statusNote,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w600,
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

  /// Kartu pembungkus satu bagian. `activity` dan `coverage` sengaja punya
  /// kartu terpisah supaya tidak ada yang mengira keduanya bisa dijumlahkan.
  Widget _section({
    required String judul,
    required String subjudul,
    required IconData ikon,
    required List<Widget> anak,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 20, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  judul,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subjudul,
              style: const TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
          ),
          const SizedBox(height: 16),
          ...anak,
        ],
      ),
    );
  }

  Widget _statBox(String nilai, String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            nilai,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: warna,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.muted),
          ),
        ],
      ),
    );
  }

  Widget _buildKosongState() {
    return _section(
      judul: 'Belum ada data bulan ini',
      subjudul: 'Tidak ada suntikan maupun anak terlambat',
      ikon: Icons.event_note,
      anak: [
        const _InfoBar(
          ikon: Icons.info_outline,
          teks:
              'Bulan ini belum ada suntikan yang tercatat, dan tidak ada anak '
              'dengan dosis terlambat. Coba pilih bulan lain lewat tombol panah.',
          warna: AppTheme.muted,
        ),
      ],
    );
  }

  Widget _buildErrorState(String pesan) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: AppTheme.primaryLight),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat rekap',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, height: 1.4),
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
}

/// Baris informasi singkat di dalam kartu (bukan Snackbar, supaya tidak hilang
/// sebelum dibaca).
class _InfoBar extends StatelessWidget {
  final IconData ikon;
  final String teks;
  final Color warna;

  const _InfoBar({required this.ikon, required this.teks, required this.warna});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 17, color: warna),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              teks,
              style: TextStyle(fontSize: 12, color: warna, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
