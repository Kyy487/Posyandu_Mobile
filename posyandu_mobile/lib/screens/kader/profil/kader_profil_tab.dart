import 'package:flutter/material.dart';

import '/../../services/auth_service.dart';
import '/../../theme/app_theme.dart';
import '/../../screens/shared/login_screen.dart';
import '/../../screens/kalkulator/calculator_screen.dart';
import 'edit_profil_kader_screen.dart';

/// Tab "Profil" pada Dashboard Kader.
///
/// Sengaja belum dihubungkan ke fitur apa pun: semua menu hanya menampilkan
/// pesan "belum tersedia" (lihat `_belumTersedia`). Tujuannya supaya tampilan
/// profil bisa dilihat dulu, lalu isinya menyusul disesuaikan dengan data yang
/// sudah ada - tanpa mengubah backend.
class KaderProfilTab extends StatelessWidget {
  final String namaKader;
  final int totalChildren;
  final int totalAgenda;

  const KaderProfilTab({
    super.key,
    required this.namaKader,
    required this.totalChildren,
    required this.totalAgenda,
  });

  @override
  Widget build(BuildContext context) {
    final nama = namaKader.isEmpty ? 'Kader Posyandu' : namaKader;

    return ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _header(nama),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _stat(
                  'Balita terpantau',
                  '$totalChildren',
                  Icons.child_care,
                  AppTheme.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _stat(
                  'Agenda',
                  '$totalAgenda',
                  Icons.event_note,
                  AppTheme.brand,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              _menu(context, Icons.person_outline, 'Data diri'),
              _menu(context, Icons.edit_outlined, 'Edit Profil & Sosial Media'),
              _menu(context, Icons.map_outlined, 'Wilayah tugas'),
              _menu(context, Icons.calculate, 'Kalkulator'),
              _menu(context, Icons.notifications_none, 'Pengingat'),
              _menu(context, Icons.help_outline, 'Bantuan'),
              _menu(context, Icons.logout, 'Keluar'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(String nama) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 44,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                nama,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Kader Posyandu',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String nilai, IconData ikon, Color warna) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: warna.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ikon, color: warna, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nilai,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, IconData ikon, String label) {
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        onTap: () {
          if (label == 'Kalkulator') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const CalculatorScreen()));
            return;
          }
          if (label == 'Data diri') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilKaderScreen()));
            return;
          }
          if (label == 'Edit Profil & Sosial Media') {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const EditProfilKaderScreen()));
            return;
          }
          if (label == 'Keluar') {
          AuthService().logout().then((_) {
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          });
          return;
        }
        _belumTersedia(context, label);
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(ikon, color: AppTheme.brand, size: 20),
        ),
        title: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: AppTheme.muted,
          size: 20,
        ),
      ),
    );
  }

  void _belumTersedia(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Menu "$label" belum tersedia.')),
    );
  }
}
