import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/../../models/immunization.dart';
import '/../../services/immunization_service.dart';
import '/../../screens/shared/login_screen.dart';

// Warna lokal layar ini, mengikuti palet desain Kader. Sengaja tidak memakai
// widget bersama `immunization_checklist.dart` supaya tampilan layar Ibu yang
// memakainya tidak ikut berubah.
const Color _teal = Color(0xFF0E7C7B);
const Color _ink = Color(0xFF12302F);
const Color _muted = Color(0xFF5C7F7C);
const Color _koral = Color(0xFFF2845C);
const Color _permukaan = Color(0xFFF2F6F5);
const Color _hijau = Color(0xFF2E7D3A);
const Color _merah = Color(0xFFC4502A);

/// Gaya tampilan satu status dosis: warna, ikon, dan label singkat.
({Color fg, Color bg, IconData ikon, String label}) _gaya(String status) {
  switch (status) {
    case ImmunizationStatus.done:
      return (
        fg: _hijau,
        bg: const Color(0xFFDDF2E0),
        ikon: Icons.check_circle_rounded,
        label: 'Sudah',
      );
    case ImmunizationStatus.overdue:
      return (
        fg: _merah,
        bg: const Color(0xFFFDE4DA),
        ikon: Icons.warning_amber_rounded,
        label: 'Terlambat',
      );
    default:
      return (
        fg: _muted,
        bg: const Color(0xFFF2F6F5),
        ikon: Icons.schedule_rounded,
        label: 'Belum',
      );
  }
}

/// Checklist imunisasi + pencatatan suntikan untuk Kader.
///
/// Ibu memakai layar read-only terpisah, jadi semua aksi tulis di sini
/// rightful: hanya Kader yang punya akses ke route `/kader/immunizations`.
///
/// Tampilan baru: ringkasan berbentuk lingkaran, saringan status, dan dosis
/// dikelompokkan per usia target sebagai ubin berikon (bukan daftar panjang).
/// Status tetap dibaca dari server; tidak ada yang dihitung ulang di sini.
class ImunisasiScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Kunjungan tempat suntikan baru menempel (opsional).
  ///
  /// Hanya berlaku untuk pencatatan dosis BARU; koreksi dosis lama tetap
  /// mengubah record yang sudah ada dan tidak memindah kunjungannya. Dipakai
  /// alur "buat kunjungan → input data" dari `KunjunganScreen`.
  final String? visitId;

  /// Label kunjungan untuk ditampilkan di banner. Boleh null bila [visitId]
  /// null.
  final String? visitLabel;

  const ImunisasiScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.visitId,
    this.visitLabel,
  });

  @override
  State<ImunisasiScreen> createState() => _ImunisasiScreenState();
}

enum _Saring { semua, terlambat, belum, sudah }

class _ImunisasiScreenState extends State<ImunisasiScreen> {
  final ImmunizationService _service = ImmunizationService();

  ImmunizationChecklist? _checklist;
  bool _isLoading = true;
  String? _errorMessage;
  _Saring _saring = _Saring.semua;

  @override
  void initState() {
    super.initState();
    _muatChecklist();
  }

