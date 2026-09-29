import 'package:flutter/material.dart';

import '../../services/kader_service.dart';

class InputPenimbanganScreen extends StatefulWidget {
  final String childId; // Menerima UUID Anak

  const InputPenimbanganScreen({super.key, required this.childId});

  @override
  State<InputPenimbanganScreen> createState() => _InputPenimbanganScreenState();
}

class _InputPenimbanganScreenState extends State<InputPenimbanganScreen> {
  final _formKey = GlobalKey<FormState>();
  final KaderService _kaderService = KaderService();
  bool _isLoading = false;

  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  DateTime _selectedDate = DateTime.now(); // Default ke hari ini

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

  Future<void> _submitMeasurement() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Mencegah error jika user mengetik menggunakan koma
    String safeWeight = _weightController.text.replaceAll(',', '.');
    String safeHeight = _heightController.text.replaceAll(',', '.');

    // Format YYYY-MM-DD
    String formattedDate =
        "${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}";

    final result = await _kaderService.addMeasurement(
      childId: widget.childId,
      measurementDate: formattedDate,
      weight: double.parse(safeWeight),
      height: double.parse(safeHeight),
    );

    setState(() => _isLoading = false);

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
            borderRadius: BorderRadius.circular(16),
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
              const Text(
                'Data penimbangan berhasil dicatat.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Input Penimbangan')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      elevation: 2,
                      child: ListTile(
                        leading: const Icon(
                          Icons.calendar_month,
                          color: Colors.blue,
                        ),
                        title: const Text('Tanggal Penimbangan'),
                        subtitle: Text(
                          "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}",
                        ),
                        trailing: OutlinedButton(
                          onPressed: _pickDate,
                          child: const Text('Ubah'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _weightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Berat Badan (kg)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.scale),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tinggi / Panjang Badan (cm)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.height),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty ? 'Wajib diisi' : null,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _submitMeasurement,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      icon: const Icon(Icons.save),
                      label: const Text(
                        'Simpan Data Penimbangan',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
