import 'package:flutter/material.dart';

import '/../../models/child.dart';
import '/../../theme/app_theme.dart';
import '/../../utils/status_gizi.dart';

/// Tab "Data Anak" pada Dashboard Kader: pencarian dan daftar balita.
///
/// Tampilan baru: judul dengan jumlah anak, kolom cari dengan tombol scan NIK,
/// pilihan saring berikon beserta jumlahnya (Semua, Sehat, Perhatian, Belum
/// ditimbang), dan daftar yang dimuat bertahap. Dengan begitu data yang banyak
/// tidak perlu digulir panjang.
///
/// Kontrak dengan layar induk tidak berubah, kecuali satu parameter opsional
/// baru [onScan]. Bila null, tombol scan tidak ditampilkan.
///
/// Pencarian tetap dilakukan layar induk (lewat [onSearch] dan [children]).
/// Saringan kategori dan "muat lebih banyak" hanya urusan tampilan di sini.
class KaderDataAnakTab extends StatefulWidget {
  final List<Child> children;
  final bool isLoading;
  final String? errorMessage;
  final TextEditingController searchController;
  final String cari;
  final ValueChanged<String> onSearch;
  final Future<void> Function() onRefresh;
  final VoidCallback onAddData;
  final ValueChanged<Child> onOpenChild;
  final VoidCallback? onScan;

  const KaderDataAnakTab({
    super.key,
    required this.children,
    required this.isLoading,
    required this.errorMessage,
    required this.searchController,
    required this.cari,
    required this.onSearch,
    required this.onRefresh,
    required this.onAddData,
    required this.onOpenChild,
    this.onScan,
  });

  @override
  State<KaderDataAnakTab> createState() => _KaderDataAnakTabState();
}

enum _Saring { semua, sehat, perhatian, belum }

class _KaderDataAnakTabState extends State<KaderDataAnakTab> {
  static const Color _koral = Color(0xFFF2845C);
  static const Color _hijau = Color(0xFF2E7D3A);
  static const Color _merah = Color(0xFFC4502A);

  /// Jumlah anak yang ditampilkan per "halaman". Daftar lengkap sudah ada di
  /// memori; ini hanya menjaga layar tetap ringan dan singkat.
  static const int _ukuranHalaman = 20;

  _Saring _saring = _Saring.semua;
  int _tampil = _ukuranHalaman;

  @override
  void didUpdateWidget(covariant KaderDataAnakTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pencarian baru -> mulai lagi dari halaman pertama.
    if (oldWidget.cari != widget.cari) _tampil = _ukuranHalaman;
  }

  // ---------------------------------------------------------------- SARING

  /// Kategori satu anak. "Perhatian" memakai aturan yang sama dengan Beranda
  /// (Gizi Buruk / Gizi Kurang) supaya angkanya konsisten di semua tempat.
  _Saring _kategori(Child c) {
    final status = c.nutritionalStatus;
    if (status == null || status.isEmpty) return _Saring.belum;
    if (status == 'Gizi Buruk' || status == 'Gizi Kurang') {
      return _Saring.perhatian;
    }
    return _Saring.sehat;
  }

  int _jumlah(_Saring s) {
    if (s == _Saring.semua) return widget.children.length;
    return widget.children.where((c) => _kategori(c) == s).length;
  }

  List<Child> get _terfilter {
    if (_saring == _Saring.semua) return widget.children;
    return widget.children.where((c) => _kategori(c) == _saring).toList();
  }

