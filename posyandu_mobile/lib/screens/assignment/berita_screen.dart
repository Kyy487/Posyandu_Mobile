import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class _Berita {
  final String judul;
  final String kategori;
  final String tanggal;
  final String ringkasan;
  final String isi;
  final IconData ikon;
  final List<Color> warna;

  const _Berita(
    this.judul,
    this.kategori,
    this.tanggal,
    this.ringkasan,
    this.isi,
    this.ikon,
    this.warna,
  );
}

class BeritaScreen extends StatelessWidget {
  const BeritaScreen({super.key});

  static const List<_Berita> _daftarBerita = [
    _Berita(
      'Posyandu Balita Gelar Pemeriksaan Rutin Bulan Ini',
      'Kegiatan',
      '08 November 2026',
      'Pemeriksaan tumbuh kembang balita kembali digelar di balai desa.',
      'Posyandu Balita menggelar pemeriksaan rutin yang meliputi pengukuran berat badan, tinggi badan, lingkar kepala, serta pemantauan status gizi. Orang tua diimbau membawa buku KIA dan hadir sesuai jadwal yang telah dibagikan oleh kader.',
      Icons.groups_rounded,
      [Color(0xFF0E7C7B), Color(0xFF2FA9A3)],
    ),
    _Berita(
      'Pentingnya Imunisasi Lengkap untuk Anak',
      'Kesehatan',
      '06 November 2026',
      'Imunisasi lengkap membantu melindungi anak dari penyakit yang dapat dicegah.',
      'Imunisasi dasar lengkap diberikan sejak bayi hingga usia 18 bulan. Pastikan jadwal imunisasi anak tidak terlewat dan konsultasikan kepada bidan atau petugas kesehatan bila anak demam setelah imunisasi.',
      Icons.vaccines_rounded,
      [Color(0xFF1565C0), Color(0xFF42A5F5)],
    ),
    _Berita(
      'Menu MPASI Sehat untuk Cegah Stunting',
      'Gizi',
      '04 November 2026',
      'Pola makan bergizi seimbang menjadi kunci pencegahan stunting pada anak.',
      'MPASI yang baik mengandung karbohidrat, protein hewani, sayur, dan buah. Gunakan bahan pangan lokal yang terjangkau, serta hindari pemberian gula dan garam berlebihan pada makanan bayi.',
      Icons.restaurant_rounded,
      [Color(0xFFC4502A), Color(0xFFF2845C)],
    ),
    _Berita(
      'Kader Posyandu Ikuti Pelatihan Antropometri',
      'Pelatihan',
      '02 November 2026',
      'Pengukuran yang tepat membantu deteksi dini masalah gizi pada anak.',
      'Pelatihan ini membahas teknik pengukuran berat dan tinggi badan yang benar, penggunaan alat ukur, serta cara membaca grafik pertumbuhan. Kader diharapkan dapat meningkatkan akurasi data posyandu.',
      Icons.school_rounded,
      [Color(0xFF7C3FBF), Color(0xFFAB7BDB)],
    ),
    _Berita(
      'Jadwal Posyandu Bulan November Telah Dibagikan',
      'Jadwal',
      '01 November 2026',
      'Kader membagikan jadwal kunjungan posyandu ke setiap wilayah.',
      'Jadwal posyandu bulan November dapat dilihat melalui papan informasi desa atau menghubungi kader wilayah masing-masing. Pastikan hadir tepat waktu agar pelayanan berjalan lancar.',
      Icons.event_available_rounded,
      [Color(0xFF2E7D3A), Color(0xFF66BB6A)],
    ),
    _Berita(
      'Cara Menjaga Kesehatan Ibu Hamil',
      'Kesehatan',
      '30 Oktober 2026',
      'Pemeriksaan kehamilan rutin membantu menjaga kesehatan ibu dan janin.',
      'Ibu hamil disarankan memeriksakan kehamilan minimal enam kali selama masa kehamilan. Cukupi kebutuhan gizi, istirahat, dan konsultasikan keluhan yang dirasakan kepada tenaga kesehatan.',
      Icons.favorite_rounded,
      [Color(0xFFAD1457), Color(0xFFEC407A)],
    ),
    _Berita(
      'Pemberian Vitamin A untuk Balita',
      'Gizi',
      '28 Oktober 2026',
      'Vitamin A diberikan secara berkala untuk mendukung daya tahan tubuh.',
      'Pemberian vitamin A dosis tinggi dilakukan setiap Februari dan Agustus. Vitamin A membantu mencegah gangguan penglihatan dan meningkatkan daya tahan tubuh anak terhadap infeksi.',
      Icons.local_pharmacy_rounded,
      [Color(0xFF9A6B00), Color(0xFFD4A72C)],
    ),
    _Berita(
      'Peran Orang Tua dalam Pemantauan Tumbuh Kembang',
      'Parenting',
      '26 Oktober 2026',
      'Orang tua adalah pengamat pertama perubahan tumbuh kembang anak.',
      'Catat berat dan tinggi badan anak secara rutin, perhatikan kemampuan motorik dan bahasa, serta segera konsultasikan bila ada keterlambatan. Buku KIA menjadi panduan penting dalam pemantauan ini.',
      Icons.family_restroom_rounded,
      [Color(0xFF37474F), Color(0xFF607D8B)],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1565C0), Color(0xFF7C3FBF)],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withValues(alpha: 0.24),
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
                  Icons.article_rounded,
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
                      'Berita Posyandu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_daftarBerita.length} berita statis untuk dibaca',
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
        ..._daftarBerita.map((berita) => _kartuBerita(context, berita)),
      ],
    );
  }

  Widget _kartuBerita(BuildContext context, _Berita berita) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => _DetailBeritaScreen(berita: berita),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: berita.judul,
                  child: Container(
                    width: 88,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: berita.warna,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(berita.ikon, color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: berita.warna.first.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              berita.kategori,
                              style: TextStyle(
                                color: berita.warna.first,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            berita.tanggal,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        berita.judul,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        berita.ringkasan,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Text(
                            'Baca selengkapnya',
                            style: TextStyle(
                              color: berita.warna.first,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: berita.warna.first,
                            size: 13,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBeritaScreen extends StatelessWidget {
  final _Berita berita;

  const _DetailBeritaScreen({required this.berita});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.kader(),
      child: Scaffold(
        backgroundColor: AppTheme.brandSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.brandSurface,
          foregroundColor: AppTheme.ink,
          title: const Text('Detail Berita'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Hero(
              tag: berita.judul,
              child: Container(
                height: 210,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: berita.warna,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(berita.ikon, color: Colors.white, size: 82),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: berita.warna.first.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    berita.kategori,
                    style: TextStyle(
                      color: berita.warna.first,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  berita.tanggal,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              berita.judul,
              style: const TextStyle(
                color: AppTheme.ink,
                fontSize: 24,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              berita.ringkasan,
              style: TextStyle(
                color: AppTheme.ink.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              berita.isi,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
