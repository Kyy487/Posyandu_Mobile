import 'package:flutter/material.dart';

import '../../models/immunization.dart';
import '../../services/immunization_service.dart';
import '../../widgets/immunization_checklist.dart';
import '../login_screen.dart';

/// Checklist imunisasi + pencatatan suntikan untuk Kader.
///
/// Ibu memakai layar read-only terpisah, jadi semua aksi tulis di sini
/// rightful: hanya Kader yang punya akses ke route `/kader/immunizations`.
class ImunisasiScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ImunisasiScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ImunisasiScreen> createState() => _ImunisasiScreenState();
}

class _ImunisasiScreenState extends State<ImunisasiScreen> {
  final ImmunizationService _service = ImmunizationService();

  ImmunizationChecklist? _checklist;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _muatChecklist();
  }

  Future<void> _muatChecklist() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _service.getChecklist(widget.childId);

    if (!mounted) return;

    if (result['success'] == true && result['data'] is ImmunizationChecklist) {
      setState(() {
        _checklist = result['data'] as ImmunizationChecklist;
        _isLoading = false;
      });
      return;
    }

    if (result['status'] == 401) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat data.';
      _isLoading = false;
    });
  }

  /// Membuka form. Dosis yang sudah disuntik berarti koreksi, bukan insert
  /// baru - backend menolak duplikat dengan 422, bukan diam-diam menimpa.
  Future<void> _bukaForm(ImmunizationItem item) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormImunisasi(
        childId: widget.childId,
        item: item,
        service: _service,
      ),
    );

    if (tersimpan == true) {
      _muatChecklist();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Imunisasi'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatChecklist,
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

    final checklist = _checklist;
    if (checklist == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatChecklist,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(checklist),
            const SizedBox(height: 16),
            ImmunizationSummaryCard(summary: checklist.summary),
            const SizedBox(height: 20),
            const Text(
              'Ketuk salah satu dosis untuk mencatat atau mengoreksi suntikan.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ImmunizationChecklistView(
              checklist: checklist,
              onTapItem: _bukaForm,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ImmunizationChecklist checklist) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.blue[200],
            child: const Icon(Icons.child_care, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  checklist.childName.isEmpty
                      ? widget.childName
                      : checklist.childName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Riwayat imunisasi lengkap',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String pesan) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat data',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _muatChecklist,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form pencatatan / koreksi satu dosis.
///
/// Mengubah dosis yang sudah ada memakai PATCH ke record tersebut, bukan
/// POST baru. Dosis tidak bisa dipindah lewat form ini karena backend
/// tidak punya endpoint untuk memindahkan catatan antar dosis.
class _FormImunisasi extends StatefulWidget {
  final String childId;
  final ImmunizationItem item;
  final ImmunizationService service;

  const _FormImunisasi({
    required this.childId,
    required this.item,
    required this.service,
  });

  @override
  State<_FormImunisasi> createState() => _FormImunisasiState();
}

class _FormImunisasiState extends State<_FormImunisasi> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _batchController;
  late final TextEditingController _notesController;
  late DateTime _tanggal;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final record = widget.item.record;
    _batchController = TextEditingController(text: record?.batchNumber ?? '');
    _notesController = TextEditingController(text: record?.notes ?? '');

    // Default tanggal suntikan: hari ini, atau tanggal yang sudah tercatat
    // supaya koreksi tidak mengubah tanggal tanpa disadari.
    _tanggal = record?.dateGiven != null
        ? DateTime.tryParse(record!.dateGiven!) ?? DateTime.now()
        : DateTime.now();
  }

  @override
  void dispose() {
    _batchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      // Batas atas dibatasi hari ini. Suntikan tanggal depan tidak masuk
      // akal dan mudah terjadi karena salah input.
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final existing = widget.item.record;

    final result = existing == null
        ? await widget.service.addRecord(
            childId: widget.childId,
            immunizationTypeId: widget.item.typeId,
            dateGiven: tanggal,
            batchNumber: _batchController.text.trim(),
            notes: _notesController.text.trim(),
          )
        : await widget.service.updateRecord(
            recordId: existing.id,
            dateGiven: tanggal,
            batchNumber: _batchController.text.trim(),
            notes: _notesController.text.trim(),
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (existing == null ? 'Imunisasi dicatat.' : 'Imunisasi diperbarui.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    String pesan = result['message']?.toString() ?? 'Gagal menyimpan.';
    final errors = result['errors'];
    if (errors is Map) {
      pesan = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item.record != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isEdit ? 'Koreksi Pencatatan' : 'Catat Imunisasi',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                widget.item.label,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: immunizationStatusColor(widget.item.status)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      immunizationStatusIcon(widget.item.status),
                      size: 18,
                      color: immunizationStatusColor(widget.item.status),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      immunizationStatusLabel(widget.item.status),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: immunizationStatusColor(widget.item.status),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 1,
                child: ListTile(
                  leading: const Icon(Icons.calendar_month, color: Colors.blue),
                  title: const Text('Tanggal Suntikan'),
                  subtitle: Text(
                    '${_tanggal.day}/${_tanggal.month}/${_tanggal.year}',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _pilihTanggal,
                    child: const Text('Ubah'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _batchController,
                decoration: const InputDecoration(
                  labelText: 'Nomor Batch (opsional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                ),
                maxLength: 60,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 3,
                maxLength: 255,
              ),
              if (isEdit) ...[
                const SizedBox(height: 4),
                const Text(
                  'Catatan: bila yang salah adalah dosisnya, hapus catatan ini '
                  'lewat backend - dosis tidak bisa dipindah dari layar ini.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _simpan,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  isEdit ? 'Simpan Perubahan' : 'Simpan Imunisasi',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
