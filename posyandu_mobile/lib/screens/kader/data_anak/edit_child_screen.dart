import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/../../models/child.dart';
import '/../../services/kader_service.dart';

/// Form edit data anak untuk Kader.
///
/// Backend sudah siap menerima PATCH (`ChildController::update`), jadi layar
/// ini murni sisi mobile.
///
/// Mengembalikan [Child] yang sudah diperbarui lewat `Navigator.pop` kalau
/// berhasil disimpan, supaya pemanggil bisa langsung memakainya tanpa
/// menunggu refresh dari server. `null` berarti tidak ada yang berubah
/// (pengguna menekan back, atau simpan gagal).
///
/// Tampilan baru mengikuti form Catat Penimbangan: bar atas bergaya baru,
/// pilihan jenis kelamin berikon, kartu tanggal lahir, kolom berlatar putih
/// membulat, dan tombol simpan koral di dasar layar. Logika simpan sama.
class EditChildScreen extends StatefulWidget {
  final Child child;

  const EditChildScreen({super.key, required this.child});

  @override
  State<EditChildScreen> createState() => _EditChildScreenState();
}

class _EditChildScreenState extends State<EditChildScreen> {
  static const Color _teal = Color(0xFF0E7C7B);
  static const Color _ink = Color(0xFF12302F);
  static const Color _muted = Color(0xFF5C7F7C);
  static const Color _koral = Color(0xFFF2845C);
  static const Color _amber = Color(0xFF9A6B00);
  static const Color _permukaan = Color(0xFFF2F6F5);

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
  /// trailing nol. Menampilkannya apa adanya di TextFormField terlihat seperti
  /// data aneh padahal angkanya benar.
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

  static const _bulanPanjang = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  String get _tanggalLahirLabel {
    final d = _dateOfBirth;
    if (d == null) return 'Pilih tanggal lahir';
    return '${d.day} ${_bulanPanjang[d.month - 1]} ${d.year}';
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

    if (_dateOfBirth == null || _gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi jenis kelamin dan tanggal lahir.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _permukaan,
      bottomNavigationBar: _tombolSimpan(),
      body: Column(
        children: [
          _barAtas(),
          Expanded(
            child: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildInfo(),
                          const SizedBox(height: 16),
                          _label('Nama lengkap anak'),
                          TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: _dekor(
                              'Nama lengkap anak',
                              Icons.person_outline_rounded,
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
                          const SizedBox(height: 16),
                          _label('Jenis kelamin'),
                          Row(
                            children: [
                              Expanded(
                                child: _pilihGender(
                                  'L',
                                  Icons.male_rounded,
                                  'Laki-laki',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _pilihGender(
                                  'P',
                                  Icons.female_rounded,
                                  'Perempuan',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _kartuTanggalLahir(),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _buildFieldAngka(
                                  controller: _weightController,
                                  label: 'Berat lahir (kg)',
                                  ikon: Icons.monitor_weight_outlined,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildFieldAngka(
                                  controller: _heightController,
                                  label: 'Panjang lahir (cm)',
                                  ikon: Icons.straighten_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _label('Kondisi khusus'),
                          TextFormField(
                            controller: _medicalFlagsController,
                            maxLines: 3,
                            maxLength: _medicalFlagsMax,
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: [
                              FilteringTextInputFormatter.deny(RegExp(r'\n')),
                            ],
                            decoration: _dekor(
                              'Mis. alergi: penisilin',
                              Icons.healing_outlined,
                            ).copyWith(
                              helperText:
                                  'Satu penanda per baris, mis. "alergi: '
                                  'penisilin". Kosongkan untuk menghapus '
                                  'penanda yang ada.',
                              helperMaxLines: 3,
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _barAtas() {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Row(
          children: [
            Tooltip(
              message: 'Kembali',
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => Navigator.of(context).maybePop(),
                  borderRadius: BorderRadius.circular(14),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back_rounded, color: _ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Edit Data Anak',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String teks) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        teks,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: _muted,
        ),
      ),
    );
  }

  InputDecoration _dekor(String hint, IconData ikon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(ikon, color: _muted),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
    );
  }

  Widget _pilihGender(String kode, IconData ikon, String label) {
    final aktif = _gender == kode;

    return Material(
      color: aktif ? _teal : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: _isSaving ? null : () => setState(() => _gender = kode),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: 22, color: aktif ? Colors.white : _muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: aktif ? Colors.white : _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartuTanggalLahir() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _isSaving ? null : _pickDate,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.cake_outlined,
                  size: 22,
                  color: _amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tanggal lahir',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                    Text(
                      _tanggalLahirLabel,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'Ubah',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _teal,
                  ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _teal.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.lock_outline_rounded, color: _teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NIK: ${widget.child.nik}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                Text(
                  'Ibu: ${widget.child.parentName}',
                  style: const TextStyle(fontSize: 12.5, color: _muted),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tidak bisa diubah dari sini',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
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
    required IconData ikon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _dekor('0.0', ikon),
          validator: (value) {
            final teks = value?.trim() ?? '';
            if (teks.isEmpty) return null;
            final angka = double.tryParse(teks.replaceAll(',', '.'));
            if (angka == null) return 'Masukkan angka';
            if (angka < 0) return 'Tidak boleh negatif';
            return null;
          },
        ),
      ],
    );
  }

  Widget _tombolSimpan() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: _koral.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _simpan,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
              label: const Text('Simpan Perubahan'),
              style: FilledButton.styleFrom(
                backgroundColor: _koral,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}