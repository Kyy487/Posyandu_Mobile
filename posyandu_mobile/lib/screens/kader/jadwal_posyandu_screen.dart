import 'package:flutter/material.dart';

import '../../models/posyandu_schedule.dart';
import '../../services/schedule_service.dart';
import '../login_screen.dart';
import 'form_agenda.dart';

/// Agenda kegiatan posyandu untuk Kader: daftar, tambah, ubah, hapus.
///
/// Satu agenda adalah satu kegiatan pada tanggal tertentu yang bisa ditangani
/// lebih dari satu petugas, jadi penugasan lewat pivot - bukan kolom tunggal.
class JadwalPosyanduScreen extends StatefulWidget {
  const JadwalPosyanduScreen({super.key});

  @override
  State<JadwalPosyanduScreen> createState() => _JadwalPosyanduScreenState();
}

class _JadwalPosyanduScreenState extends State<JadwalPosyanduScreen> {
  final ScheduleService _service = ScheduleService();

  List<PosyanduSchedule> _agenda = [];
  List<Petugas> _petugas = [];

  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _filterTanggal;

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
      });
      return;
    }

    setState(() {
      _errorMessage = jadwal['message']?.toString() ?? 'Gagal memuat jadwal.';
      _isLoading = false;
    });
  }

  static String? _formatTanggal(DateTime? t) {
    if (t == null) return null;
    return t.toIso8601String().substring(0, 10);
  }

  Future<void> _pilihFilterTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterTanggal ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;

    setState(() => _filterTanggal = picked);
    _muatData();
  }

  Future<void> _bukaForm([PosyanduSchedule? existing]) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FormAgenda(
        existing: existing,
        petugas: _petugas,
        service: _service,
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal Posyandu'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bukaForm,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Agenda'),
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

    return RefreshIndicator(
      onRefresh: _muatData,
      child: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _agenda.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [_EmptyAgendaKader()],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: _agenda.length,
                    itemBuilder: (context, index) =>
                        _buildAgendaCard(_agenda[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      width: double.infinity,
      color: Colors.grey[100],
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.filter_alt, size: 18, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _filterTanggal == null
                  ? 'Semua agenda'
                  : 'Agenda tanggal ${_formatTanggalTampil(_filterTanggal!)}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (_filterTanggal != null)
            TextButton.icon(
              onPressed: () {
                setState(() => _filterTanggal = null);
                _muatData();
              },
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Semua'),
            )
          else
            TextButton.icon(
              onPressed: _pilihFilterTanggal,
              icon: const Icon(Icons.calendar_month, size: 16),
              label: const Text('Filter'),
            ),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(PosyanduSchedule agenda) {
    final warna = _warnaStatus(agenda.status);

    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _bukaForm(agenda),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      agenda.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: warna.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      ScheduleStatus.label(agenda.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: warna,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildBaris(Icons.calendar_today, agenda.scheduledDate ?? '-'),
              if (agenda.timeLabel.isNotEmpty)
                _buildBaris(Icons.schedule, agenda.timeLabel),
              if (agenda.locationName != null)
                _buildBaris(Icons.location_on, agenda.locationName!),
              _buildBaris(Icons.groups, agenda.petugasLabel),
              if (agenda.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  agenda.description!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 3,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _bukaForm(agenda),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Ubah'),
                  ),
                  TextButton.icon(
                    onPressed: () => _konfirmasiHapus(agenda),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Hapus'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBaris(IconData ikon, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(ikon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nilai,
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
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
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat jadwal',
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

  static String _formatTanggalTampil(DateTime t) =>
      '${t.day}/${t.month}/${t.year}';
}

class _EmptyAgendaKader extends StatelessWidget {
  const _EmptyAgendaKader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.event_note, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Belum ada agenda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tekan "Tambah Agenda" untuk membuat kegiatan posyandu '
                'dan menugaskan petugas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
