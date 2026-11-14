import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'assignment_config.dart';
import 'berita_screen.dart';
import 'biodata_screen.dart';
import 'cuaca_screen.dart';
import 'kalkulator_screen.dart';
import 'kontak_screen.dart';

class AssignmentDashboardScreen extends StatefulWidget {
  const AssignmentDashboardScreen({super.key});

  @override
  State<AssignmentDashboardScreen> createState() =>
      _AssignmentDashboardScreenState();
}

class _AssignmentDashboardScreenState extends State<AssignmentDashboardScreen> {
  static const List<String> _titles = [
    'Biodata',
    'Kontak',
    'Kalkulator',
    'Cuaca',
    'Berita',
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.kader(),
      child: Scaffold(
        backgroundColor: AppTheme.brandSurface,
        appBar: AppBar(
          backgroundColor: AppTheme.brandDark,
          foregroundColor: Colors.white,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                AssignmentConfig.assignmentTitle,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              Text(
                _titles[_index],
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        body: IndexedStack(
          index: _index,
          children: [
            TickerMode(enabled: _index == 0, child: const BiodataScreen()),
            TickerMode(enabled: _index == 1, child: const KontakScreen()),
            TickerMode(enabled: _index == 2, child: const KalkulatorScreen()),
            TickerMode(enabled: _index == 3, child: const CuacaScreen()),
            TickerMode(enabled: _index == 4, child: const BeritaScreen()),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) {
            setState(() => _index = value);
          },
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.brand.withValues(alpha: 0.16),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge_rounded, color: AppTheme.brand),
              label: 'Biodata',
            ),
            NavigationDestination(
              icon: Icon(Icons.contacts_outlined),
              selectedIcon: Icon(Icons.contacts_rounded, color: AppTheme.brand),
              label: 'Kontak',
            ),
            NavigationDestination(
              icon: Icon(Icons.calculate_outlined),
              selectedIcon: Icon(
                Icons.calculate_rounded,
                color: AppTheme.brand,
              ),
              label: 'Kalkulator',
            ),
            NavigationDestination(
              icon: Icon(Icons.cloud_outlined),
              selectedIcon: Icon(Icons.cloud_rounded, color: AppTheme.brand),
              label: 'Cuaca',
            ),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article_rounded, color: AppTheme.brand),
              label: 'Berita',
            ),
          ],
        ),
      ),
    );
  }
}
