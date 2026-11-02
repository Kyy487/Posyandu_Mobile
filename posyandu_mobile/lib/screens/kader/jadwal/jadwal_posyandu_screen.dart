import 'package:flutter/material.dart';

import '/../../models/posyandu_schedule.dart';
import '/../../services/schedule_service.dart';
import '/../../theme/app_theme.dart';
import '/../../screens/shared/login_screen.dart';
import 'form_agenda.dart';

/// Agenda kegiatan posyandu untuk Kader: daftar, tambah, ubah, hapus.
///
/// Satu agenda adalah satu kegiatan pada tanggal tertentu yang bisa ditangani
/// lebih dari satu petugas, jadi penugasan lewat pivot - bukan kolom tunggal.
///
/// Layar ini dipakai sebagai tab pada dashboard, jadi tidak punya tombol
/// kembali. Tampilan baru: deretan tanggal 7 hari ke depan untuk menyaring
/// cepat, kartu agenda berikon sesuai jenis kegiatan, dan tombol tambah koral.
/// Seluruh logika (muat, saring server, form, hapus) sama seperti sebelumnya.
class JadwalPosyanduScreen extends StatefulWidget {
  const JadwalPosyanduScreen({super.key});

  @override
  State<JadwalPosyanduScreen> createState() => _JadwalPosyanduScreenState();
}

class _JadwalPosyanduScreenState extends State<JadwalPosyanduScreen> {
  static const Color _koral = Color(0xFFF2845C);

  final ScheduleService _service = ScheduleService();

  List<PosyanduSchedule> _agenda = [];
  List<Petugas> _petugas = [];

  /// Muat pertama: spinner penuh. Muat berikutnya (ganti tanggal, refresh)
  /// cukup bar tipis di atas daftar, supaya layar tidak berkedip.
  bool _isLoading = true;
  bool _menyegarkan = false;
  String? _errorMessage;
  DateTime? _filterTanggal;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  // ------------------------------------------------------------------ DATA

  Future<void> _muatData() async {
    setState(() {
      _errorMessage = null;
      _menyegarkan = true;
    });

    // Dua request paralel: daftar petugas dibutuhkan form, dan akan sering
    // dipakai ulang saat menambah agenda.
    final hasil = await Future.wait([
      _service.getSchedules(date: _formatTanggal(_filterTanggal)),
      _service.getPetugas(),
    ]);

    final jadwal = hasil[0];
    final petugas = hasil[1];

    if (!mounted) return;

    if (jadwal['status'] == 401) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (jadwal['success'] == true && jadwal['data'] is List) {
      setState(() {
        _agenda = (jadwal['data'] as List)
            .map((e) => PosyanduSchedule.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        if (petugas['success'] == true && petugas['data'] is List) {
          _petugas = (petugas['data'] as List)
              .map((e) => Petugas.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }

        _isLoading = false;
        _menyegarkan = false;
      });
      return;
    }

    setState(() {
      _errorMessage = jadwal['message']?.toString() ?? 'Gagal memuat jadwal.';
      _isLoading = false;
      _menyegarkan = false;
    });
  }

  static String? _formatTanggal(DateTime? t) {
    if (t == null) return null;
    return t.toIso8601String().substring(0, 10);
  }

  void _setFilter(DateTime? tanggal) {
    setState(() => _filterTanggal = tanggal);
    _muatData();
  }

  Future<void> _pilihFilterTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    _setFilter(picked);
  }

  Future<void> _bukaForm([PosyanduSchedule? existing]) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          FormAgenda(existing: existing, petugas: _petugas, service: _service),
    );

