import 'package:flutter/material.dart';

import '../models/immunization.dart';

/// Pemetaan warna per status imunisasi. Dipakai bersama oleh layar Kader
/// (bisa mencatat) dan layar Ibu (hanya membaca) supaya warna di dua layar
/// tidak berbeda jauh.
Color immunizationStatusColor(String status) {
  switch (status) {
    case ImmunizationStatus.done:
      return Colors.green;
    case ImmunizationStatus.overdue:
      return Colors.red;
    default:
      return Colors.orange;
  }
}

IconData immunizationStatusIcon(String status) {
  switch (status) {
    case ImmunizationStatus.done:
      return Icons.check_circle;
    case ImmunizationStatus.overdue:
      return Icons.error;
    default:
      return Icons.pending_outlined;
  }
}

/// Label panjang untuk status, dipakai di header kartu.
String immunizationStatusLabel(String status) {
  switch (status) {
    case ImmunizationStatus.done:
      return 'Sudah';
    case ImmunizationStatus.overdue:
      return 'Terlambat';
    default:
      return 'Belum';
  }
}

/// Daftar dosis read-only.
///
/// [onTapItem] dipakai layar Kader untuk membuka form pencatatan; layar Ibu
/// mengosongkan parameter ini sehingga seluruh daftar tidak bisa diketuk.
class ImmunizationChecklistView extends StatelessWidget {
  final ImmunizationChecklist checklist;
  final void Function(ImmunizationItem item)? onTapItem;

  const ImmunizationChecklistView({
    super.key,
    required this.checklist,
    this.onTapItem,
  });

  @override
  Widget build(BuildContext context) {
    final groups = checklist.groupedByCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          _buildGroupHeader(entry.value.first),
          const SizedBox(height: 8),
          for (final item in entry.value) _buildItemTile(item),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// Judul kelompok diambil dari nama vaksin pada dosis pertama di grup.
  Widget _buildGroupHeader(ImmunizationItem sample) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.vaccines_outlined, size: 18, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sample.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.blue[900],
              ),
            ),
          ),
          Text(
            sample.code,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(ImmunizationItem item) {
    final warna = immunizationStatusColor(item.status);
    final bisaDiketuk = onTapItem != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: bisaDiketuk ? () => onTapItem!(item) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: warna.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  immunizationStatusIcon(item.status),
                  color: warna,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.statusNote,
                        style: TextStyle(
                          fontSize: 12,
                          color: warna,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.record?.notes != null &&
                          item.record!.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.record!.notes!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: warna.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.targetLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: warna,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (bisaDiketuk) ...[
                      const SizedBox(height: 6),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Colors.grey,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartu ringkasan: jumlah sudah / belum / terlambat + progres.
class ImmunizationSummaryCard extends StatelessWidget {
  final ImmunizationSummary summary;

  const ImmunizationSummaryCard({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Kelengkapan Imunisasi',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.blue[900],
                    ),
                  ),
                ),
                Text(
                  '${summary.done}/${summary.total} dosis',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: summary.total == 0 ? 0 : summary.done / summary.total,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation(Colors.green),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStat('Sudah', summary.done, Colors.green),
                _buildStat('Belum', summary.pending, Colors.orange),
                _buildStat('Terlambat', summary.overdue, Colors.red),
                _buildStatProgres(summary.percentDone),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Kolom keempat menampilkan persen, jadi formatnya beda dari tiga
  /// kolom angka biasa.
  Widget _buildStatProgres(int percent) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$percent%',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Progres',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, int value, Color warna) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: warna,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
