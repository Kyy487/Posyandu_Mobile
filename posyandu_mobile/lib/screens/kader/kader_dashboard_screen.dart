import 'package:flutter/material.dart';

import '../../models/child.dart';
import '../../services/child_service.dart'; // Sesuaikan path service anak Anda
import '../../services/auth_service.dart'; // Untuk logout jika diperlukan
import '../login_screen.dart'; // Sesuaikan path login
import 'detail_anak_screen.dart';
import 'jadwal_posyandu_screen.dart';
import 'rekap_imunisasi_screen.dart';

class DashboardKaderScreen extends StatefulWidget {
  const DashboardKaderScreen({super.key});

  @override
  State<DashboardKaderScreen> createState() => _DashboardKaderScreenState();
}

class _DashboardKaderScreenState extends State<DashboardKaderScreen> {
  final ChildService _childService = ChildService();

  List<Child> _allChildren = [];
  List<Child> _filteredChildren = [];
  bool _isLoading = true;

  // TAMBAHAN: Variabel State untuk melacak tab yang aktif
  String _selectedCategory = 'Balita';

  @override
  void initState() {
    super.initState();
    _fetchChildrenData();
  }

  // Mengambil data anak dari API
  Future<void> _fetchChildrenData() async {
    setState(() => _isLoading = true);
    try {
      final dynamic response = await _childService.getChildren();

      List<Child> loadedChildren = [];

      if (response is List) {
        loadedChildren = response.map((item) => Child.fromJson(item)).toList();
      } else if (response is Map && response.containsKey('data')) {
        final List listData = response['data'];
        loadedChildren = listData.map((item) => Child.fromJson(item)).toList();
      }

      setState(() {
        _allChildren = loadedChildren;
        _filteredChildren = loadedChildren;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat data peserta: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Logika Pencarian
  void _filterChildren(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredChildren = _allChildren;
      } else {
        _filteredChildren = _allChildren.where((child) {
          final nameLower = child.name.toLowerCase();
          final nikLower = child.nik.toLowerCase();
          final searchLower = query.toLowerCase();
          return nameLower.contains(searchLower) ||
              nikLower.contains(searchLower);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue[800],
        title: const Text(
          'Dashboard Kader Posyandu',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              // Navigator diambil SEBELUM await agar tidak memakai BuildContext
              // setelah async gap.
              final navigator = Navigator.of(context);
              await AuthService().logout();
              if (!mounted) return;
              navigator.pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchChildrenData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER SAMBUTAN & RINGKASAN STATISTIK
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[800],
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Halo, Kader Posyandu 👋',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Posyandu Melati 01',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Kartu Statistik Mini
                    Row(
                      children: [
                        _buildStatCard(
                          'Total Balita',
                          '${_allChildren.length}',
                          Icons.child_care,
                          Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Wilayah Binaan',
                          'RT 01 / RW 10',
                          Icons.location_on,
                          Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 2. MENU FITUR CEPAT (SHORTCUTS) DISESUAIKAN MVP
                    const Text(
                      'Menu Utama',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.spaceAround,
                      spacing: 4,
                      runSpacing: 8,
                      children: [
                        _buildMenuButton(
                          Icons.monitor_heart,
                          'Triage',
                          Colors.red,
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Fitur Smart Triage segera hadir',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildMenuButton(
                          Icons.add_chart,
                          'Input e-KMS',
                          Colors.blue,
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Pilih nama anak di bawah untuk input e-KMS',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildMenuButton(
                          Icons.library_books,
                          'Buku Medis',
                          Colors.teal,
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Pilih pasien untuk melihat Buku Medis',
                                ),
                              ),
                            );
                          },
                        ),
                        _buildMenuButton(
                          Icons.qr_code_scanner,
                          'Scan NIK',
                          Colors.indigo,
                          () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Fitur Scan segera hadir'),
                              ),
                            );
                          },
                        ),
                        _buildMenuButton(
                          Icons.event_note,
                          'Jadwal\nPosyandu',
                          Colors.green,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const JadwalPosyanduScreen(),
                              ),
                            );
                          },
                        ),
                        _buildMenuButton(
                          Icons.vaccines,
                          'Rekap\nImunisasi',
                          Colors.purple,
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const RekapImunisasiScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ==========================================
                    // TAMBAHAN: TAB KATEGORI BALITA & IBU HAMIL
                    // ==========================================
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCategory = 'Balita'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedCategory == 'Balita'
                                      ? Colors.blue[800]
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Text(
                                  '👶 Balita',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedCategory == 'Balita'
                                        ? Colors.white
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _selectedCategory = 'Ibu Hamil',
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: _selectedCategory == 'Ibu Hamil'
                                      ? Colors.pink[400]
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Text(
                                  '🤰 Ibu Hamil',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _selectedCategory == 'Ibu Hamil'
                                        ? Colors.white
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. DAFTAR PESERTA (DINAMIS BERDASARKAN TAB)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _selectedCategory == 'Balita'
                              ? 'Daftar Balita'
                              : 'Daftar Ibu Hamil',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Hanya tampilkan tombol Tambah jika di Tab Balita
                        if (_selectedCategory == 'Balita')
                          TextButton.icon(
                            onPressed: () async {
                              // Navigasi ke form tambah anak
                              _fetchChildrenData();
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah Data'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ==========================================
                    // KONDISI TAMPILAN BERDASARKAN KATEGORI
                    // ==========================================
                    if (_selectedCategory == 'Balita') ...[
                      // Search Bar (Hanya tampil di Balita)
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Cari nama anak atau NIK...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
                        ),
                        onChanged: _filterChildren,
                      ),
                      const SizedBox(height: 16),

                      // Daftar Kartu Anak Berdasarkan API
                      _isLoading
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _filteredChildren.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Text(
                                'Tidak ada data anak ditemukan.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _filteredChildren.length,
                              itemBuilder: (context, index) {
                                final Child child = _filteredChildren[index];
                                return Card(
                                  elevation: 1,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue[100],
                                      child: Text(
                                        child.name.isNotEmpty
                                            ? child.name[0].toUpperCase()
                                            : 'A',
                                        style: TextStyle(
                                          color: Colors.blue[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      child.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'NIK: ${child.nik}\nTanggal Lahir: ${child.dateOfBirth}',
                                    ),
                                    isThreeLine: true,
                                    trailing: const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              DetailAnakScreen(
                                                childData: child,
                                              ),
                                        ),
                                      ).then((_) => _fetchChildrenData());
                                    },
                                  ),
                                );
                              },
                            ),
                    ] else ...[
                      // Tampilan Placeholder untuk Tab Ibu Hamil
                      const Padding(
                        padding: EdgeInsets.only(top: 40.0, bottom: 40.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.pregnant_woman,
                                size: 64,
                                color: Colors.pinkAccent,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Data Ibu Hamil belum tersedia.\n(Dalam Pengembangan)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
