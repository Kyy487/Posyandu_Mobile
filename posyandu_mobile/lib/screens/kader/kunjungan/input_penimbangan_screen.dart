import 'package:flutter/material.dart';

import '/../../models/measurement_model.dart';
import '/../../services/kader_service.dart';

/// Form catat / koreksi penimbangan.
///
/// Tampilan baru: berat dan tinggi masing-masing punya kartu dengan angka
/// besar dan tombol - / + untuk menyesuaikan tanpa membuka keyboard (angka
/// tetap bisa diketik langsung). Logika simpan, koreksi, penempelan ke
/// kunjungan, dan dialog hasil Z-Score sama seperti sebelumnya.
///
/// Semua parameter baru bersifat opsional, jadi pemanggil lama tidak perlu
/// diubah. Bila [childName], [umurLabel], [terakhirBerat], atau
/// [terakhirTinggi] diisi, layar menampilkan kartu anak dan angka acuan
/// "Terakhir ..." untuk membantu kader memeriksa input.
class InputPenimbanganScreen extends StatefulWidget {
  final String childId; // Menerima UUID Anak

  /// Kunjungan tempat penimbangan ini menempel (opsional).
  ///
  /// Bila diisi, penimbangan ikut terhubung ke kunjungan itu. Dipakai alur
  /// "buat kunjungan → input data" dari `KunjunganScreen`.
  final String? visitId;

  /// Label kunjungan untuk ditampilkan di banner, mis. "24 September 2026 ·
  /// Posyandu". Boleh null bila [visitId] null.
  final String? visitLabel;

  /// Penimbangan yang sedang dikoreksi, bila layar ini dibuka untuk edit.
  ///
  /// Saat diisi layar berubah mode: form terisi nilai lama dan tombol
  /// memanggil `updateMeasurement` (PATCH) alih-alih `addMeasurement` (POST).
  /// Dikirim oleh daftar riwayat di `DetailAnakScreen`.
  final MeasurementModel? existing;

  /// Nama dan umur anak untuk kartu identitas di atas form (opsional).
  final String? childName;
  final String? umurLabel;

  /// Penimbangan terakhir anak, dipakai sebagai acuan dan titik awal tombol
  /// - / + (opsional).
  final double? terakhirBerat;
  final double? terakhirTinggi;

  const InputPenimbanganScreen({
    super.key,
    required this.childId,
    this.visitId,
    this.visitLabel,
    this.existing,
    this.childName,
    this.umurLabel,
    this.terakhirBerat,
    this.terakhirTinggi,
  });

  @override
  State<InputPenimbanganScreen> createState() => _InputPenimbanganScreenState();
}

class _InputPenimbanganScreenState extends State<InputPenimbanganScreen> {
  static const Color _teal = Color(0xFF0E7C7B);
  static const Color _ink = Color(0xFF12302F);
  static const Color _muted = Color(0xFF5C7F7C);
  static const Color _koral = Color(0xFFF2845C);
  static const Color _biru = Color(0xFF2F7DE1);
  static const Color _ungu = Color(0xFF8A3A9B);
  static const Color _amber = Color(0xFF9A6B00);

  final _formKey = GlobalKey<FormState>();
  final KaderService _kaderService = KaderService();
  bool _isLoading = false;

  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final FocusNode _weightFocus = FocusNode();
  final FocusNode _heightFocus = FocusNode();
  DateTime _selectedDate = DateTime.now(); // Default ke hari ini

  /// True bila layar ini membuka form koreksi, bukan input baru.
  bool get _mengedit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    if (m == null) return;

    _weightController.text = _teksAngka(m.weightKg);
    _heightController.text = _teksAngka(m.heightCm);
    _selectedDate = DateTime.tryParse(m.measurementDate) ?? _selectedDate;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _weightFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  /// Double → teks isian, tanpa `.0` berlebih ("11.5", bukan "11.50").
  static String _teksAngka(double nilai) {
    final teks = nilai.toString();
    return teks.endsWith('.0') ? teks.substring(0, teks.length - 2) : teks;
  }

  /// Teks isian → angka. Koma diterima sebagai pemisah desimal.
  static double? _bacaAngka(String teks) =>
      double.tryParse(teks.trim().replaceAll(',', '.'));

