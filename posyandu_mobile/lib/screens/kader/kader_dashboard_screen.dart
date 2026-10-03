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
  final AuthService _authService = AuthService();

  List<Child> _allChildren = [];
  List<Child> _filteredChildren = [];
  bool _isLoading = true;

  /// Pesan error singkat, null bila tidak ada.
  ///
  /// Sebelumnya error hanya muncul sebagai SnackBar sebentar lalu layar
  /// menganggap daftar kosong - sehingga kader melihat "Tidak ada data anak
  /// ditemukan" padahal server-nya yang gagal.
  String? _errorMessage;

  /// Nama kader dari `GET /api/user`, sama seperti dashboard Ibu.
  ///
  /// Dulu header menampilkan nama Posyandu dan RT/RW yang diketik manual dan
  /// tidak ada di database mana pun.
  String _namaKader = '';

  /// Controller pencarian.
  ///
  /// Diperlukan karena `_fetchChildrenData` menimpa daftar hasil filter.
  /// Tanpa controller, teks di kotak pencarian tetap tampil tapi hasilnya
  /// kembali penuh - jadi yang diketik pengguna hilang tanpa penjelasan.
  final TextEditingController _searchController = TextEditingController();

  String _cari = '';

  // TAMBAHAN: Variabel State untuk melacak tab yang aktif
  String _selectedCategory = 'Balita';

  /// Anak yang status gizinya perlu ditindak lanjuti kader.
  int get _jumlahPerluPerhatian => _allChildren.where((child) {
    final status = child.nutritionalStatus;
    return status == 'Gizi Buruk' || status == 'Gizi Kurang';
  }).length;

  String get _sapaan {
    final parts = _namaKader.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'Kader';
    return parts.first;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchChildrenData();
  }

  // Mengambil data anak dari API
  //
  // `ChildService.getChildren()` tidak pernah melempar exception: semua
  // kegagalan dikembalikan sebagai map dengan `success: false`. Jadi yang
  // diperiksa di sini adalah `success`, bukan `try/catch` - membungkus
  // pemanggilan di `try` lalu mengabaikan hasilnya sama saja dengan tidak
  // memeriksa apa pun.
  Future<void> _fetchChildrenData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasil = await _childService.getChildren();
    if (!mounted) return;

    if (hasil['success'] != true) {
      // Sesi habis -> arahkan ke login, sama seperti dashboard Ibu. Tanpa ini
      // kader terjebak di state error dengan satu-satunya tombol "Coba Lagi"
      // yang akan selalu gagal.
      if (hasil['status'] == 401) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            hasil['message']?.toString() ?? 'Gagal memuat data anak.';
      });
      return;
    }

    final data = hasil['data'];
    final loaded = data is List
        ? data
              .whereType<Map>()
              .map((e) => Child.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <Child>[];

    // Nama kader diambil terpisah: `GET /api/user` hanya dipakai untuk sapaan,
    // dan kegagalannya tidak boleh menggagalkan daftar anak.
    final profile = await _authService.getProfile();
    if (!mounted) return;

    setState(() {
      _namaKader = profile?['name']?.toString() ?? '';
      _allChildren = loaded;
      _isLoading = false;
    });

    // Filter dijalankan ulang setelah data baru masuk supaya pencarian yang
    // sedang diketik tidak hilang begitu selesai di-refresh.
    _filterChildren(_cari);
  }

  // Logika Pencarian
  void _filterChildren(String query) {
    setState(() {
      _cari = query;
      if (query.isEmpty) {
        _filteredChildren = _allChildren;
      } else {
        final searchLower = query.toLowerCase();
        _filteredChildren = _allChildren.where((child) {
          return child.name.toLowerCase().contains(searchLower) ||
              child.nik.toLowerCase().contains(searchLower);
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
                    Text(
                      'Halo, $_sapaan 👋',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _namaKader.isEmpty ? 'Kader Posyandu' : _namaKader,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
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
                          'Perlu Perhatian',
                          '$_jumlahPerluPerhatian',
                          Icons.monitor_heart_outlined,
                          Colors.redAccent,
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
                        // `Expanded` + ellipsis: tanpa itu, `Row` ini meluber
                        // di layar sempit begitu tombol "Tambah Data" bertambah
                        // lebar. `spaceBetween` sendiri tidak membatasi lebar
                        // anak-anaknya.
                        Expanded(
                          child: Text(
                            _selectedCategory == 'Balita'
                                ? 'Daftar Balita'
                                : 'Daftar Ibu Hamil',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
                        controller: _searchController,
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
                      //
                      // Tiga kondisi dipisah: gagal memuat, tidak ada hasil,
                      // dan daftar terisi. Sebelumnya gagal memuat ikut masuk
                      // cabang "kosong", sehingga kader mengira tidak ada anak
                      // terdaftar padahal server-nya yang tidak merespons.
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_errorMessage != null)
                        _buildKegagalan(_errorMessage!)
                      else if (_filteredChildren.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            _cari.isEmpty
                                ? 'Belum ada data anak. Tekan "Tambah Data" untuk mendaftarkan balita pertama.'
                                : 'Tidak ada anak yang cocok dengan "$_cari".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        // Tanpa `shrinkWrap` + `NeverScrollableScrollPhysics`.
                        // Dua kombinasi itu membuat ListView membangun SEMUA
                        // kartu di luar layar, persis membatalkan virtualisasi
                        // yang jadi alasan memakai ListView di tempat pertama.
                        ListView.builder(
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
                                          DetailAnakScreen(childData: child),
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
            // `Expanded` itu wajib, bukan kosmetik: tanpa itu `Column` punya
            // lebar bebas penuh dan teks panjang seperti "Perlu Perhatian"
            // meluber keluar kartu di layar 360dp.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
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

  /// State gagal memuat, dengan tombol coba lagi.
  ///
  /// Dipisah dari state "kosong" karena dua hal itu berbeda bagi kader: satu
  /// berarti server tidak bisa dihubungi, satu lagi berarti memang tidak ada
  /// anak yang cocok. Menyatukan keduanya membuat kader berulang kali membuka
  /// aplikasi tanpa tahu ada masalah.
  Widget _buildKegagalan(String pesan) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            pesan,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _fetchChildrenData,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
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
