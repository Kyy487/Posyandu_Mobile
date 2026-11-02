import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '/../../models/child.dart';
import '/../../models/posyandu_schedule.dart';
import '/../../services/auth_service.dart';
import '/../../services/child_service.dart';
import '/../../services/schedule_service.dart';
import '/../../theme/app_theme.dart';
import '/../../utils/constants.dart';
import '/../screens/shared/login_screen.dart';
import '../data_anak/add_child_screen.dart';
import '../data_anak/detail_anak_screen.dart';
import '../jadwal/jadwal_posyandu_screen.dart';
import '../beranda/kader_beranda_tab.dart';
import '../data_anak/kader_data_anak_tab.dart';
import '../profil/kader_profil_tab.dart';
import '../imunisasi/rekap_imunisasi_screen.dart';
import '../../kalkulator/calculator_screen.dart';

/// Shell Dashboard Kader: bottom navigation melayang 5 slot (Beranda, Jadwal,
/// Scan, Data Anak, Profil) dengan Beranda sebagai tab awal.
///
/// Data anak, profil, dan agenda dimuat sekali di sini lalu dibagikan ke
/// tab-tab, supaya tiap tab tidak memanggil jaringan sendiri-sendiri dan
/// redirect "sesi habis" tetap terjadi saat layar dibuka.
class DashboardKaderScreen extends StatefulWidget {
  const DashboardKaderScreen({super.key});

  @override
  State<DashboardKaderScreen> createState() => _DashboardKaderScreenState();
}

class _DashboardKaderScreenState extends State<DashboardKaderScreen> {
  // Warna khusus bar bawah (mengikuti desain baru).
  static const Color _koral = Color(0xFFF2845C);
  static const Color _ikonRedup = Color(0xFF8FB3B0);

  final ChildService _childService = ChildService();
  final AuthService _authService = AuthService();
  final ScheduleService _scheduleService = ScheduleService();
  final TextEditingController _searchController = TextEditingController();

  List<Child> _allChildren = [];
  List<PosyanduSchedule> _agenda = [];

  bool _isLoading = true;
  String? _errorMessage;
  String _namaKader = '';
  String _cari = '';
  int _selectedIndex = 0;
  int _pendingRegistrations = 0;