  static const _bulanPanjang = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  String get _tanggalLabel =>
      '${_selectedDate.day} ${_bulanPanjang[_selectedDate.month - 1]} '
      '${_selectedDate.year}';

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Menaikkan / menurunkan angka pada satu kolom.
  ///
  /// Kolom kosong: ketukan pertama mengisi angka acuan (penimbangan terakhir)
  /// supaya kader mulai dari nilai yang masuk akal. Tanpa acuan, kolom hanya
  /// difokuskan agar kader mengetik angka awal - kami tidak menebak berat
  /// atau tinggi anak.
  void _ubahAngka(
    TextEditingController c,
    FocusNode fokus,
    double langkah,
    double? acuan,
  ) {
    final sekarang = _bacaAngka(c.text);

    if (sekarang == null) {
      if (acuan == null) {
        fokus.requestFocus();
        return;
      }
      c.text = acuan.toStringAsFixed(1);
    } else {
      final baru = (sekarang + langkah).clamp(0.0, 999.0);
      c.text = baru.toStringAsFixed(1);
    }
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  String? _validasiAngka(String? value, String label) {
    final teks = value?.trim() ?? '';
    if (teks.isEmpty) return 'Wajib diisi';
    final angka = _bacaAngka(teks);
    if (angka == null) return '$label tidak valid';
    if (angka <= 0) return 'Harus lebih dari 0';
    return null;
  }

  Future<void> _submitMeasurement() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Koma dan titik sama-sama diterima.
    final double berat = _bacaAngka(_weightController.text)!;
    final double tinggi = _bacaAngka(_heightController.text)!;

    // Format YYYY-MM-DD
    String formattedDate =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    final result = _mengedit
        ? await _kaderService.updateMeasurement(
            measurementId: widget.existing!.id,
            measurementDate: formattedDate,
            weight: berat,
            height: tinggi,
          )
        : await _kaderService.addMeasurement(
            childId: widget.childId,
            measurementDate: formattedDate,
            weight: berat,
            height: tinggi,
            visitId: widget.visitId,
          );

    if (mounted) setState(() => _isLoading = false);

    if (result['success']) {
      if (mounted) {
        await _tampilkanHasilKalkulasi(result['data']);
        if (mounted) Navigator.pop(context, true);
      }
    } else {
      // AMBIL DETAIL ERROR DARI LARAVEL JIKA ADA
      String errorMessage = result['message'];
      if (result['errors'] != null) {
        // Gabungkan pesan error validasi per field
        Map<String, dynamic> errors = result['errors'];
        errorMessage = errors.values.map((e) => e.join(', ')).join('\n');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Menampilkan hasil kalkulasi Z-Score & Status Gizi yang dihitung
  /// otomatis oleh Database Trigger PostgreSQL (WHO Child Growth Standards).
  Future<void> _tampilkanHasilKalkulasi(dynamic rawData) async {
    if (rawData is! Map) {
      // Fallback bila server tidak mengirim data (misal versi API lama)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data penimbangan berhasil disimpan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    final data = Map<String, dynamic>.from(rawData);
    final double? zScore = _parseDouble(data['z_score_wfa']);
    final int? ageInMonths = _parseInt(data['age_in_months']);
    final String? statusGizi = data['status_gizi']?.toString();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusGizi ?? 'Tersimpan',
                  style: TextStyle(
                    color: _warnaStatus(statusGizi),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _mengedit
                    ? 'Data penimbangan berhasil diperbarui.'
                    : 'Data penimbangan berhasil dicatat.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _barisHasil('Berat Badan', '${data['weight_kg']} kg'),
              _barisHasil('Tinggi Badan', '${data['height_cm']} cm'),
              _barisHasil(
                'Umur Anak',
                ageInMonths != null ? '$ageInMonths bulan' : '-',
              ),
              const Divider(height: 24),
              _barisHasil(
                'Z-Score (BB/U)',
                zScore == null
                    ? 'Di luar rentang WHO'
                    : zScore.toStringAsFixed(2),
                bold: true,
              ),
              if (statusGizi == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Usia anak di luar rentang standar WHO (0-60 bulan), '
                    'sehingga status gizi tidak dihitung.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _warnaStatus(statusGizi),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Selesai',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _barisHasil(String label, String nilai, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          Text(
            nilai,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Pemetaan warna indikator sesuai status gizi hasil hitungan Z-Score.
  Color _warnaStatus(String? status) {
    switch (status) {
      case 'Gizi Buruk':
        return Colors.red;
      case 'Gizi Kurang':
        return Colors.orange[800] ?? Colors.orange;
      case 'Risiko Gizi Lebih':
        return Colors.blueGrey;
      case 'Normal':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F5),
      bottomNavigationBar: _tombolSimpan(),
      body: Column(
        children: [
          _barAtas(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.visitId != null) ...[
                            _buildBannerKunjungan(),
                            const SizedBox(height: 12),
                          ],
                          if (widget.childName != null) ...[
                            _kartuAnak(),
                            const SizedBox(height: 12),
                          ],
                          _kartuTanggal(),
                          const SizedBox(height: 12),
                          _kartuAngka(
                            ikon: Icons.monitor_weight_outlined,
                            warna: _biru,
                            label: 'Berat badan',
                            satuan: 'kg',
                            controller: _weightController,
                            fokus: _weightFocus,
                            langkah: 0.1,
                            acuan: widget.terakhirBerat,
                            validasi: (v) => _validasiAngka(v, 'Berat'),
                          ),
                          const SizedBox(height: 12),
                          _kartuAngka(
                            ikon: Icons.straighten_rounded,
                            warna: _ungu,
                            label: 'Tinggi / panjang badan',
                            satuan: 'cm',
                            controller: _heightController,
                            fokus: _heightFocus,
                            langkah: 0.5,
                            acuan: widget.terakhirTinggi,
                            validasi: (v) => _validasiAngka(v, 'Tinggi'),
                          ),
                          const SizedBox(height: 12),
                          _catatan(),
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
            Expanded(
              child: Text(
                _mengedit ? 'Edit Penimbangan' : 'Catat Penimbangan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
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

  Widget _kartu({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _kartuAnak() {
    final nama = widget.childName ?? '';

    return _kartu(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E7C7B), Color(0xFF14A39A)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              nama.isNotEmpty ? nama[0].toUpperCase() : 'A',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                if (widget.umurLabel != null)
                  Text(
                    widget.umurLabel!,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuTanggal() {
    return _kartu(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: _pickDate,
        borderRadius: BorderRadius.circular(22),
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
                  Icons.calendar_month_rounded,
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
                      'Tanggal penimbangan',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                    Text(
                      _tanggalLabel,
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

  /// Kartu angka besar dengan tombol - / + dan kolom yang tetap bisa diketik.
  Widget _kartuAngka({
    required IconData ikon,
    required Color warna,
    required String label,
    required String satuan,
    required TextEditingController controller,
    required FocusNode fokus,
    required double langkah,
    required double? acuan,
    required String? Function(String?) validasi,
  }) {
    return _kartu(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(ikon, size: 22, color: warna),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              if (acuan != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F6F5),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Terakhir ${_teksAngka(acuan)} $satuan',
                    style: const TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _tombolBulat(
                Icons.remove_rounded,
                'Kurangi $label',
                const Color(0xFFF2F6F5),
                _ink,
                () => _ubahAngka(controller, fokus, -langkah, acuan),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 118,
                      child: TextFormField(
                        controller: controller,
                        focusNode: fokus,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          color: warna,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '0.0',
                          hintStyle: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: warna.withValues(alpha: 0.25),
                          ),
                          errorStyle: const TextStyle(fontSize: 11),
                        ),
                        validator: validasi,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      satuan,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
              _tombolBulat(
                Icons.add_rounded,
                'Tambah $label',
                warna.withValues(alpha: 0.12),
                warna,
                () => _ubahAngka(controller, fokus, langkah, acuan),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tombolBulat(
    IconData ikon,
    String tooltip,
    Color latar,
    Color warnaIkon,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(ikon, size: 26, color: warnaIkon),
          ),
        ),
      ),
    );
  }

  Widget _catatan() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 22, color: _teal),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Z-Score dan status gizi dihitung otomatis setelah data '
              'disimpan.',
              style: TextStyle(fontSize: 12, height: 1.4, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  /// Penanda bahwa data ini menempel pada satu kunjungan.
  ///
  /// Tanpa ini, kader bisa lupa sedang mengisi untuk kunjungan mana dan
  /// mengira datanya berdiri sendiri.
  Widget _buildBannerKunjungan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_available, size: 18, color: _teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Menempel pada kunjungan',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _teal,
                  ),
                ),
                if (widget.visitLabel != null)
                  Text(
                    widget.visitLabel!,
                    style: const TextStyle(fontSize: 11, color: _ink),
                  ),
              ],
            ),
          ),
        ],
      ),
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
              onPressed: _isLoading ? null : _submitMeasurement,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
              label: Text(
                _mengedit ? 'Simpan Perubahan' : 'Simpan Penimbangan',
              ),
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