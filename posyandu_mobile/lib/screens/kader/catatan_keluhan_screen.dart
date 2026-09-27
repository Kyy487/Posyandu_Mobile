import 'package:flutter/material.dart';

import '../../models/medical_note.dart';
import '../../services/medical_note_service.dart';
import '../../widgets/medical_note_list_view.dart';
import '../login_screen.dart';

/// Catatan keluhan untuk Kader: daftar, catat baru, koreksi, dan batalkan.
///
/// Kader memakai layar terpisah dari Ibu karena endpoint tulisnya ada di
/// prefix `/kader/`. Role `ibu` tidak akan pernah sampai ke sini lewat UI,
/// dan backend juga menolak request tulis dari role tersebut.
class CatatanKeluhanScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Id penimbangan yang dipakai bila kader mencatat keluhan sekaligus
  /// menimbang. Null berarti catatan tetap sah tanpa penimbangan, karena
  /// anak bisa mengeluh tanpa ditimbang hari itu juga.
  final String? measurementId;

  const CatatanKeluhanScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.measurementId,
  });

  @override
  State<CatatanKeluhanScreen> createState() => _CatatanKeluhanScreenState();
}

class _CatatanKeluhanScreenState extends State<CatatanKeluhanScreen> {
  final MedicalNoteService _service = MedicalNoteService();

  MedicalNoteList? _data;
  bool _isLoading = true;
  String? _errorMessage;

  /// null = bulan berjalan, true = semua bulan.
  bool _semuaBulan = false;

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

