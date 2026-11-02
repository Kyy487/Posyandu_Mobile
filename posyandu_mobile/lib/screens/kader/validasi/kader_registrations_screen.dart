import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


import '/../../services/auth_service.dart';
import '/../../utils/constants.dart';

class KaderRegistrationsScreen extends StatefulWidget {
  const KaderRegistrationsScreen({super.key});

  @override
  State<KaderRegistrationsScreen> createState() => _KaderRegistrationsScreenState();
}

class _KaderRegistrationsScreenState extends State<KaderRegistrationsScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late TabController _tabController;
  List _pending = [];
  List _processed = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = await _authService.getToken();
    try {
      final resPending = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/kader/registrations?status=pending'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      final resApproved = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/kader/registrations?status=active'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      final resRejected = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/kader/registrations?status=rejected'),
        headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
      );
      final bodyP = jsonDecode(resPending.body);
      final bodyA = jsonDecode(resApproved.body);
      final bodyR = jsonDecode(resRejected.body);
      final List processed = [];
      if (bodyA['data'] is List) processed.addAll(bodyA['data']);
      if (bodyR['data'] is List) processed.addAll(bodyR['data']);
      processed.sort((a, b) {
        final da = DateTime.tryParse(a['approved_at']?.toString() ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['approved_at']?.toString() ?? '') ?? DateTime(2000);
        return db.compareTo(da);
      });
      setState(() {
        _pending = bodyP['data'] ?? [];
        _processed = processed;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _approve(String id) async {
    final token = await _authService.getToken();
    final res = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/kader/registrations/$id/approve'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Disetujui')));
      _load();
    }
  }

  Future<void> _reject(String id) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tolak Permohonan'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Alasan penolakan'), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tolak')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    final token = await _authService.getToken();
    final res = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/kader/registrations/$id/reject'),
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'rejection_reason': reason.text.trim()}),
    );
    if (res.statusCode == 200) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ditolak')));
      _load();
    }
  }

  void _showDetail(Map<String, dynamic> u) {
    final verifs = u['verifications'] as List? ?? [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Detail Permohonan', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _row('Nama', u['name']),
            _row('NIK', u['nik']),
            _row('No HP', u['phone_number']),
            _row('Tempat/Tanggal Lahir', '${u['place_of_birth'] ?? '-'} / ${u['date_of_birth'] ?? '-'}'),
            _row('Jenis Kelamin', u['gender']),
            _row('Alamat', u['address']),
            const Divider(),
            const Text('Bukti Verifikasi', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (verifs.isEmpty) const Text('Tidak ada file bukti'),
            ...verifs.map((v) {
              final path = v['file_path'];
              final base = ApiConstants.baseUrl.replaceAll('/api', '');
              final urlStr = path != null ? '$base/storage/$path' : null;
              return Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      title: Text(v['file_name'] ?? v['type'] ?? 'Bukti'),
                      subtitle: Text(v['type'] ?? '-'),
                    ),
                    if (urlStr != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: InteractiveViewer(
                                  child: Image.network(
                                    urlStr,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('Gagal memuat gambar'),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              urlStr,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 200,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Text('Gagal memuat gambar'),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            }),
            if (u['status'] == 'pending') ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); _approve(u['id']); }, icon: const Icon(Icons.check), label: const Text('Setujui'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(onPressed: () { Navigator.pop(ctx); _reject(u['id']); }, icon: const Icon(Icons.close), label: const Text('Tolak'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white))),
                ],
              ),
            ],
            if ((u['status'] == 'rejected' || u['status'] == 'active') && u['approved_at'] != null) ...[
              const Divider(),
              _row('Diproses pada', u['approved_at']),
            ],
            if (u['status'] == 'rejected' && u['rejection_reason'] != null) ...[
              const SizedBox(height: 4),
              Text('Alasan Penolakan: ${u['rejection_reason']}', style: const TextStyle(color: Colors.red)),
            ]
          ],
        ),
      ),
    );
  }

  Widget _row(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value?.toString() ?? '-')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Validasi Registrasi Ibu'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Menunggu (${_pending.length})'),
            Tab(text: 'Sudah Diproses (${_processed.length})'),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildList(_pending, true),
                  _buildProcessedList(_processed),
                ],
              ),
      ),
    );
  }

  Widget _buildList(List items, bool pending) {
    if (items.isEmpty) return const Center(child: Text('Tidak ada data'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final u = items[i];
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            onTap: () => _showDetail(Map<String, dynamic>.from(u)),
            title: Text(u['name'] ?? ''),
            subtitle: Text('NIK: ${u['nik'] ?? '-'} | HP: ${u['phone_number'] ?? '-'}'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildProcessedList(List items) {
    if (items.isEmpty) return const Center(child: Text('Tidak ada data'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final u = items[i];
        final status = u['status']?.toString() ?? '-';
        final approvedAt = u['approved_at']?.toString() ?? '-';
        final approver = u['approver'] is Map ? (u['approver']['name']?.toString() ?? '-') : '-';
        final reason = u['rejection_reason']?.toString();
        final subtitle = status == 'rejected'
            ? 'Ditolak • $approvedAt • Oleh: $approver\nAlasan: ${reason ?? '-'}'
            : 'Disetujui • $approvedAt • Oleh: $approver';
        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            onTap: () => _showDetail(Map<String, dynamic>.from(u)),
            title: Text(u['name'] ?? ''),
            subtitle: Text(subtitle),
            isThreeLine: status == 'rejected',
            trailing: Icon(
              status == 'rejected' ? Icons.cancel : Icons.check_circle,
              color: status == 'rejected' ? Colors.red : Colors.green,
            ),
          ),
        );
      },
    );
  }
}
