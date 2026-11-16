import 'dart:math' as math;

import 'package:flutter/material.dart';

import '/../../models/posyandu_schedule.dart';
import '/../../theme/app_theme.dart';

/// Satu tombol pada grid "Menu Utama" Beranda.
class KaderMenuAksi {
  final IconData ikon;
  final String label;
  final Color warna;
  final VoidCallback onTap;
  final int? badgeCount;

  const KaderMenuAksi({
    required this.ikon,
    required this.label,
    required this.warna,
    required this.onTap,
    this.badgeCount,
  });
}

/// Tab "Beranda" Dashboard Kader.
///
/// Susunan: sapaan -> kartu ringkasan (ring progres) -> status gizi ->
/// menu ikon 3 kolom -> agenda terdekat (satu kartu utama + daftar ringkas).
/// Semua data tetap berasal dari layar induk, tanpa pemanggilan jaringan baru.
class KaderBerandaTab extends StatelessWidget {
  final String waktuSapaan;
  final String namaKader;
  final String sapaan;
  final bool isLoading;
  final String? errorMessage;
  final int totalChildren;
  final int perluPerhatian;
  final List<PosyanduSchedule> agenda;
  final List<KaderMenuAksi> menu;
  final Future<void> Function() onRefresh;
  final VoidCallback onSeeAllAgenda;
  final VoidCallback onLogout;

  const KaderBerandaTab({
    super.key,
    required this.waktuSapaan,
    required this.namaKader,
    required this.sapaan,
    required this.isLoading,
    required this.errorMessage,
    required this.totalChildren,
    required this.perluPerhatian,
    required this.agenda,
    required this.menu,
    required this.onRefresh,
    required this.onSeeAllAgenda,
    required this.onLogout,
  });

  // Jarak tepi & antar-bagian dipusatkan di sini supaya ritmenya konsisten.
  static const double _tepi = 20;
  static const double _jarakBagian = 26;

