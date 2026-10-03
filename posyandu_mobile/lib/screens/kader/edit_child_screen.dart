import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/child.dart';
import '../../services/kader_service.dart';

/// Form edit data anak untuk Kader.
///
/// Mengganti stub lama di `detail_anak_screen.dart` yang hanya memunculkan
/// SnackBar "Fitur edit data anak segera hadir". Backend sudah siap menerima
/// PATCH sejak lama (`ChildController::update`), jadi layar ini murni sisi
/// mobile.
///
/// Mengembalikan [Child] yang sudah diperbarui lewat `Navigator.pop` kalau
/// berhasil disimpan, supaya pemanggil bisa langsung memakainya tanpa
/// menunggu refresh dari server. `null` berarti tidak ada yang berubah
/// (pengguna menekan back, atau simpan gagal).
class EditChildScreen extends StatefulWidget {
  final Child child;

  const EditChildScreen({super.key, required this.child});

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final KaderService _kaderService = KaderService();

  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _medicalFlagsController;

  String? _gender;
  DateTime? _dateOfBirth;
  bool _isSaving = false;

  /// Batas atas `medical_flags` di backend (`ChildController::update`).
  static const _medicalFlagsMax = 500;

  @override
  void initState() {
    super.initState();
    final child = widget.child;

    _nameController = TextEditingController(text: child.name);
    _weightController = TextEditingController(
      text: _formatAngka(child.birthWeight),
    );
    _heightController = TextEditingController(
      text: _formatAngka(child.birthHeight),
    );
    _medicalFlagsController = TextEditingController(
      text: child.medicalFlags ?? '',
    );

    _gender = child.gender;
    _dateOfBirth = DateTime.tryParse(child.dateOfBirth ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _medicalFlagsController.dispose();
    super.dispose();
  }

  /// Angka untuk isi form: `3.2000` dari PostgreSQL dirapikan jadi `3.2`.
  ///
  /// Kolomnya bertipe `decimal`, jadi Laravel sering mengirim string dengan
  /// trailing nol. Menampilkan 그대로 di TextFormField terlihat seperti data
  /// aneh padahal angkanya benar.
  static String _formatAngka(double? nilai) {
    if (nilai == null) return '';
    final teks = nilai.toStringAsFixed(2);
    return teks.contains('.')
        ? teks.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : teks;
  }

  /// Mengubah isi form menjadi angka, atau null bila dikosongkan.
  ///
  /// null berarti "kosongkan field ini" dan sengaja dikirim apa adanya ke
  /// backend - bukan dilewati.
  static double? _parseAngka(String teks) {
    final bersih = teks.trim().replaceAll(',', '.');
    if (bersih.isEmpty) return null;
    return double.tryParse(bersih);
  }

  Future<void> _pickDate() async {
    final sekarang = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? sekarang,
      // Batas bawah lebih longgar daripada di form tambah (yang memakai 2015):
      // di form edit, lantai yang terlalu tinggi akan membuat anak yang lebih
      // tua tidak bisa diperbarui sama sekali. Backend sendiri hanya menuntut
      // tanggal tidak di masa depan.
      firstDate: DateTime(2000),
      lastDate: sekarang,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOfBirth == null || _gender == null) return;

    setState(() => _isSaving = true);

    final berat = _parseAngka(_weightController.text);
    final panjang = _parseAngka(_heightController.text);
    final kondisi = _medicalFlagsController.text.trim();

    final hasil = await _kaderService.updateChild(
      childId: widget.child.id,
      name: _nameController.text.trim(),
      dateOfBirth: _dateOfBirth!.toIso8601String().substring(0, 10),
      gender: _gender!,
      birthWeight: berat,
      birthHeight: panjang,
      medicalFlags: kondisi.isEmpty ? null : kondisi,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (hasil['success'] == true) {
      // Nilai balik dibawa pulang supaya layar pemanggil tidak perlu fetch
      // ulang: `GET /children/{id}` untuk satu anak tidak ada, dan refresh
      // penuh akan membuang posisi scroll pengguna.
      Navigator.pop(
        context,
        widget.child.copyWith(
          name: _nameController.text.trim(),
          dateOfBirth: _dateOfBirth!.toIso8601String().substring(0, 10),
          gender: _gender,
          birthWeight: berat,
          birthHeight: panjang,
          medicalFlags: kondisi.isEmpty ? null : kondisi,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hasil['message']?.toString() ?? 'Gagal menyimpan data.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Data Anak')),
      body: _isSaving
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInfo(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama Lengkap Anak',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final teks = value?.trim() ?? '';
                        if (teks.isEmpty) return 'Nama wajib diisi';
                        if (teks.length > 255) {
                          return 'Nama maksimal 255 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _gender,
                      decoration: const InputDecoration(
                        labelText: 'Jenis Kelamin',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
                        DropdownMenuItem(value: 'P', child: Text('Perempuan')),
                      ],
                      onChanged: (val) => setState(() => _gender = val),
                      validator: (value) =>
                          value == null ? 'Pilih jenis kelamin' : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        _dateOfBirth == null
                            ? 'Pilih Tanggal Lahir'
                            : '${_dateOfBirth!.day}/${_dateOfBirth!.month}/${_dateOfBirth!.year}',
                      ),
                      onPressed: _isSaving ? null : _pickDate,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFieldAngka(
                            controller: _weightController,
                            label: 'Berat Lahir (kg)',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildFieldAngka(
                            controller: _heightController,
                            label: 'Panjang Lahir (cm)',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _medicalFlagsController,
                      maxLines: 3,
                      maxLength: _medicalFlagsMax,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\n')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Kondisi Khusus',
                        helperText:
                            'Satu penanda per baris, mis. "alergi: penisilin". '
                            'Kosongkan untuk menghapus penanda yang ada.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _simpan,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Simpan Perubahan',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// Data yang tidak bisa diubah dari sini, ditampilkan supaya kader tahu apa
  /// yang sedang diedit. NIK sengaja tidak bisa diedit: nilainya unik per anak
  /// dan tidak ada di kontrak edit.
  Widget _buildInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NIK: ${widget.child.nik}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Ibu: ${widget.child.parentName}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Field angka yang boleh dikosongkan.
  ///
  /// Kosong berarti "hapus nilai", jadi validator hanya menolak yang tidak
  /// bisa dibaca sebagai angka - bukan yang kosong.
  Widget _buildFieldAngka({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final teks = value?.trim() ?? '';
        if (teks.isEmpty) return null;
        final angka = double.tryParse(teks.replaceAll(',', '.'));
        if (angka == null) return 'Masukkan angka';
        if (angka < 0) return 'Tidak boleh negatif';
        return null;
      },
    );
  }
}
