import 'package:flutter/material.dart';
import '../../models/child.dart';
import '../../models/measurement_model.dart';
import '../../services/kader_service.dart';
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

  List<MeasurementModel> _riwayat = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRiwayat();
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
          SnackBar(content: Text('Gagal memuat riwayat: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
      ];
      return '${d.day} ${bulan[d.month - 1]} ${d.year}';
    } catch (e) {
      return isoDate;
    }
  }

  MeasurementModel? get _terakhir => _riwayat.isEmpty ? null : _riwayat.first;

  @override
  Widget build(BuildContext context) {
    final terakhir = _terakhir;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue[800],
        title: const Text('Profil Medis Anak', style: TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
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
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fitur edit data anak segera hadir')));
            },
          )
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
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      widget.childData.name.isNotEmpty ? widget.childData.name[0].toUpperCase() : 'A',
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.blue[800]),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.childData.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('NIK: ${widget.childData.nik}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'Ibu: ${widget.childData.parentName}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _hitungUmur(widget.childData.dateOfBirth ?? ''),
                          style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w600, fontSize: 13)
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. STATISTIK PENIMBANGAN TERAKHIR (diambil dari API, bukan hardcode)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📊 Penimbangan Terakhir', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                if (terakhir != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadRiwayat,
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
                    Icon(Icons.monitor_weight_outlined, size: 40, color: Colors.grey),
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
                  _buildStatCard('Berat (BB)', '${terakhir.weightKg} kg', Colors.blue),
                  const SizedBox(width: 10),
                  _buildStatCard('Tinggi (TB)', '${terakhir.heightCm} cm', Colors.purple),
                  const SizedBox(width: 10),
                  _buildStatCard('Status Gizi', terakhir.statusGizi ?? '-', _warnaStatus(terakhir.statusGizi)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _warnaStatus(terakhir.statusGizi).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _warnaStatus(terakhir.statusGizi).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calculate, color: _warnaStatus(terakhir.statusGizi), size: 20),
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
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // 3. RIWAYAT PEMERIKSAAN BERKESINAMBUNGAN (dari API)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('📅 Riwayat Pemeriksaan (${_riwayat.length})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                if (_riwayat.length > 1)
                  TextButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Menampilkan ${_riwayat.length} data penimbangan')),
                      );
                    },
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text('Lihat Semua', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (!_isLoading && _riwayat.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('Belum ada riwayat penimbangan.', style: TextStyle(color: Colors.grey, fontSize: 13)),
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

            // Jarak ekstra di bawah agar konten tidak tertutup oleh tombol FAB
            const SizedBox(height: 80),
          ],
        ),
      ),

      // 4. TOMBOL AKSI INPUT e-KMS
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => InputPenimbanganScreen(childId: widget.childData.id),
            ),
          );
          // Muat ulang riwayat agar Z-Score & Status Gizi ter-update otomatis
          if (saved == true) {
            _loadRiwayat();
          }
        },
        backgroundColor: Colors.blue[800],
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Input Bulan Ini', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
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
            BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
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
                  decoration: BoxDecoration(color: warnaStatus.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.monitor_weight, color: warnaStatus, size: 20),
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLatest)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: warnaStatus.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('TERAKHIR',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.monitor_weight, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(bb, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 16),
                      Icon(Icons.height, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(tb, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: warnaStatus.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: warnaStatus.withValues(alpha: 0.3)),
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
            )
          ],
        ),
      ),
    );
  }
}
