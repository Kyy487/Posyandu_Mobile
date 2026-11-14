import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class _JamCuaca {
  final String jam;
  final IconData ikon;
  final String suhu;

  const _JamCuaca(this.jam, this.ikon, this.suhu);
}

class _HariCuaca {
  final String hari;
  final IconData ikon;
  final String kondisi;
  final String rendah;
  final String tinggi;

  const _HariCuaca(
    this.hari,
    this.ikon,
    this.kondisi,
    this.rendah,
    this.tinggi,
  );
}

class CuacaScreen extends StatefulWidget {
  const CuacaScreen({super.key});

  @override
  State<CuacaScreen> createState() => _CuacaScreenState();
}

class _CuacaScreenState extends State<CuacaScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hujan = false;

  static const List<_JamCuaca> _perJam = [
    _JamCuaca('09.00', Icons.wb_sunny_rounded, '27°'),
    _JamCuaca('10.00', Icons.wb_sunny_rounded, '28°'),
    _JamCuaca('11.00', Icons.cloud_rounded, '29°'),
    _JamCuaca('12.00', Icons.cloud_rounded, '30°'),
    _JamCuaca('13.00', Icons.water_drop_rounded, '28°'),
    _JamCuaca('14.00', Icons.cloud_rounded, '27°'),
  ];

  static const List<_HariCuaca> _prakiraan = [
    _HariCuaca('Senin', Icons.wb_sunny_rounded, 'Cerah', '22°', '30°'),
    _HariCuaca('Selasa', Icons.cloud_rounded, 'Berawan', '23°', '29°'),
    _HariCuaca('Rabu', Icons.water_drop_rounded, 'Hujan', '21°', '27°'),
    _HariCuaca('Kamis', Icons.cloud_rounded, 'Berawan', '22°', '28°'),
    _HariCuaca('Jumat', Icons.wb_sunny_rounded, 'Cerah', '23°', '31°'),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ubahCuaca() {
    setState(() => _hujan = !_hujan);
  }

  @override
  Widget build(BuildContext context) {
    final warnaAtas = _hujan
        ? const Color(0xFF203A56)
        : const Color(0xFF087E8B);
    final warnaBawah = _hujan
        ? const Color(0xFF455A75)
        : const Color(0xFF2FA9A3);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        GestureDetector(
          onTap: _ubahCuaca,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [warnaAtas, warnaBawah],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: warnaAtas.withValues(alpha: 0.3),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Bandung, Jawa Barat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: const Text(
                        'Data statis',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 190,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return _visualCuaca(_controller.value);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _hujan ? '24°' : '27°',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 58,
                        height: 0.9,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hujan ? 'Hujan Ringan' : 'Cerah Berawan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Terasa seperti ${_hujan ? '26' : '29'}°C',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _hujan
                          ? Icons.water_drop_rounded
                          : Icons.wb_sunny_rounded,
                      color: Colors.white.withValues(alpha: 0.86),
                      size: 54,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.touch_app_rounded,
                      color: Colors.white.withValues(alpha: 0.65),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Ketuk kartu untuk mengubah animasi cuaca',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _gridDetail(),
        const SizedBox(height: 16),
        _kartuPerJam(),
        const SizedBox(height: 16),
        _kartuPrakiraan(),
      ],
    );
  }

  Widget _visualCuaca(double progress) {
    final ayun = math.sin(progress * math.pi * 2);
    final ayunDua = math.cos(progress * math.pi * 2);
    final skalaMatahari = 1 + (math.sin(progress * math.pi * 4) * 0.04);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        if (!_hujan)
          Positioned(
            top: 8,
            right: 34,
            child: Transform.scale(
              scale: skalaMatahari,
              child: Transform.rotate(
                angle: progress * math.pi * 2,
                child: Icon(
                  Icons.wb_sunny_rounded,
                  size: 112,
                  color: Colors.amber.shade300,
                ),
              ),
            ),
          ),
        if (!_hujan)
          Positioned(
            top: 0,
            right: 14,
            child: Container(
              width: 152,
              height: 152,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.12),
              ),
            ),
          ),
        if (_hujan)
          Positioned.fill(
            child: CustomPaint(painter: _RainPainter(progress: progress)),
          ),
        Positioned(
          top: 52 + (ayun * 6),
          left: 42 + (ayun * 10),
          child: Icon(
            Icons.cloud_rounded,
            size: 92,
            color: Colors.white.withValues(alpha: 0.94),
          ),
        ),
        Positioned(
          top: 22 + (ayunDua * 5),
          left: 106 + (ayunDua * 14),
          child: Icon(
            Icons.cloud_rounded,
            size: 122,
            color: Colors.white.withValues(alpha: 0.86),
          ),
        ),
        Positioned(
          top: 104 + (ayun * 4),
          right: 36 + (ayun * 12),
          child: Icon(
            Icons.cloud_rounded,
            size: 62,
            color: Colors.white.withValues(alpha: 0.66),
          ),
        ),
        Positioned(
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              _hujan ? 'Animasi hujan aktif' : 'Animasi cerah aktif',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _gridDetail() {
    final detail = [
      ('Kelembapan', _hujan ? '86%' : '78%', Icons.water_drop_outlined),
      ('Kecepatan angin', _hujan ? '16 km/j' : '12 km/j', Icons.air_rounded),
      ('Tekanan udara', '1.012 hPa', Icons.speed_rounded),
      ('Indeks UV', _hujan ? '2' : '6', Icons.wb_sunny_outlined),
      ('Jarak pandang', _hujan ? '6 km' : '10 km', Icons.visibility_outlined),
      ('Titik embun', '22°C', Icons.thermostat_rounded),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.02,
      children: [
        for (final item in detail)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.$3, color: AppTheme.brand, size: 21),
                const SizedBox(height: 10),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.$1,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kartuPerJam() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Perkiraan per jam',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 98,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _perJam.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _perJam[index];
                return Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.jam,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(item.ikon, color: AppTheme.brand, size: 22),
                      Text(
                        item.suhu,
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuPrakiraan() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prakiraan 5 hari',
            style: TextStyle(
              color: AppTheme.ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in _prakiraan)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(
                      item.hari,
                      style: const TextStyle(
                        color: AppTheme.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(item.ikon, color: AppTheme.brand, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.kondisi,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${item.rendah} / ${item.tinggi}',
                    style: const TextStyle(
                      color: AppTheme.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  final double progress;

  const _RainPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 34; i++) {
      final seedX = (i * 47) % 233;
      final x = (seedX / 233) * size.width;
      final offset = (i * 83) % 97;
      final y = ((offset / 97) + progress + (i * 0.037)) % 1;
      final startY = y * size.height;
      canvas.drawLine(Offset(x, startY), Offset(x - 4, startY + 14), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