  int get _sehat => (totalChildren - perluPerhatian).clamp(0, totalChildren);

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _header()),
          if (isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorMessage != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(_tepi, 16, _tepi, 0),
                child: _errorCard(),
              ),
            )
          else
            ..._konten(),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  List<Widget> _konten() {
    return [
      SliverToBoxAdapter(
        child: _Muncul(
          index: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_tepi, 6, _tepi, 0),
            child: _kartuRingkasan(),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _Muncul(
          index: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_tepi, 12, _tepi, 0),
            child: _kartuStatus(),
          ),
        ),
      ),
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(_tepi, _jarakBagian, _tepi, 14),
          child: SectionHeader(title: 'Menu Utama'),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: _tepi),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _Muncul(index: 2 + i, child: _menuTile(menu[i])),
            childCount: menu.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_tepi, _jarakBagian, _tepi, 12),
          child: SectionHeader(
            title: 'Agenda terdekat',
            actionLabel: 'Semua',
            onAction: onSeeAllAgenda,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _tepi),
          child: _agenda(),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- HEADER

  Widget _header() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_tepi, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    waktuSapaan,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Halo, $sapaan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    namaKader.isEmpty ? 'Kader Posyandu' : namaKader,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            // Tombol keluar tetap ada selama tab Profil belum menampungnya.
            IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
              color: AppTheme.muted,
              tooltip: 'Keluar',
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- RINGKASAN

  Widget _kartuRingkasan() {
    final progres = totalChildren == 0 ? 0.0 : _sehat / totalChildren;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progres),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, nilai, child) => CustomPaint(
                painter: _RingPainter(nilai),
                child: child,
              ),
              child: Center(
                child: Text(
                  '$totalChildren',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Balita terpantau',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _miniStat(
                        'Sehat',
                        '$_sehat',
                        Icons.favorite_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniStat(
                        'Perhatian',
                        '$perluPerhatian',
                        Icons.monitor_heart_outlined,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String nilai, IconData ikon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ikon, size: 13, color: Colors.white70),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            nilai,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuStatus() {
    final sehat = perluPerhatian == 0;
    final warna = sehat ? AppTheme.success : Colors.orange;
    final ikon = sehat ? Icons.verified_rounded : Icons.warning_amber_rounded;
    final judul = sehat
        ? 'Semua balita sehat'
        : '$perluPerhatian balita perlu perhatian';
    final sub = sehat
        ? 'Tidak ada yang perlu perhatian'
        : 'Buka Data anak untuk melihat status gizi';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(ikon, color: warna, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  judul,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ MENU

  Widget _menuTile(KaderMenuAksi aksi) {
    final badge = aksi.badgeCount ?? 0;
    return InkWell(
      onTap: aksi.onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: aksi.warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(aksi.ikon, color: aksi.warna, size: 26),
              ),
              if (badge > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            aksi.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- AGENDA

  Widget _agenda() {
    if (agenda.isEmpty) {
      return AppCard(
        child: Row(
          children: const [
            Icon(Icons.event_available, color: AppTheme.muted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Belum ada agenda terjadwal.',
                style: TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final items = agenda.take(3).toList();
    final sisa = items.skip(1).toList();

    return Column(
      children: [
        _agendaUtama(items.first),
        if (sisa.isNotEmpty) ...[
          const SizedBox(height: 10),
          _agendaRingkas(sisa),
        ],
      ],
    );
  }

  Widget _agendaUtama(PosyanduSchedule a) {
    final relatif = _relatif(a.scheduledDate);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _bulan(a.scheduledDate).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _hari(a.scheduledDate),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_ikonAgenda(a.title), size: 20, color: AppTheme.brand),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _infoBaris(Icons.schedule_rounded, a.timeLabel),
                _infoBaris(Icons.place_outlined, a.locationName ?? a.location),
                if (relatif.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _chip(relatif),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _agendaRingkas(List<PosyanduSchedule> items) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: AppTheme.muted.withValues(alpha: 0.12),
              ),
            _barisAgenda(items[i]),
          ],
        ],
      ),
    );
  }

  Widget _barisAgenda(PosyanduSchedule a) {
    final tanggal = '${_hari(a.scheduledDate)} ${_bulan(a.scheduledDate)}';
    final info = [a.timeLabel, a.locationName ?? a.location]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join(' - ');
    final relatif = _relatif(a.scheduledDate);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_ikonAgenda(a.title), size: 21, color: AppTheme.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.isEmpty ? tanggal : '$tanggal  -  $info',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                ),
              ],
            ),
          ),
          if (relatif.isNotEmpty) ...[
            const SizedBox(width: 8),
            _chip(relatif),
          ],
        ],
      ),
    );
  }

  Widget _infoBaris(IconData ikon, String? teks) {
    if (teks == null || teks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(ikon, size: 15, color: AppTheme.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              teks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String teks) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        teks,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.brand,
        ),
      ),
    );
  }

  /// Ikon agenda ditebak dari judulnya supaya tiap kegiatan mudah dikenali.
  static IconData _ikonAgenda(String judul) {
    final t = judul.toLowerCase();
    if (t.contains('timbang') || t.contains('ukur')) {
      return Icons.monitor_weight_outlined;
    }
    if (t.contains('vaksin') || t.contains('imunisasi')) {
      return Icons.vaccines_outlined;
    }
    if (t.contains('kunjung')) return Icons.home_outlined;
    return Icons.event_note_outlined;
  }

  // ----------------------------------------------------------------- ERROR

  Widget _errorCard() {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.cloud_off, size: 44, color: AppTheme.muted),
          const SizedBox(height: 12),
          Text(
            errorMessage ?? 'Gagal memuat data.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- TANGGAL

  static const _namaBulan = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static DateTime? _parse(String? iso) {
    if (iso == null) return null;
    return DateTime.tryParse(iso);
  }

  static String _hari(String? iso) {
    final d = _parse(iso);
    return d == null ? '-' : '${d.day}';
  }

  static String _bulan(String? iso) {
    final d = _parse(iso);
    if (d == null) return '';
    return _namaBulan[(d.month - 1).clamp(0, 11)];
  }

  static String _relatif(String? iso) {
    final d = _parse(iso);
    if (d == null) return '';

    final now = DateTime.now();
    final hariIni = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final selisih = target.difference(hariIni).inDays;

    if (selisih == 0) return 'Hari ini';
    if (selisih == 1) return 'Besok';
    if (selisih > 1) return '$selisih hari lagi';
    return 'Lewat';
  }
}

/// Muncul pelan dari bawah (fade + geser) dengan jeda bertingkat per [index].
class _Muncul extends StatelessWidget {
  final int index;
  final Widget child;

  const _Muncul({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final langkah = index > 8 ? 8 : index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + langkah * 60),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 16), child: child),
      ),
      child: child,
    );
  }
}

/// Lingkaran progres putih untuk kartu ringkasan.
class _RingPainter extends CustomPainter {
  final double progres;

  const _RingPainter(this.progres);

  @override
  void paint(Canvas canvas, Size size) {
    const tebal = 10.0;
    final pusat = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - tebal / 2;

    final dasar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tebal
      ..color = Colors.white.withValues(alpha: 0.25);
    canvas.drawCircle(pusat, radius, dasar);

    if (progres <= 0) return;
    final garis = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = tebal
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawArc(
      Rect.fromCircle(center: pusat, radius: radius),
      -math.pi / 2,
      2 * math.pi * progres.clamp(0.0, 1.0),
      false,
      garis,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progres != progres;
}