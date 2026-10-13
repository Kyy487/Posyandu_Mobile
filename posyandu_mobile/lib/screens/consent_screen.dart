import 'package:flutter/material.dart';

import '../models/consent.dart';
import '../services/consent_service.dart';
import 'login_screen.dart';

/// Layar persetujuan pemrosesan data anak (UU PDP).
///
/// Dipakai bersama oleh dua peran:
/// - Ibu/wali: [bisaMengelola] `true` - boleh memberi dan mencabut consent.
/// - Kader: [bisaMengelola] `false` - hanya melihat status yang sudah ada,
///   karena `POST`/`DELETE /children/{id}/consents` khusus Ibu/wali.
///
/// Semua tipe di [ConsentTipe.semua] selalu ditampilkan (bukan hanya yang
/// sudah diberikan) supaya ibu tahu persetujuan mana yang belum diberikan.
class ConsentScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Menentukan tombol beri/cabut muncul atau tidak.
  final bool bisaMengelola;

  const ConsentScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.bisaMengelola = false,
  });

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final ConsentService _service = ConsentService();

  List<Consent> _data = const [];
  bool _isLoading = true;
  String? _errorMessage;

  /// Tipe yang sedang diproses (beri/cabut) supaya tombolnya bisa disabled.
  String? _proses;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _service.getByChild(widget.childId);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is List<Consent>) {
      setState(() {
        _data = result['data'] as List<Consent>;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Gagal memuat data persetujuan.';
      _isLoading = false;
    });
  }

  /// Mencari consent aktif untuk satu tipe.
  Consent? _cari(String tipe) {
    for (final item in _data) {
      if (item.consentType == tipe && item.aktif) return item;
    }
    return null;
  }

  Future<void> _beri(String tipe) async {
    setState(() => _proses = tipe);

    final result = await _service.grant(
      childId: widget.childId,
      consentType: tipe,
    );

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    setState(() => _proses = null);
    _pesan(
      result['success'] == true
          ? 'Persetujuan ${ConsentTipe.label(tipe)} diberikan.'
          : result['message']?.toString() ?? 'Gagal memberi persetujuan.',
      sukses: result['success'] == true,
    );

    if (result['success'] == true) _muatData();
  }

  Future<void> _cabut(String tipe) async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cabut persetujuan?'),
        content: Text(
          'Persetujuan ${ConsentTipe.label(tipe)} akan dicabut. Riwayat medis '
          'yang sudah tercatat tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red[700]),
            child: const Text('Cabut'),
          ),
        ],
      ),
    );

    if (setuju != true || !mounted) return;

    setState(() => _proses = tipe);

    final result = await _service.revoke(
      childId: widget.childId,
      consentType: tipe,
    );

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    setState(() => _proses = null);
    _pesan(
      result['success'] == true
          ? 'Persetujuan ${ConsentTipe.label(tipe)} dicabut.'
          : result['message']?.toString() ?? 'Gagal mencabut persetujuan.',
      sukses: result['success'] == true,
    );

    if (result['success'] == true) _muatData();
  }

  void _pesan(String message, {required bool sukses}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: sukses ? Colors.green[700] : Colors.red[700],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Persetujuan Data'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatData,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildIntro(),
          for (final tipe in ConsentTipe.semua) _buildKartu(tipe),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.privacy_tip_outlined, color: Colors.blue[700], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.bisaMengelola
                  ? 'Atur persetujuan pemrosesan data untuk ${widget.childName}. '
                        'Persetujuan bisa dicabut kapan saja.'
                  : 'Persetujuan pemrosesan data ${widget.childName} diberikan '
                        'oleh ibu/wali. Kader hanya dapat melihat.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKartu(String tipe) {
    final consent = _cari(tipe);
    final aktif = consent != null;
    final sedangProses = _proses == tipe;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: aktif ? Colors.green[200]! : Colors.grey[300]!,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ConsentTipe.label(tipe),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatus(aktif, consent),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              ConsentTipe.deskripsi(tipe),
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            if (aktif) ...[
              const SizedBox(height: 8),
              Text(
                'Disetujui ${consent.tanggalLabel}'
                '${consent.documentVersion != null ? ' • v${consent.documentVersion}' : ''}',
                style: TextStyle(fontSize: 11.5, color: Colors.green[800]),
              ),
            ],
            if (widget.bisaMengelola) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: aktif
                    ? OutlinedButton.icon(
                        onPressed: sedangProses ? null : () => _cabut(tipe),
                        icon: sedangProses
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cancel_outlined, size: 18),
                        label: const Text('Cabut'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[700],
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: sedangProses ? null : () => _beri(tipe),
                        icon: sedangProses
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Beri Persetujuan'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(bool aktif, Consent? consent) {
    final color = aktif ? Colors.green[700]! : Colors.grey[600]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            aktif ? Icons.verified : Icons.remove_circle_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            aktif ? 'Aktif' : 'Belum',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _muatData,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
