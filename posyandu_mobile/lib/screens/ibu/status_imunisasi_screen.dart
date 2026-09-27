import 'package:flutter/material.dart';

import '../../models/immunization.dart';
import '../../services/immunization_service.dart';
import '../../widgets/immunization_checklist.dart';
import '../login_screen.dart';

/// Status imunisasi untuk orang tua. Sepenuhnya read-only.
///
/// Tidak ada tombol catat atau ubah di layar ini. Backend juga menolak
/// semua request tulis dari role `ibu`, jadi pembatasan ada di dua sisi.
class StatusImunisasiScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const StatusImunisasiScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<StatusImunisasiScreen> createState() => _StatusImunisasiScreenState();
}

class _StatusImunisasiScreenState extends State<StatusImunisasiScreen> {
  final ImmunizationService _service = ImmunizationService();

  ImmunizationChecklist? _checklist;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _muatChecklist();
  }

  Future<void> _muatChecklist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _service.getChecklist(widget.childId);

    if (!mounted) return;

    if (result['success'] == true &&
        result['data'] is ImmunizationChecklist) {
      setState(() {
        _checklist = result['data'] as ImmunizationChecklist;
        _isLoading = false;
      });
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        backgroundColor: Colors.pink[400],
        foregroundColor: Colors.white,
        title: const Text('Status Imunisasi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatChecklist,
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

    final checklist = _checklist;
    if (checklist == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      color: Colors.pink,
      onRefresh: _muatChecklist,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(checklist),
            const SizedBox(height: 16),
            ImmunizationSummaryCard(summary: checklist.summary),
            const SizedBox(height: 16),
            _buildNextDoseHint(checklist),
            const SizedBox(height: 20),
            ImmunizationChecklistView(checklist: checklist),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ImmunizationChecklist checklist) {
    final nama = checklist.childName.isEmpty
        ? widget.childName
        : checklist.childName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.pink[100]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.pink[200],
            child: const Icon(Icons.child_care, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Riwayat imunisasi',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Menyorot satu dosis yang paling mendesak supaya orang tua tidak perlu
  /// membaca seluruh daftar. Bila semua dosis beres, baru tampil kabar baik.
  Widget _buildNextDoseHint(ImmunizationChecklist checklist) {
    final belum = checklist.pendingItems;

    if (belum.isEmpty) {
      return _buildHint(
        icon: Icons.celebration,
        warna: Colors.green,
        judul: 'Semua dosis sudah lengkap',
        isi: 'Seluruh imunisasi ${checklist.childName} sudah tercatat. '
            'Tetap datang ke posyandu untuk pemeriksaan rutin.',
      );
    }

    final terlambat = belum.where((e) => e.isOverdue).toList();
    final berikutnya = terlambat.isNotEmpty ? terlambat.first : belum.first;

    final warna = immunizationStatusColor(berikutnya.status);

    return _buildHint(
      icon: Icons.priority_high,
      warna: warna,
      judul: berikutnya.isOverdue
          ? 'Ada imunisasi yang terlambat'
          : 'Imunisasi berikutnya',
      isi: '${berikutnya.label} '
          '(${berikutnya.statusNote.toLowerCase()}). '
          'Bawa $checklist.childName ke posyandu agar dapat disuntik.',
    );
  }

  Widget _buildHint({
    required IconData icon,
    required Color warna,
    required String judul,
    required String isi,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warna.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: warna, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: warna,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isi,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ],
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
              onPressed: _muatChecklist,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