    if (tersimpan == true) {
      _muatData();
    }
  }

  Future<void> _konfirmasiHapus(PosyanduSchedule agenda) async {
    final ya = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus agenda?'),
        content: Text(
          'Agenda "${agenda.title}" akan dihapus beserta penugasan '
          'petugasnya. Agenda yang sudah lewat tidak bisa dipulihkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ya != true || !mounted) return;

    final result = await _service.deleteSchedule(agenda.id);

    if (!mounted) return;

    final sukses = result['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sukses
              ? 'Agenda dihapus.'
              : (result['message']?.toString() ?? 'Gagal menghapus agenda.'),
        ),
        backgroundColor: sukses ? Colors.green : Colors.red,
      ),
    );

    if (sukses) {
      _muatData();
    }
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.brandSurface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bukaForm,
        backgroundColor: _koral,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tambah Agenda',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jadwal',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_namaBulan[DateTime.now().month - 1]} ${DateTime.now().year}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh_rounded),
            color: AppTheme.brand,
            onPressed: _menyegarkan ? null : _muatData,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _agenda.isEmpty) {
      return _buildErrorState(_errorMessage!);
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
        children: [
          _barisTanggal(),
          const SizedBox(height: 6),
          // Bar tipis saat ganti tanggal / muat ulang, bukan spinner penuh.
          SizedBox(
            height: 3,
            child: _menyegarkan
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          _ringkasan(),
          const SizedBox(height: 4),
          if (_agenda.isEmpty)
            const _EmptyAgendaKader()
          else
            for (final a in _agenda) _buildAgendaCard(a),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- DERET TANGGAL

  static const _hariSingkat = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const _namaBulan = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  static const _bulanSingkat = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  static bool _sama(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Semua + 7 hari mulai hari ini + pilih tanggal lain. Menyentuh tanggal
  /// yang sedang aktif menghapus saringan.
  Widget _barisTanggal() {
    final hariIni = DateTime.now();
    final awal = DateTime(hariIni.year, hariIni.month, hariIni.day);
    final hari = [for (var i = 0; i < 7; i++) awal.add(Duration(days: i))];
    final filter = _filterTanggal;
    final diLuar = filter != null && !hari.any((h) => _sama(h, filter));

    return SizedBox(
      height: 70,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          _kotakTanggal(
            aktif: filter == null,
            atas: 'Semua',
            bawah: null,
            ikon: Icons.view_agenda_outlined,
            onTap: () => _setFilter(null),
          ),
          for (final h in hari)
            _kotakTanggal(
              aktif: filter != null && _sama(h, filter),
              atas: _hariSingkat[h.weekday - 1],
              bawah: '${h.day}',
              onTap: () => _setFilter(
                filter != null && _sama(h, filter) ? null : h,
              ),
            ),
          _kotakTanggal(
            aktif: diLuar,
            atas: diLuar ? _bulanSingkat[filter!.month - 1] : 'Pilih',
            bawah: diLuar ? '${filter!.day}' : null,
            ikon: diLuar ? null : Icons.calendar_month_rounded,
            onTap: _pilihFilterTanggal,
          ),
        ],
      ),
    );
  }

  Widget _kotakTanggal({
    required bool aktif,
    required String atas,
    required String? bawah,
    required VoidCallback onTap,
    IconData? ikon,
  }) {
    final fg = aktif ? Colors.white : AppTheme.ink;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: aktif ? AppTheme.brand : Colors.white,
        elevation: aktif ? 0 : 1,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58,
            height: 66,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ikon != null) ...[
                  Icon(ikon, size: 20, color: fg),
                  const SizedBox(height: 3),
                ],
                Text(
                  atas,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: aktif ? Colors.white70 : AppTheme.muted,
                  ),
                ),
                if (bawah != null)
                  Text(
                    bawah,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ringkasan() {
    final filter = _filterTanggal;
    final teks = filter == null
        ? 'Semua agenda'
        : 'Agenda ${filter.day} ${_namaBulan[filter.month - 1]} ${filter.year}';

    return Row(
      children: [
        Expanded(
          child: Text(
            teks,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '${_agenda.length} agenda',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.brand,
            ),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ KARTU

  /// Ikon agenda ditebak dari judulnya supaya jenis kegiatan mudah dikenali.
  static IconData _ikonAgenda(String judul) {
    final t = judul.toLowerCase();
    if (t.contains('timbang') || t.contains('ukur')) {
      return Icons.monitor_weight_outlined;
    }
    if (t.contains('vaksin') || t.contains('imunisasi')) {
      return Icons.vaccines_outlined;
    }
    if (t.contains('kunjung')) return Icons.home_outlined;
    return Icons.event_note_outlined;
  }

  static String _tanggalLabel(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '-';
    return '${d.day} ${_bulanSingkat[d.month - 1]} ${d.year}';
  }

  Widget _buildAgendaCard(PosyanduSchedule agenda) {
    final warna = _warnaStatus(agenda.status);

    return AppCard(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      onTap: () => _bukaForm(agenda),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              _ikonAgenda(agenda.title),
              color: AppTheme.brand,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        agenda.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: warna.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        ScheduleStatus.label(agenda.status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: warna,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildBaris(
                  Icons.calendar_today_rounded,
                  _tanggalLabel(agenda.scheduledDate),
                ),
                if (agenda.timeLabel.isNotEmpty)
                  _buildBaris(Icons.schedule_rounded, agenda.timeLabel),
                if (agenda.locationName != null)
                  _buildBaris(Icons.place_outlined, agenda.locationName!),
                _buildBaris(Icons.groups_outlined, agenda.petugasLabel),
                if (agenda.description != null &&
                    agenda.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    agenda.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.muted,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _bukaForm(agenda),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Ubah'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.brand,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _konfirmasiHapus(agenda),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFC4502A),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Hapus'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaris(IconData ikon, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(ikon, size: 14, color: AppTheme.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(fontSize: 12, color: AppTheme.ink),
            ),
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
            const Icon(Icons.cloud_off, size: 64, color: AppTheme.muted),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat jadwal',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

  static Color _warnaStatus(String status) {
    switch (status) {
      case ScheduleStatus.berlangsung:
        return Colors.blue;
      case ScheduleStatus.selesai:
        return Colors.green;
      case ScheduleStatus.dibatalkan:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }
}

class _EmptyAgendaKader extends StatelessWidget {
  const _EmptyAgendaKader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 320,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_note, size: 64, color: AppTheme.muted),
              SizedBox(height: 16),
              Text(
                'Belum ada agenda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Tekan "Tambah Agenda" untuk membuat kegiatan posyandu '
                'dan menugaskan petugas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}