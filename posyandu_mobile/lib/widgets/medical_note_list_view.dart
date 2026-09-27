/// Widget presentasi untuk catatan keluhan. Dipakai bersama oleh layar Kader
/// dan layar Ibu supaya keduanya tidak pernah menampilkan angka atau label
/// yang berbeda untuk catatan yang sama.
///
/// Perbedaan peran hanya pada `onTap`: Kader mendapat callback untuk mengoreksi,
/// Ibu mendapat null sehingga kartunya tidak bisa diketuk. Backend yang
/// sesungguhnya menolak penulisan dari role `ibu`, jadi ini hanya lapisan UI.
library;

import 'package:flutter/material.dart';

import '../models/medical_note.dart';

/// Warna label tindak lanjut: rujukan selalu merah agar paling menonjol,
/// `sedang` oranye, `ringan` hijau, dan null abu-abu (kader belum memutuskan).
Color medicalNoteTindakLanjutColor(String? value) {
  switch (value) {
    case TindakLanjut.rujuk:
      return Colors.red;
    case TindakLanjut.sedang:
      return Colors.orange[800] ?? Colors.orange;
    case TindakLanjut.ringan:
      return Colors.green;
    default:
      return Colors.grey;
  }
}

/// Ubah `YYYY-MM-DD` jadi "Senin, 15 September 2026".
///
/// Diparse manual, bukan pakai `intl`, mengikuti pola yang sudah dipakai
/// `jadwal_posyandu_screen.dart`. Satu helper tanggal tidak sebanding dengan
/// tambahan dependency untuk aplikasi ini.
String formatTanggalIndo(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return iso ?? '-';

  const hari = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  const bulan = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  return '${hari[d.weekday - 1]}, ${d.day} ${bulan[d.month - 1]} ${d.year}';
}

/// Kartu ringkasan jumlah keluhan di header.
///
/// Angkanya berasal dari server (`summary`), bukan dihitung ulang di sini,
/// supaya Kader dan Ibu melihat angka yang persis sama dengan database.
class MedicalNoteSummaryCard extends StatelessWidget {
  final MedicalNoteSummary summary;
  final Color warna;

  const MedicalNoteSummaryCard({
    super.key,
    required this.summary,
    this.warna = Colors.pink,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warna.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: warna, size: 20),
              const SizedBox(width: 8),
              Text(
                'Ringkasan Keluhan',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: warna,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildKotak('Total Catatan', '${summary.total}', warna),
              const SizedBox(width: 8),
              _buildKotak('Demam', '${summary.demam}', Colors.red),
              const SizedBox(width: 8),
              _buildKotak('Rewel', '${summary.rewel}', Colors.orange),
              const SizedBox(width: 8),
              _buildKotak('Diare', '${summary.diare}', Colors.blueGrey),
            ],
          ),
          if (summary.perluRujuk > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_hospital, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${summary.perluRujuk} catatan perlu rujukan ke fasilitas kesehatan.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKotak(String label, String nilai, Color warnaKotak) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: warnaKotak.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              nilai,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: warnaKotak,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baris hasil satu catatan keluhan.
///
/// [onTap] null membuat kartu tidak bisa diketuk, dipakai di layar Ibu.
class MedicalNoteCard extends StatelessWidget {
  final MedicalNote note;
  final VoidCallback? onTap;
  final bool tampilkanKader;

  const MedicalNoteCard({
    super.key,
    required this.note,
    this.onTap,
    this.tampilkanKader = true,
  });

  @override
  Widget build(BuildContext context) {
    final warnaTindakLanjut = medicalNoteTindakLanjutColor(note.tindakLanjut);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: note.perluRujukan
              ? Colors.red.withValues(alpha: 0.5)
              : Colors.grey[300]!,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatTanggalIndo(note.noteDate),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: warnaTindakLanjut.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      TindakLanjut.label(note.tindakLanjut),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: warnaTindakLanjut,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (note.keluhan.isEmpty)
                const Text(
                  'Tidak ada keluhan dicentang',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in note.keluhan) _buildChipKeluhan(k),
                  ],
                ),
              if (note.catatan != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    note.catatan!,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ],
              if (note.tindakLanjut != null) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.assignment_turned_in_outlined,
                      size: 16,
                      color: warnaTindakLanjut,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        TindakLanjut.petunjuk(note.tindakLanjut!),
                        style: TextStyle(
                          fontSize: 11,
                          color: warnaTindakLanjut,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (tampilkanKader && note.kaderName != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Dicatat oleh ${note.kaderName}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChipKeluhan(String keluhan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Text(
        capitalize(keluhan),
        style: const TextStyle(
          fontSize: 11,
          color: Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

/// Tampilan saat belum ada catatan pada filter yang dipilih.
class MedicalNoteEmptyState extends StatelessWidget {
  final bool semuaBulan;

  const MedicalNoteEmptyState({super.key, this.semuaBulan = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.health_and_safety_outlined, size: 64, color: Colors.pink[200]),
              const SizedBox(height: 16),
              Text(
                semuaBulan ? 'Belum ada catatan keluhan' : 'Belum ada catatan bulan ini',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                semuaBulan
                    ? 'Catatan keluhan yang dicatat kader akan muncul di sini.'
                    : 'Coba pilih "Semua bulan" untuk melihat catatan bulan lalu.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
