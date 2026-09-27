import 'package:flutter/material.dart';

import '../../models/posyandu_schedule.dart';
import '../../services/schedule_service.dart';

/// Form tambah / ubah agenda.
///
/// Mengubah agenda mengirim PATCH dengan field yang memang berubah. Satu
/// pengecualian: `petugas_ids` selalu ikut dikirim saat status diubah, karena
/// layar ini tidak menyimpan salinan penugasan di luar form.
class FormAgenda extends StatefulWidget {
  final PosyanduSchedule? existing;
  final List<Petugas> petugas;
  final ScheduleService service;

  const FormAgenda({
    super.key,
    required this.existing,
    required this.petugas,
    required this.service,
  });

  @override
  State<FormAgenda> createState() => FormAgendaState();
}

class FormAgendaState extends State<FormAgenda> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _judulController;
  late final TextEditingController _deskripsiController;
  late final TextEditingController _lokasiController;
  late final TextEditingController _catatanController;
  late final TextEditingController _mulaiController;
  late final TextEditingController _selesaiController;

  late DateTime _tanggal;
  late String _status;
  late Set<String> _terpilihPetugas;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _judulController = TextEditingController(text: e?.title ?? '');
    _deskripsiController = TextEditingController(text: e?.description ?? '');
    _lokasiController = TextEditingController(text: e?.location ?? '');
    _catatanController = TextEditingController(text: e?.notes ?? '');
    _mulaiController = TextEditingController(text: e?.startTime ?? '');
    _selesaiController = TextEditingController(text: e?.endTime ?? '');

    _tanggal = DateTime.tryParse(e?.scheduledDate ?? '') ?? DateTime.now();
    _status = e?.status ?? ScheduleStatus.terjadwal;
    _terpilihPetugas = {...?e?.petugasIds};
  }

  @override
  void dispose() {
    _judulController.dispose();
    _deskripsiController.dispose();
    _lokasiController.dispose();
    _catatanController.dispose();
    _mulaiController.dispose();
    _selesaiController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  /// Jam diisi manual sebagai teks karena input time bawaan Flutter tidak
  /// ada. Format wajib `HH:MM` 24 jam agar cocok `date_format:H:i` di server.
  String? _validasiJam(String? nilai, String label) {
    if (nilai == null || nilai.isEmpty) return null;

    final cocok = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(nilai.trim());
    if (!cocok) return '$label harus berformat HH:MM (24 jam)';

    return null;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    // Cek silang jam selesai >= jam mulai. Server juga memvalidasi ini saat
    // create, tapi caught lebih awal supaya pesan error lebih jelas.
    final mulai = _mulaiController.text.trim();
    final selesai = _selesaiController.text.trim();
    if (mulai.isNotEmpty &&
        selesai.isNotEmpty &&
        selesai.compareTo(mulai) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jam selesai tidak boleh lebih awal dari jam mulai.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final petugasIds = _terpilihPetugas.toList();

    final result = _isEdit
        ? await widget.service.updateSchedule(
            scheduleId: widget.existing!.id,
            title: _judulController.text.trim(),
            scheduledDate: tanggal,
            description: _deskripsiController.text.trim(),
            startTime: mulai.isEmpty ? null : mulai,
            endTime: selesai.isEmpty ? null : selesai,
            status: _status,
            location: _lokasiController.text.trim(),
            notes: _catatanController.text.trim(),
            petugasIds: petugasIds,
          )
        : await widget.service.createSchedule(
            title: _judulController.text.trim(),
            scheduledDate: tanggal,
            description: _deskripsiController.text.trim(),
            startTime: mulai.isEmpty ? null : mulai,
            endTime: selesai.isEmpty ? null : selesai,
            status: _status,
            location: _lokasiController.text.trim(),
            notes: _catatanController.text.trim(),
            petugasIds: petugasIds,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit ? 'Agenda diperbarui.' : 'Agenda disimpan.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    String pesan = result['message']?.toString() ?? 'Gagal menyimpan agenda.';
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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEdit ? 'Ubah Agenda' : 'Tambah Agenda',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    TextFormField(
                      controller: _judulController,
                      decoration: const InputDecoration(
                        labelText: 'Nama kegiatan',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      maxLength: 120,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nama kegiatan wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Card(
                      elevation: 1,
                      child: ListTile(
                        leading:
                            const Icon(Icons.calendar_month, color: Colors.blue),
                        title: const Text('Tanggal'),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _mulaiController,
                            decoration: const InputDecoration(
                              labelText: 'Mulai',
                              hintText: '08:00',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => _validasiJam(v, 'Jam mulai'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _selesaiController,
                            decoration: const InputDecoration(
                              labelText: 'Selesai',
                              hintText: '11:00',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => _validasiJam(v, 'Jam selesai'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final s in ScheduleStatus.semua)
                          DropdownMenuItem(
                            value: s,
                            child: Text(ScheduleStatus.label(s)),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _status = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildPetugasSelector(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _lokasiController,
                      decoration: const InputDecoration(
                        labelText: 'Lokasi (opsional)',
                        helperText:
                            'Bila dikosongkan, sistem memakai nama posyandu '
                            'dari pengaturan.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.location_on),
                      ),
                      maxLength: 120,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _deskripsiController,
                      decoration: const InputDecoration(
                        labelText: 'Deskripsi (opsional)',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      maxLength: 500,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _catatanController,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 500,
                    ),
                    const SizedBox(height: 16),
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
                        _isEdit ? 'Simpan Perubahan' : 'Simpan Agenda',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Pemilih petugas kelipak. Daftar `/petugas` tidak pernah memuat NIK,
  /// jadi yang ditampilkan hanya nama dan jabatan.
  Widget _buildPetugasSelector() {
    if (widget.petugas.isEmpty) {
      return const Text(
        'Belum ada data petugas. Daftar petugas diambil dari user role kader.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Petugas yang menangani (${_terpilihPetugas.length} dipilih)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in widget.petugas)
              FilterChip(
                label: Text('${p.shortName} - ${p.roleLabel}'),
                selected: _terpilihPetugas.contains(p.id),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _terpilihPetugas.add(p.id);
                    } else {
                      _terpilihPetugas.remove(p.id);
                    }
                  });
                },
              ),
          ],
        ),
      ],
    );
  }
}
