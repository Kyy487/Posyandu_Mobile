import 'package:flutter/material.dart';

import '../../models/posyandu_schedule.dart';
import '../../services/schedule_service.dart';
import '../login_screen.dart';

/// Daftar agenda posyandu untuk orang tua. Read-only.
///
/// Satu kartu menampilkan tanggal, jam, lokasi, dan siapa petugas yang
/// menangani. NIK petugas tidak pernah ditampilkan karena endpoint
/// `/petugas` memang tidak mengirimnya.
class JadwalPosyanduScreen extends StatefulWidget {
  const JadwalPosyanduScreen({super.key});

  @override
  State<JadwalPosyanduScreen> createState() => _JadwalPosyanduScreenState();
}

class _JadwalPosyanduScreenState extends State<JadwalPosyanduScreen> {
  final ScheduleService _service = ScheduleService();

  List<PosyanduSchedule> _agenda = [];
  bool _isLoading = true;
  String? _errorMessage;

  /// null = semua agenda, bukan hanya yang upcoming.
  bool _hanyaMendatang = true;

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

    final result = await _service.getSchedules();

    if (!mounted) return;

    if (result['status'] == 401) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is List) {
      var agenda = (result['data'] as List)
          .map((e) => PosyanduSchedule.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (_hanyaMendatang) {
        agenda = agenda.where((a) => !a.isPast).toList()
          ..sort((a, b) => a.scheduledDate!.compareTo(b.scheduledDate!));
      }

      setState(() {
        _agenda = agenda;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat jadwal.';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        backgroundColor: Colors.pink[400],
        foregroundColor: Colors.white,
        title: const Text('Jadwal Posyandu'),
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
      return const Center(
        child: CircularProgressIndicator(color: Colors.pink),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    return RefreshIndicator(
      color: Colors.pink,
      onRefresh: _muatData,
      child: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _agenda.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [_EmptyAgendaIbu()],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _hanyaMendatang ? 'Agenda mendatang' : 'Semua agenda',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Switch(
            value: _hanyaMendatang,
            activeThumbColor: Colors.pink,
            onChanged: (v) {
              setState(() => _hanyaMendatang = v);
              _muatData();
            },
          ),
          const Text(
            'Mendatang saja',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(PosyanduSchedule agenda) {
    final warna = _warnaStatus(agenda.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
            const SizedBox(height: 12),
            _buildInfo(Icons.event, _formatTanggalIndo(agenda.scheduledDate)),
            if (agenda.timeLabel.isNotEmpty)
              _buildInfo(Icons.schedule, agenda.timeLabel),
            if (agenda.locationName != null)
              _buildInfo(Icons.location_on, agenda.locationName!),
            if (agenda.petugas.isNotEmpty)
              _buildInfo(Icons.groups, agenda.petugasLabel),
            if (agenda.description != null) ...[
              const SizedBox(height: 8),
              Text(
                agenda.description!,
                style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(IconData ikon, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 16, color: Colors.pink[400]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
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
            Icon(Icons.cloud_off, size: 64, color: Colors.pink[200]),
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

  /// Ubah `YYYY-MM-DD` jadi "Sabtu, 15 Agustus 2026".
  static String _formatTanggalIndo(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return iso ?? '-';

    const hari = [
      'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
    ];
    const bulan = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return '${hari[d.weekday - 1]}, ${d.day} ${bulan[d.month - 1]} ${d.year}';
  }
}

class _EmptyAgendaIbu extends StatelessWidget {
  const _EmptyAgendaIbu();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_available, size: 64, color: Colors.pink[200]),
              const SizedBox(height: 16),
              const Text(
                'Belum ada agenda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Jadwal kegiatan posyandu berikutnya akan muncul di sini. '
                'Matikan sakelar "Mendatang saja" untuk melihat agenda lama.',
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