  Future<void> _muatChecklist() async {
    // Spinner penuh hanya untuk muat pertama; muat ulang berikutnya tidak
    // menghilangkan daftar yang sedang dibaca.
    if (_checklist == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final result = await _service.getChecklist(widget.childId);

    if (!mounted) return;

    if (result['success'] == true && result['data'] is ImmunizationChecklist) {
      setState(() {
        _checklist = result['data'] as ImmunizationChecklist;
        _isLoading = false;
        _errorMessage = null;
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

  /// Membuka form. Dosis yang sudah disuntik berarti koreksi, bukan insert
  /// baru - backend menolak duplikat dengan 422, bukan diam-diam menimpa.
  Future<void> _bukaForm(ImmunizationItem item) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => _FormImunisasi(
        childId: widget.childId,
        item: item,
        service: _service,
        visitId: widget.visitId,
      ),
    );

    if (tersimpan == true) {
      _muatChecklist();
    }
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _permukaan,
      body: Column(
        children: [
          _barAtas(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _barAtas() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Row(
          children: [
            _tombolBar(
              Icons.arrow_back_rounded,
              'Kembali',
              Colors.white,
              _ink,
              () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Imunisasi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
            _tombolBar(
              Icons.refresh_rounded,
              'Muat ulang',
              _teal.withValues(alpha: 0.12),
              _teal,
              _isLoading ? null : _muatChecklist,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tombolBar(
    IconData ikon,
    String tooltip,
    Color latar,
    Color warnaIkon,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              ikon,
              color: onTap == null ? warnaIkon.withValues(alpha: 0.4) : warnaIkon,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _checklist == null) {
      return _buildErrorState(_errorMessage!);
    }

    final checklist = _checklist;
    if (checklist == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    final daftar = _terfilter(checklist);
    final grup = _kelompokkan(daftar);

    return RefreshIndicator(
      onRefresh: _muatChecklist,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          if (widget.visitId != null) ...[
            _buildBannerKunjungan(),
            const SizedBox(height: 12),
          ],
          _kartuAnak(checklist),
          const SizedBox(height: 12),
          _kartuRingkasan(checklist.summary),
          const SizedBox(height: 12),
          _barisSaring(checklist),
          const SizedBox(height: 4),
          if (grup.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'Tidak ada dosis pada kategori ini.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 14, 0, 0),
              child: Text(
                'Ketuk satu dosis untuk mencatat atau mengoreksi suntikan.',
                style: TextStyle(fontSize: 12, color: _muted),
              ),
            ),
            for (final g in grup) _bagianUsia(g.key, g.value),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- SARING

  List<ImmunizationItem> _terfilter(ImmunizationChecklist c) {
    switch (_saring) {
      case _Saring.semua:
        return c.items;
      case _Saring.terlambat:
        return c.items.where((e) => e.isOverdue).toList();
      case _Saring.belum:
        return c.items.where((e) => e.isPending).toList();
      case _Saring.sudah:
        return c.items.where((e) => e.isDone).toList();
    }
  }

  /// Dosis dikelompokkan per usia target, dari yang paling awal.
  List<MapEntry<int?, List<ImmunizationItem>>> _kelompokkan(
    List<ImmunizationItem> items,
  ) {
    final peta = <int?, List<ImmunizationItem>>{};
    for (final item in items) {
      peta.putIfAbsent(item.targetAgeMonths, () => []).add(item);
    }
    final kunci = peta.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return a.compareTo(b);
      });
    return [for (final k in kunci) MapEntry(k, peta[k]!)];
  }

  Widget _barisSaring(ImmunizationChecklist c) {
    int hitung(bool Function(ImmunizationItem) f) => c.items.where(f).length;

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(_Saring.semua, Icons.vaccines_outlined, 'Semua', c.items.length, _teal),
          _chip(
            _Saring.terlambat,
            Icons.warning_amber_rounded,
            'Terlambat',
            hitung((e) => e.isOverdue),
            _merah,
          ),
          _chip(
            _Saring.belum,
            Icons.schedule_rounded,
            'Belum',
            hitung((e) => e.isPending),
            _muted,
          ),
          _chip(
            _Saring.sudah,
            Icons.check_circle_outline_rounded,
            'Sudah',
            hitung((e) => e.isDone),
            _hijau,
          ),
        ],
      ),
    );
  }

  Widget _chip(_Saring s, IconData ikon, String label, int jumlah, Color warna) {
    final aktif = _saring == s;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: aktif ? _teal : Colors.white,
        elevation: aktif ? 0 : 1,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: () => setState(() => _saring = s),
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ikon, size: 17, color: aktif ? Colors.white : warna),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: aktif ? Colors.white : _ink,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: aktif
                        ? Colors.white.withValues(alpha: 0.25)
                        : warna.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$jumlah',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: aktif ? Colors.white : warna,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ KARTU

  BoxDecoration _dekorKartu() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );

  Widget _kartuAnak(ImmunizationChecklist checklist) {
    final nama = checklist.childName.isEmpty
        ? widget.childName
        : checklist.childName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: _dekorKartu(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E7C7B), Color(0xFF14A39A)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              nama.isNotEmpty ? nama[0].toUpperCase() : 'A',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const Text(
                  'Riwayat imunisasi lengkap',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuRingkasan(ImmunizationSummary s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: _dekorKartu(),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => CustomPaint(
                painter: _RingImunisasi(
                  sudah: s.done,
                  terlambat: s.overdue,
                  total: s.total,
                  progres: t,
                ),
                child: child,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${s.done}/${s.total}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      '${s.percentDone}%',
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _legenda(Icons.check_circle_rounded, _hijau, s.done, 'Sudah'),
                const SizedBox(height: 9),
                _legenda(
                  Icons.warning_amber_rounded,
                  _merah,
                  s.overdue,
                  'Terlambat',
                ),
                const SizedBox(height: 9),
                _legenda(Icons.schedule_rounded, _muted, s.pending, 'Belum'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legenda(IconData ikon, Color warna, int jumlah, String label) {
    return Row(
      children: [
        Icon(ikon, size: 18, color: warna),
        const SizedBox(width: 8),
        Text(
          '$jumlah',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    );
  }

  // ------------------------------------------------------------ KELOMPOK USIA

  String _judulUsia(int? bulan) {
    if (bulan == null) return 'Usia belum ditentukan';
    if (bulan == 0) return 'Saat lahir';
    return 'Usia $bulan bulan';
  }

  Widget _bagianUsia(int? bulan, List<ImmunizationItem> items) {
    final selesai = items.where((e) => e.isDone).length;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _judulUsia(bulan),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$selesai/${items.length}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _teal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.86,
            children: [
              for (final item in items)
                _UbinDosis(item: item, onTap: () => _bukaForm(item)),
            ],
          ),
        ],
      ),
    );
  }

  /// Penanda bahwa suntikan baru menempel pada satu kunjungan.
  Widget _buildBannerKunjungan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_available, size: 18, color: _teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suntikan baru menempel pada kunjungan',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _teal,
                  ),
                ),
                if (widget.visitLabel != null)
                  Text(
                    widget.visitLabel!,
                    style: const TextStyle(fontSize: 11, color: _ink),
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
            const Icon(Icons.cloud_off, size: 64, color: _muted),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
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

// =================================================================== WIDGET

/// Satu dosis sebagai ubin berikon. Warna dan ikon mengikuti status dari
/// server; ketuk untuk mencatat atau mengoreksi.
class _UbinDosis extends StatelessWidget {
  final ImmunizationItem item;
  final VoidCallback onTap;

  const _UbinDosis({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = _gaya(item.status);
    final belum = !item.isDone && !item.isOverdue;

    return Material(
      color: Colors.white,
      elevation: 1,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: belum
                ? Border.all(color: const Color(0xFFCFE0DD), width: 1.5)
                : null,
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: Icon(g.ikon, size: 16, color: g.fg),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: g.bg,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(Icons.vaccines_outlined, size: 24, color: g.fg),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Dosis ${item.doseNumber}',
                      style: const TextStyle(fontSize: 10.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lingkaran ringkasan: hijau = sudah, merah = terlambat, sisanya abu muda.
class _RingImunisasi extends CustomPainter {
  final int sudah;
  final int terlambat;
  final int total;
  final double progres;

  const _RingImunisasi({
    required this.sudah,
    required this.terlambat,
    required this.total,
    required this.progres,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const tebal = 12.0;
    final pusat = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - tebal / 2;
    final kotak = Rect.fromCircle(center: pusat, radius: radius);

    canvas.drawCircle(
      pusat,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tebal
        ..color = const Color(0xFFE1ECEA),
    );

    if (total <= 0) return;

    final penuh = 2 * math.pi * progres;
    final sapuSudah = penuh * (sudah / total);
    final sapuTerlambat = penuh * (terlambat / total);

    Paint kuas(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tebal
      ..strokeCap = StrokeCap.butt
      ..color = c;

    if (sapuSudah > 0) {
      canvas.drawArc(kotak, -math.pi / 2, sapuSudah, false, kuas(const Color(0xFF4CB86B)));
    }
    if (sapuTerlambat > 0) {
      canvas.drawArc(
        kotak,
        -math.pi / 2 + sapuSudah,
        sapuTerlambat,
        false,
        kuas(const Color(0xFFE0645A)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingImunisasi old) =>
      old.sudah != sudah ||
      old.terlambat != terlambat ||
      old.total != total ||
      old.progres != progres;
}

/// Form pencatatan / koreksi satu dosis.
///
/// Mengubah dosis yang sudah ada memakai PATCH ke record tersebut, bukan
/// POST baru. Memindahkan catatan ke dosis lain tetap dua operasi terpisah:
/// batalkan dulu, lalu catat ulang pada dosis yang benar.
class _FormImunisasi extends StatefulWidget {
  final String childId;
  final ImmunizationItem item;
  final ImmunizationService service;

  /// Kunjungan tempat dosis baru menempel (opsional). Diabaikan saat koreksi
  /// record lama.
  final String? visitId;

  const _FormImunisasi({
    required this.childId,
    required this.item,
    required this.service,
    this.visitId,
  });

  @override
  State<_FormImunisasi> createState() => _FormImunisasiState();
}

class _FormImunisasiState extends State<_FormImunisasi> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _batchController;
  late final TextEditingController _notesController;
  late DateTime _tanggal;

  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();

    final record = widget.item.record;
    _batchController = TextEditingController(text: record?.batchNumber ?? '');
    _notesController = TextEditingController(text: record?.notes ?? '');

    // Default tanggal suntikan: hari ini, atau tanggal yang sudah tercatat
    // supaya koreksi tidak mengubah tanggal tanpa disadari.
    _tanggal = record?.dateGiven != null
        ? DateTime.tryParse(record!.dateGiven!) ?? DateTime.now()
        : DateTime.now();
  }

  @override
  void dispose() {
    _batchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static const _bulanPanjang = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  String get _tanggalLabel =>
      '${_tanggal.day} ${_bulanPanjang[_tanggal.month - 1]} ${_tanggal.year}';

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      // Batas atas dibatasi hari ini. Suntikan tanggal depan tidak masuk
      // akal dan mudah terjadi karena salah input.
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final existing = widget.item.record;

    final result = existing == null
        ? await widget.service.addRecord(
            childId: widget.childId,
            immunizationTypeId: widget.item.typeId,
            dateGiven: tanggal,
            batchNumber: _batchController.text.trim(),
            notes: _notesController.text.trim(),
            visitId: widget.visitId,
          )
        : await widget.service.updateRecord(
            recordId: existing.id,
            dateGiven: tanggal,
            batchNumber: _batchController.text.trim(),
            notes: _notesController.text.trim(),
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (existing == null
                    ? 'Imunisasi dicatat.'
                    : 'Imunisasi diperbarui.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    String pesan = result['message']?.toString() ?? 'Gagal menyimpan.';
    final errors = result['errors'];
    if (errors is Map) {
      pesan = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Membatalkan suntikan yang tercatat.
  ///
  /// Dipakai saat yang salah adalah dosisnya, bukan tanggal/batch/catatan -
  /// kasus yang tidak bisa ditangani PATCH. Konfirmasi obligatory karena
  /// di lapangan orang salah ketuk bisa berakibat membatalkan catatan benar.
  Future<void> _hapus() async {
    final record = widget.item.record;
    if (record == null) return;

    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan suntikan?'),
        content: Text(
          'Catatan suntikan untuk "${widget.item.label}" akan dibatalkan.\n\n'
          'Data tidak dihapus permanen, dan dosis ini bisa dicatat ulang '
          'nanti bila memang belum diberikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setState(() => _isDeleting = true);

    final result = await widget.service.deleteRecord(recordId: record.id);

    if (!mounted) return;

    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Suntikan dibatalkan.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    final errors = result['errors'];
    var pesan = result['message']?.toString() ?? 'Gagal membatalkan suntikan.';
    if (errors is Map) {
      pesan = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  InputDecoration _dekor(String label, IconData ikon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(ikon),
      filled: true,
      fillColor: _permukaan,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item.record != null;
    final g = _gaya(widget.item.status);
    final subtitle = [
      'Dosis ${widget.item.doseNumber}',
      if (widget.item.targetAgeMonths != null)
        'Usia ${widget.item.targetLabel.toLowerCase()}',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFE0DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: g.bg,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Icon(Icons.vaccines_outlined, size: 30, color: g.fg),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.item.label,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        Text(
                          isEdit ? 'Koreksi pencatatan · $subtitle' : subtitle,
                          style: const TextStyle(fontSize: 12.5, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: g.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(g.ikon, size: 18, color: g.fg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${g.label} · ${widget.item.statusNote}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: g.fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: _permukaan,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _pilihTanggal,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9A6B00).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.calendar_month_rounded,
                            size: 22,
                            color: Color(0xFF9A6B00),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tanggal suntikan',
                                style: TextStyle(fontSize: 12, color: _muted),
                              ),
                              Text(
                                _tanggalLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Text(
                            'Ubah',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _teal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _batchController,
                decoration: _dekor('Nomor Batch (opsional)', Icons.qr_code),
                maxLength: 60,
              ),
              const SizedBox(height: 4),
              TextFormField(
                controller: _notesController,
                decoration: _dekor('Catatan (opsional)', Icons.notes),
                maxLines: 3,
                maxLength: 255,
              ),
              if (isEdit) ...[
                const SizedBox(height: 4),
                const Text(
                  'Bila yang salah adalah dosisnya, gunakan "Batalkan suntikan" '
                  'di bawah lalu catat ulang pada dosis yang benar.',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSaving || _isDeleting ? null : _hapus,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.red,
                          ),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text(
                    'Batalkan suntikan',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: _koral.withValues(alpha: 0.4),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: _isSaving || _isDeleting ? null : _simpan,
                    style: FilledButton.styleFrom(
                      backgroundColor: _koral,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      isEdit ? 'Simpan Perubahan' : 'Simpan Suntikan',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}