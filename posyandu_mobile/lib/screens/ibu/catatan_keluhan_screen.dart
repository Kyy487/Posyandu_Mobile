import 'package:flutter/material.dart';

import '../../models/medical_note.dart';
import '../../services/medical_note_service.dart';
import '../../widgets/medical_note_list_view.dart';
import '../login_screen.dart';

/// Catatan keluhan untuk orang tua. Sepenuhnya read-only.
///
/// Tidak ada tombol catat, ubah, atau batalkan di layar ini. Backend juga
/// menolak semua request tulis dari role `ibu` karena seluruh endpoint tulis
/// berada di prefix `/kader/`, jadi pembatasan ada di dua sisi.
///
/// Angka ringkasan dikirim server, sehingga total catatan yang dilihat Ibu
/// sama persis dengan yang dilihat kader di posyandu.
class CatatanKeluhanScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const CatatanKeluhanScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<CatatanKeluhanScreen> createState() => _CatatanKeluhanScreenState();
}

class _CatatanKeluhanScreenState extends State<CatatanKeluhanScreen> {
  final MedicalNoteService _service = MedicalNoteService();

  MedicalNoteList? _data;
  bool _isLoading = true;
  String? _errorMessage;

  /// null = bulan berjalan. Ibu bisa buka bulan lalu supaya bisa mengecek
  /// keluhan sebelum kunjungan posyandu terakhir.
  String? _bulanDipilih;

  /// Daftar bulan yang punya catatan, plus bulan berjalan, supaya orang tua
  /// tidak perlu menebak bulan mana yang perlu dibuka.
  List<String> _pilihanBulan = [];

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

    final result = await _service.getNotes(
      widget.childId,
      month: _bulanDipilih,
    );

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is MedicalNoteList) {
      setState(() {
        _data = result['data'] as MedicalNoteList;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat catatan.';
      _isLoading = false;
    });
  }

  Future<void> _pilihBulan() async {
    final dipilih = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Pilih bulan',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            for (final bulan in _pilihanBulan)
              ListTile(
                leading: Icon(
                  bulan == _bulanDipilih
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: Colors.pink,
                ),
                title: Text(_labelBulan(bulan)),
                onTap: () => Navigator.of(context).pop(bulan),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (dipilih == null) return;

    setState(() {
      _bulanDipilih = dipilih == _bulanSekarang() ? null : dipilih;
    });
    _muatData();
  }

  static String _bulanSekarang() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  static String _labelBulan(String? bulan) {
    if (bulan == null || bulan.isEmpty) return 'Bulan ini';

    final bagian = bulan.split('-');
    if (bagian.length != 2) return bulan;

    const namaBulan = [
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

    final index = int.tryParse(bagian[1]);
    if (index == null || index < 1 || index > 12) return bulan;

    return '${namaBulan[index - 1]} ${bagian[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        backgroundColor: Colors.pink[400],
        foregroundColor: Colors.white,
        title: const Text('Catatan Keluhan'),
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
      return const Center(child: CircularProgressIndicator(color: Colors.pink));
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    if (_pilihanBulan.isEmpty) {
      _pilihanBulan = [_bulanSekarang(), if (data.month != null) data.month!];
    }

    return RefreshIndicator(
      color: Colors.pink,
      onRefresh: _muatData,
      child: Column(
        children: [
          _buildFilterBar(data),
          Expanded(
            child: data.notes.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [MedicalNoteEmptyState()],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: data.notes.length,
                    itemBuilder: (context, index) => MedicalNoteCard(
                      // onTap sengaja null: Ibu hanya boleh membaca.
                      note: data.notes[index],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(MedicalNoteList data) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.childName.isEmpty ? widget.childName : data.childName,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pilihBulan,
            icon: const Icon(Icons.calendar_month, size: 16),
            label: Text(
              _bulanDipilih == null ? 'Bulan ini' : _labelBulan(_bulanDipilih),
              style: const TextStyle(fontSize: 12),
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
              'Gagal memuat catatan',
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
}
