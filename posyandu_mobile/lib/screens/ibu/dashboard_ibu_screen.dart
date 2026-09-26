import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../login_screen.dart';

class DashboardIbuScreen extends StatefulWidget {
  const DashboardIbuScreen({super.key});

  @override
  State<DashboardIbuScreen> createState() => _DashboardIbuScreenState();
}

class _DashboardIbuScreenState extends State<DashboardIbuScreen> {
  final String namaIbu = "Siti";
  
  // Dummy Data Daftar Anak
  final List<Map<String, String>> daftarAnak = [
    {"nama": "Budi Santoso", "umur": "2 Tahun 3 Bulan", "jk": "L"},
    {"nama": "Ayu Lestari", "umur": "8 Bulan", "jk": "P"},
  ];
  
  // State untuk melacak anak mana yang sedang dipilih
  int _selectedAnakIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Variabel anak yang sedang aktif
    final anakAktif = daftarAnak[_selectedAnakIndex];

    return Scaffold(
      backgroundColor: Colors.pink[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.pink[400],
        title: const Text('Smart Posyandu Bunda', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () async {
              await AuthService().logout();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. HEADER & PROFILE SWITCHER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 24),
              decoration: BoxDecoration(
                color: Colors.pink[400],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Halo, Bunda $namaIbu 👋', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Memantau Perkembangan Anak:', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  
                  // Horizontal Scroll untuk Daftar Anak
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(daftarAnak.length + 1, (index) {
                        // Jika index terakhir, tampilkan tombol Tambah Anak
                        if (index == daftarAnak.length) {
                          return _buildAddChildButton();
                        }
                        
                        // Render Kartu Anak
                        bool isActive = index == _selectedAnakIndex;
                        return _buildChildSelector(daftarAnak[index], isActive, () {
                          setState(() {
                            _selectedAnakIndex = index;
                          });
                        });
                      }),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2. MENU CEPAT (QUICK ACCESS)
                  const Text('Menu Cepat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.pink.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMenuButton(Icons.camera_alt, 'Sepiring\nBergizi', Colors.orange, () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cek gizi makanan untuk ${anakAktif['nama']}')));
                        }),
                        _buildMenuButton(Icons.auto_graph, 'Grafik\nTumbuh', Colors.blue, () {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buka grafik pertumbuhan ${anakAktif['nama']}')));
                        }),
                        _buildMenuButton(Icons.play_circle_fill, 'Edukasi\n& Tips', Colors.purple, () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buka Video Edukasi')));
                        }),
                        _buildMenuButton(Icons.calendar_month, 'Jadwal\nPosyandu', Colors.teal, () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lihat Jadwal Posyandu')));
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 3. SARAN & INSIGHT (Dinamis berdasarkan anak yang dipilih)
                  Row(
                    children: [
                      const Text('💡 Insight Khusus: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      Expanded(
                        child: Text(
                          anakAktif['nama']!, 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pink[600]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Insight 1
                  _buildInsightCard(
                    icon: Icons.restaurant,
                    iconColor: Colors.orange,
                    title: 'Insight "Sepiring Bergizi"',
                    time: 'Hari Ini',
                    content: 'Makan siang ${anakAktif['nama']} kemarin sudah kaya karbohidrat. Hari ini coba tambahkan protein hewani ya, Bun!',
                  ),

                  // Insight 2
                  _buildInsightCard(
                    icon: Icons.medical_services,
                    iconColor: Colors.blue,
                    title: 'Catatan Kader (Bulan Lalu)',
                    time: 'Bulan Lalu',
                    content: 'Berat badan naik stabil. Z-Score Normal. Terus pertahankan pola makannya yang bergizi.',
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget: Pilihan Anak (Active / Inactive)
  Widget _buildChildSelector(Map<String, String> anak, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isActive ? Colors.white : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              anak['jk'] == 'L' ? Icons.boy : Icons.girl, 
              color: isActive ? Colors.pink[400] : Colors.white, 
              size: 20
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anak['nama']!.split(' ')[0], // Ambil nama panggilan saja
                  style: TextStyle(
                    color: isActive ? Colors.pink[600] : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (isActive) 
                  Text(
                    anak['umur']!,
                    style: TextStyle(color: Colors.pink[300], fontSize: 10, fontWeight: FontWeight.w600),
                  )
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Widget: Tombol Tambah Anak
  Widget _buildAddChildButton() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form Tambah Anak')));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 24),
      ),
    );
  }

  // Widget Bantuan: Tombol Ikon Menu Cepat
  Widget _buildMenuButton(IconData icon, String label, MaterialColor color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color[50],
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color[600], size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label, 
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.2),
          ),
        ],
      ),
    );
  }

  // Widget Bantuan: Kartu Feed Saran/Insight
  Widget _buildInsightCard({required IconData icon, required MaterialColor iconColor, required String title, required String time, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.pink[100]!),
        boxShadow: [
          BoxShadow(color: Colors.pink.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor[600], size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                    Text(time, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(color: Colors.grey[800], fontSize: 13, height: 1.4),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}