import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';

class _Kontak {
  final String nama;
  final String peran;
  final String telepon;

  const _Kontak(this.nama, this.peran, this.telepon);

  String get inisial {
    final bagian = nama.split(' ').where((e) => e.isNotEmpty).toList();
    if (bagian.isEmpty) return '?';
    if (bagian.length == 1) return bagian.first[0].toUpperCase();
    return '${bagian[0][0]}${bagian[1][0]}'.toUpperCase();
  }
}

class KontakScreen extends StatefulWidget {
  const KontakScreen({super.key});

  @override
  State<KontakScreen> createState() => _KontakScreenState();
}

class _KontakScreenState extends State<KontakScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  static const List<_Kontak> _kontak = [
    _Kontak('Sari Wulandari', 'Bidan Desa', '081234567801'),
    _Kontak('Rina Marlina', 'Kader Posyandu', '081234567802'),
    _Kontak('Dewi Lestari', 'Kader Posyandu', '081234567803'),
    _Kontak('Ahmad Fauzi', 'Petugas Puskesmas', '081234567804'),
    _Kontak('Nur Aisyah', 'Bidan Koordinator', '081234567805'),
    _Kontak('Budi Santoso', 'Kepala Desa', '081234567806'),
    _Kontak('Siti Aminah', 'Guru PAUD', '081234567807'),
    _Kontak('Agus Setiawan', 'Ketua RW', '081234567808'),
    _Kontak('Maya Puspita', 'Petugas Gizi', '081234567809'),
    _Kontak('Rudi Hartono', 'Ketua RT', '081234567810'),
    _Kontak('Lina Herlina', 'Kader Posyandu', '081234567811'),
    _Kontak('Fajar Nugroho', 'Petugas Imunisasi', '081234567812'),
    _Kontak('Nia Ramadhani', 'Posyandu Remaja', '081234567813'),
    _Kontak('Hendra Gunawan', 'Ambulans Desa', '081234567814'),
    _Kontak('Dinas Kesehatan', 'Layanan Umum', '081234567815'),
  ];

  static const List<Color> _warna = [
    Color(0xFF0E7C7B),
    Color(0xFF1565C0),
    Color(0xFF7C3FBF),
    Color(0xFFC4502A),
    Color(0xFF2E7D3A),
    Color(0xFF9A6B00),
  ];

  List<_Kontak> get _hasil {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _kontak;
    return _kontak
        .where(
          (kontak) =>
              kontak.nama.toLowerCase().contains(query) ||
              kontak.peran.toLowerCase().contains(query) ||
              kontak.telepon.contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _telepon(String nomor) async {
    final uri = Uri.parse('tel:$nomor');
    final berhasil = await launchUrl(uri);
    if (!mounted) return;
    if (!berhasil) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplikasi telepon tidak tersedia')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasil = _hasil;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B6B69), Color(0xFF1565C0)],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brand.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.contacts_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kontak Posyandu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_kontak.length} kontak penting tersimpan statis',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: 'Cari nama, peran, atau nomor',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        if (hasil.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Column(
              children: const [
                Icon(Icons.search_off_rounded, size: 54, color: AppTheme.muted),
                SizedBox(height: 12),
                Text(
                  'Kontak tidak ditemukan',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(hasil.length, (index) {
            final kontak = hasil[index];
            final warna = _warna[index % _warna.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () => _telepon(kontak.telepon),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: warna.withValues(alpha: 0.14),
                          child: Text(
                            kontak.inisial,
                            style: TextStyle(
                              color: warna,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kontak.nama,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                kontak.peran,
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                kontak.telepon,
                                style: TextStyle(
                                  color: warna,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: warna.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            color: warna,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