    final result = await _service.getNotes(
      widget.childId,
      all: _semuaBulan,
    );

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is MedicalNoteList) {
      setState(() {
        _data = result['data'] as MedicalNoteList;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat catatan.';
      _isLoading = false;
    });
  }

  Future<void> _bukaForm({MedicalNote? note}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormCatatanKeluhan(
        childId: widget.childId,
        service: _service,
        note: note,
        measurementId: widget.measurementId,
      ),
    );

    if (tersimpan == true) {
      _muatData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catatan Keluhan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatData,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bukaForm,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Catat Keluhan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[800],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: Column(
        children: [
          _buildFilterBar(data),
          Expanded(
            child: data.notes.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [MedicalNoteEmptyState(semuaBulan: _semuaBulan)],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: data.notes.length,
                    itemBuilder: (context, index) => MedicalNoteCard(
                      note: data.notes[index],
                      onTap: () => _bukaForm(note: data.notes[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(MedicalNoteList data) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              data.labelFilter,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Switch(
            value: _semuaBulan,
            onChanged: (v) {
              setState(() => _semuaBulan = v);
              _muatData();
            },
          ),
          const Text(
            'Semua bulan',
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
            Icon(Icons.cloud_off, size: 64, color: Colors.blue[200]),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat catatan',
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
              onPressed: _muatData,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form catatan keluhan dalam bottom sheet.
///
/// Satu form melayani dua mode. [note] null berarti membuat catatan baru;
/// filled berarti mengoreksi catatan yang sudah ada. Bedanya penting karena
/// backend menolak duplikat tanggal dengan 422 - revise the existing record is
/// the correct response, not recording a new one.
class _FormCatatanKeluhan extends StatefulWidget {
  final String childId;
  final MedicalNoteService service;
  final MedicalNote? note;
  final String? measurementId;

  const _FormCatatanKeluhan({
    required this.childId,
    required this.service,
    this.note,
    this.measurementId,
  });

  @override
  State<_FormCatatanKeluhan> createState() => _FormCatatanKeluhanState();
}

class _FormCatatanKeluhanState extends State<_FormCatatanKeluhan> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _catatanController = TextEditingController();

  late DateTime _tanggal;
  late bool _demam;
  late bool _rewel;
  late bool _diare;
  String? _tindakLanjut;

  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isEdit => widget.note != null;

  @override
  void initState() {
    super.initState();

    final note = widget.note;
    _tanggal = DateTime.tryParse(note?.noteDate ?? '') ?? DateTime.now();
    _demam = note?.demam ?? false;
    _rewel = note?.rewel ?? false;
    _diare = note?.diare ?? false;
    _tindakLanjut = note?.tindakLanjut;
    _catatanController.text = note?.catatan ?? '';
  }

  @override
  void dispose() {
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  /// Validasi lokal yang mencerminkan CHECK constraint di database.
  ///
  /// Server tetap memvalidasi ulang - ini hanya supaya kader mendapat umpan
  /// balik cepat tanpa satu putaran jaringan, dan supaya alasan tidaknya
  /// catatan bisa disimpan terlihat sebelum menekan tombol.
  ///
  /// Mengembalikan null berarti isi catatan sudah sah.
  String? _validasiIsi() {
    if (!_demam && !_rewel && !_diare && _catatanController.text.trim().isEmpty) {
      return 'Centang minimal satu keluhan, atau isi catatan.';
    }
    return null;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final pesanLokal = _validasiIsi();
    if (pesanLokal != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pesanLokal), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final catatan = _catatanController.text.trim();

    final result = _isEdit
        ? await widget.service.updateNote(
            noteId: widget.note!.id,
            noteDate: tanggal,
            demam: _demam,
            rewel: _rewel,
            diare: _diare,
            catatan: catatan,
            tindakLanjut: _tindakLanjut,
          )
        : await widget.service.addNote(
            childId: widget.childId,
            noteDate: tanggal,
            demam: _demam,
            rewel: _rewel,
            diare: _diare,
            catatan: catatan,
            tindakLanjut: _tindakLanjut,
            measurementId: widget.measurementId,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit ? 'Catatan diperbarui.' : 'Catatan keluhan tersimpan.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_pesanError(result)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Membatalkan catatan yang keliru tercatat.
  ///
  /// Yang biasanya salah adalah tanggalnya, bukan keluhan anak. Karena tanggal
  /// boleh diubah lewat PATCH, pembatalan sebaiknya jadi pilihan terakhir -
  /// untuk salah tanggal, pilih Ubah saja.
  Future<void> _hapus() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan catatan?'),
        content: const Text(
          'Catatan keluhan ini akan dibatalkan.\n\n'
          'Data tidak hilang permanen dari database, dan tanggal yang sama '
          'boleh dicatat ulang nanti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setState(() => _isDeleting = true);

    final result = await widget.service.cancelNote(widget.note!.id);

    if (!mounted) return;

    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Catatan dibatalkan.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_pesanError(result)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Menggabungkan pesan utama dengan detail validasi per field dari Laravel.
  String _pesanError(Map<String, dynamic> result) {
    var pesan = result['message']?.toString() ?? 'Gagal menyimpan.';
    final errors = result['errors'];

    if (errors is Map) {
      final detail = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
      if (detail.isNotEmpty) pesan = '$pesan\n$detail';
    }

    return pesan;
  }

  @override
  Widget build(BuildContext context) {
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
                _isEdit ? 'Koreksi Catatan Keluhan' : 'Catat Keluhan',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Tanggal. Bisa diubah walau mode koreksi, karena salah pilih
              // tanggal di kalender adalah kesalahan yang wajar terjadi.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: Colors.blue),
                title: const Text('Tanggal Keluhan', style: TextStyle(fontSize: 14)),
                subtitle: Text(formatTanggalIndo(_tanggal.toIso8601String().substring(0, 10))),
                trailing: OutlinedButton(
                  onPressed: _pickDate,
                  child: const Text('Ubah'),
                ),
              ),
              const SizedBox(height: 8),

              const Text(
                'Keluhan yang dilihat',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              const Text(
                'Boleh lebih dari satu. Bila tidak ada keluhan, cukup isi catatan saja.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _demam,
                onChanged: (v) => setState(() => _demam = v),
                title: const Text('Demam', style: TextStyle(fontSize: 14)),
                secondary: const Icon(Icons.thermostat, color: Colors.red),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _rewel,
                onChanged: (v) => setState(() => _rewel = v),
                title: const Text('Rewel', style: TextStyle(fontSize: 14)),
                secondary: const Icon(Icons.sentiment_dissatisfied, color: Colors.orange),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _diare,
                onChanged: (v) => setState(() => _diare = v),
                title: const Text('Diare', style: TextStyle(fontSize: 14)),
                secondary: const Icon(Icons.water_drop, color: Colors.blueGrey),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _catatanController,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Contoh: Demam sejak semalam, masih mau makan.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),

              const Text(
                'Tindak lanjut',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              const Text(
                'Boleh dikosongkan bila kader memutuskan nanti.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              // Radio butuh satu ancestor yang memegang nilai grup, jadi
              // `RadioListTile` tidak lagi menerima groupValue/onChanged
              // secara langsung (deprecated sejak Flutter 3.32).
              RadioGroup<String>(
                groupValue: _tindakLanjut,
                onChanged: (v) => setState(() => _tindakLanjut = v),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final pilihan in TindakLanjut.semua)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: pilihan,
                        title: Text(
                          TindakLanjut.label(pilihan),
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          TindakLanjut.petunjuk(pilihan),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
              if (_tindakLanjut != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _tindakLanjut = null),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text(
                      'Kosongkan pilihan',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: (_isSaving || _isDeleting) ? null : _simpan,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isEdit ? 'Simpan Perubahan' : 'Simpan Catatan'),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: (_isSaving || _isDeleting) ? null : _hapus,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Batalkan Catatan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