  @override
  void initState() {
    super.initState();
    _muatData();
    _muatPendingRegistrations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  String get _waktuSapaan {
    final jam = DateTime.now().hour;
    if (jam < 11) return 'Selamat pagi';
    if (jam < 15) return 'Selamat siang';
    if (jam < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  List<Child> get _filteredChildren {
    if (_cari.isEmpty) return _allChildren;
    final q = _cari.toLowerCase();
    return _allChildren
        .where(
          (child) =>
              child.name.toLowerCase().contains(q) ||
              child.nik.toLowerCase().contains(q),
        )
        .toList();
  }

  /// Memuat anak, profil, dan agenda.
  ///
  /// `getChildren()` tidak pernah melempar exception: kegagalan dikembalikan
  /// sebagai map `success: false`, jadi yang diperiksa adalah `success`.
  Future<void> _muatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final hasil = await _childService.getChildren();
    if (!mounted) return;

    if (hasil['success'] != true) {
      // Sesi habis -> arahkan ke login. Tanpa ini kader terjebak di state
      // error dengan satu-satunya tombol "Coba Lagi" yang akan selalu gagal.
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

    // Profil dan agenda diambil terpisah: kegagalannya tidak boleh
    // menggagalkan daftar anak. Keduanya dijalankan bersamaan (bukan
    // berurutan) supaya Beranda tampil lebih cepat.
    final profilFuture = _authService.getProfile();
    final jadwalFuture = _scheduleService.getSchedules();
    final profil = await profilFuture;
    final jadwal = await jadwalFuture;
    if (!mounted) return;

    final agenda = <PosyanduSchedule>[];
    if (jadwal['success'] == true && jadwal['data'] is List) {
      agenda.addAll(
        (jadwal['data'] as List)
            .whereType<Map>()
            .map((e) => PosyanduSchedule.fromJson(Map<String, dynamic>.from(e)))
            .where((a) => a.status != ScheduleStatus.dibatalkan),
      );
      agenda.sort((a, b) {
        final da = DateTime.tryParse(a.scheduledDate ?? '') ?? DateTime(2100);
        final db = DateTime.tryParse(b.scheduledDate ?? '') ?? DateTime(2100);
        return da.compareTo(db);
      });
    }

    setState(() {
      _namaKader = profil?['name']?.toString() ?? '';
      _allChildren = loaded;
      _agenda = agenda;
      _isLoading = false;
    });
    _muatPendingRegistrations();
  }

  Future<void> _muatPendingRegistrations() async {
    try {
      final token = await _authService.getToken();
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/kader/registrations?status=pending'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return;
      final body = jsonDecode(res.body);
      if (body is Map && body['data'] is List) {
        if (!mounted) return;
        setState(() {
          _pendingRegistrations = (body['data'] as List).length;
        });
      }
    } catch (_) {
      // Biarkan badge tetap 0 jika gagal.
    }
  }

  void _ubahPencarian(String value) {
    setState(() => _cari = value);
  }

  void _pindahTab(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  void _snack(String pesan) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(pesan)));
  }

  void _scanNik() => _snack('Fitur Scan NIK segera hadir');

  Future<void> _keluar() async {
    // Navigator diambil SEBELUM await agar tidak memakai BuildContext setelah
    // async gap.
    final navigator = Navigator.of(context);
    await AuthService().logout();
    if (!mounted) return;
    navigator.pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _bukaDetail(Child child) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DetailAnakScreen(childData: child)),
    ).then((_) => _muatData());
  }

  /// Membuka form tambah anak, lalu menyegarkan daftar bila berhasil.
  Future<void> _tambahAnak() async {
    final berhasil = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddChildScreen()),
    );
    if (berhasil == true) _muatData();
  }

  // Warna menu mengikuti palet desain baru (lebih lembut dari warna dasar).
  List<KaderMenuAksi> get _menu => [
    KaderMenuAksi(
      ikon: Icons.person_add_alt_1_rounded,
      label: 'Validasi Registrasi',
      warna: const Color(0xFFC4502A),
      onTap: () => Navigator.pushNamed(context, '/kader/registrations').then((_) => _muatPendingRegistrations()),
      badgeCount: _pendingRegistrations,
    ),
    KaderMenuAksi(
      ikon: Icons.add_chart_rounded,
      label: 'Input e-KMS',
      warna: const Color(0xFF0E7C7B),
      onTap: () => _tambahAnak(),
    ),
    KaderMenuAksi(
      ikon: Icons.calculate_rounded,
      label: 'Kalkulator',
      warna: const Color(0xFF7C3FBF),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CalculatorScreen())),
    ),
    KaderMenuAksi(
      ikon: Icons.menu_book_rounded,
      label: 'Buku Medis',
      warna: const Color(0xFF4150B8),
      onTap: () => _snack('Pilih pasien untuk melihat Buku Medis'),
    ),
    KaderMenuAksi(
      ikon: Icons.qr_code_scanner_rounded,
      label: 'Scan NIK',
      warna: const Color(0xFF9A6B00),
      onTap: _scanNik,
    ),
    KaderMenuAksi(
      ikon: Icons.calendar_month_rounded,
      label: 'Jadwal Posyandu',
      warna: const Color(0xFF2E7D3A),
      onTap: () => _pindahTab(1),
    ),
    KaderMenuAksi(
      ikon: Icons.vaccines_outlined,
      label: 'Rekap Imunisasi',
      warna: const Color(0xFF8A3A9B),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const RekapImunisasiScreen()),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.kader(),
      child: Scaffold(
        backgroundColor: AppTheme.brandSurface,
        // Pindah tab memudar pelan, bukan berganti mendadak.
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedIndex),
            child: _buildPage(),
          ),
        ),
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 1:
        return const JadwalPosyanduScreen();
      case 2:
        return KaderDataAnakTab(
          children: _filteredChildren,
          isLoading: _isLoading,
          errorMessage: _errorMessage,
          searchController: _searchController,
          cari: _cari,
          onSearch: _ubahPencarian,
          onRefresh: _muatData,
          onAddData: _tambahAnak,
          onOpenChild: _bukaDetail,
        );
      case 3:
        return KaderProfilTab(
          namaKader: _namaKader,
          totalChildren: _allChildren.length,
          totalAgenda: _agenda.length,
        );
      default:
        return KaderBerandaTab(
          waktuSapaan: _waktuSapaan,
          namaKader: _namaKader,
          sapaan: _sapaan,
          isLoading: _isLoading,
          errorMessage: _errorMessage,
          totalChildren: _allChildren.length,
          perluPerhatian: _jumlahPerluPerhatian,
          agenda: _agenda,
          menu: _menu,
          onRefresh: _muatData,
          onSeeAllAgenda: () => _pindahTab(1),
          onLogout: _keluar,
        );
    }
  }

  /// Bar bawah melayang: kapsul gelap membulat, ikon aktif berlatar kotak
  /// teal, dan tombol Scan koral yang menonjol di tengah.
  Widget _buildNavBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SizedBox(
          height: 94, // 68 bar + 26 tonjolan tombol Scan
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.navBar,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _navItem(0, Icons.home_rounded, 'Beranda'),
                    _navItem(1, Icons.calendar_month_rounded, 'Jadwal'),
                    // Slot tengah dikosongkan untuk tombol Scan.
                    const SizedBox(width: 56),
                    _navItem(2, Icons.people_alt_rounded, 'Data Anak'),
                    _navItem(3, Icons.person_rounded, 'Profil'),
                  ],
                ),
              ),
              Positioned(top: 0, child: _tombolScan()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tombolScan() {
    return Tooltip(
      message: 'Scan NIK',
      child: Material(
        color: _koral,
        elevation: 6,
        shadowColor: _koral.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _scanNik,
          borderRadius: BorderRadius.circular(20),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData ikon, String label) {
    final aktif = _selectedIndex == index;

    return Semantics(
      button: true,
      selected: aktif,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: () => _pindahTab(index),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: aktif ? AppTheme.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              ikon,
              size: 24,
              color: aktif ? Colors.white : _ikonRedup,
            ),
          ),
        ),
      ),
    );
  }
}