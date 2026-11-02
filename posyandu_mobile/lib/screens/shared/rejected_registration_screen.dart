import 'package:flutter/material.dart';

import '/../theme/app_theme.dart';

import 'registration_completion_screen.dart';

class RejectedRegistrationScreen extends StatelessWidget {
  final Map<String, dynamic>? user;

  const RejectedRegistrationScreen({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    final reason = user?['rejection_reason'] ?? '-';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pendaftaran Ditolak'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cancel, size: 64, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text('Permohonan pendaftaran kamu ditolak', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('Alasan penolakan:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(reason),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RegistrationCompletionScreen()),
                  );
                },
                child: const Text('Perbaiki & Kirim Ulang'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