  void _pilihSaring(_Saring s) {
    if (_saring == s) return;
    setState(() {
      _saring = s;
      _tampil = _ukuranHalaman;
    });
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          _kolomCari(),
          if (!widget.isLoading && widget.errorMessage == null)
            _barisSaring(),
          const SizedBox(height: 8),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _header() {
    final n = widget.children.length;
    final sub = widget.cari.isEmpty ? '$n balita terdaftar' : '$n hasil';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data Anak',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'Tambah anak',
            child: Material(
              color: _koral,
              elevation: 4,
              shadowColor: _koral.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                onTap: widget.onAddData,
                borderRadius: BorderRadius.circular(17),
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.add_rounded, color: Colors.white, size: 26),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kolomCari() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: TextField(
        controller: widget.searchController,
        onChanged: widget.onSearch,
        decoration: InputDecoration(
          hintText: 'Cari nama atau NIK',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: widget.onScan == null
              ? null
              : IconButton(
                  tooltip: 'Scan NIK',
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  color: AppTheme.brand,
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _barisSaring() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip(_Saring.semua, Icons.child_care_rounded, 'Semua', AppTheme.brand),
          _chip(_Saring.sehat, Icons.verified_rounded, 'Sehat', _hijau),
          _chip(
            _Saring.perhatian,
            Icons.monitor_heart_outlined,
            'Perhatian',
            _merah,
          ),
          _chip(
            _Saring.belum,
            Icons.hourglass_empty_rounded,
            'Belum ditimbang',
            AppTheme.muted,
          ),
        ],
      ),
    );
  }

  Widget _chip(_Saring s, IconData ikon, String label, Color warna) {
    final aktif = _saring == s;
    final fg = aktif ? Colors.white : warna;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: aktif ? AppTheme.brand : Colors.white,
        elevation: aktif ? 0 : 1,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: () => _pilihSaring(s),
          borderRadius: BorderRadius.circular(99),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 40,
            padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(ikon, size: 17, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: aktif ? Colors.white : AppTheme.ink,
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
                    '${_jumlah(s)}',
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

  // ------------------------------------------------------------------ BODY

  Widget _buildBody() {
    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.errorMessage != null) {
      return _Kegagalan(
        pesan: widget.errorMessage!,
        onRetry: widget.onRefresh,
      );
    }

    final daftar = _terfilter;

    if (daftar.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _pesanKosong(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted),
              ),
            ),
          ],
        ),
      );
    }

    final terlihat = daftar.take(_tampil).toList();
    final adaSisa = daftar.length > terlihat.length;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: terlihat.length + 1,
        itemBuilder: (context, index) {
          if (index == terlihat.length) {
            return _kaki(terlihat.length, daftar.length, adaSisa);
          }
          return _kartuAnak(terlihat[index]);
        },
      ),
    );
  }

  String _pesanKosong() {
    if (widget.children.isEmpty) {
      return widget.cari.isEmpty
          ? 'Belum ada data anak. Tekan "+" untuk mendaftarkan balita '
                'pertama.'
          : 'Tidak ada anak yang cocok dengan "${widget.cari}".';
    }
    return 'Tidak ada anak pada kategori ini.';
  }

  Widget _kaki(int tampil, int total, bool adaSisa) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Text(
            'Menampilkan $tampil dari $total anak',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.muted),
          ),
          if (adaSisa) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _tampil += _ukuranHalaman),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Muat lebih banyak'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.brand,
                side: BorderSide(color: AppTheme.brand, width: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kartuAnak(Child child) {
    final status = warnaStatusGizi(child.nutritionalStatus);
    final adaStatus = child.nutritionLabel != null;
    final warnaAvatar = adaStatus ? status.warna : AppTheme.muted;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => widget.onOpenChild(child),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: warnaAvatar.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              child.name.isNotEmpty ? child.name[0].toUpperCase() : 'A',
              style: TextStyle(
                color: warnaAvatar,
                fontWeight: FontWeight.w800,
                fontSize: 19,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 13,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        child.ageLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (adaStatus)
            _StatusBadge(
              label: child.nutritionLabel!,
              warna: status.warna,
              ikon: status.ikon,
            )
          else
            const _StatusBadge(
              label: 'Belum ditimbang',
              warna: AppTheme.muted,
              ikon: Icons.hourglass_empty_rounded,
            ),
        ],
      ),
    );
  }
}

/// Chip status gizi memakai pemetaan warna bersama `warnaStatusGizi`.
class _StatusBadge extends StatelessWidget {
  final String label;
  final Color warna;
  final IconData ikon;

  const _StatusBadge({
    required this.label,
    required this.warna,
    required this.ikon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 14, color: warna),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }
}

/// State gagal memuat daftar anak, dengan tombol coba lagi.
class _Kegagalan extends StatelessWidget {
  final String pesan;
  final Future<void> Function() onRetry;

  const _Kegagalan({required this.pesan, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppTheme.muted),
            const SizedBox(height: 12),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}