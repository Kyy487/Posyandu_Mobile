import 'package:flutter/material.dart';
import '../../services/kader_service.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey = GlobalKey<FormState>();
  final KaderService _kaderService = KaderService();

  bool _isLoading = false;

  // Controllers untuk input
  final TextEditingController _nikController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ibuNikController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  
  String? _selectedGender;
  DateTime? _selectedDate;

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015), // Batasan tahun minimal
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih tanggal lahir terlebih dahulu')));
      return;
    }
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih jenis kelamin')));
      return;
    }

    setState(() => _isLoading = true);

    // Format tanggal untuk PostgreSQL (YYYY-MM-DD)
    String formattedDate = "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";

    final result = await _kaderService.addChild(
      nik: _nikController.text,
      name: _nameController.text,
      dateOfBirth: formattedDate,
      gender: _selectedGender!,
      birthWeight: double.parse(_weightController.text),
      birthHeight: double.parse(_heightController.text),
      ibuNik: _ibuNikController.text,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']), backgroundColor: Colors.green));
        Navigator.pop(context, true); // Kembali ke Dashboard sambil mengirim sinyal 'true' (berhasil)
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message']), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tambah Data Anak')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _nikController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'NIK Anak (16 Digit)', border: OutlineInputBorder()),
                    validator: (value) => value!.length != 16 ? 'NIK harus 16 digit' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nama Lengkap Anak', border: OutlineInputBorder()),
                    validator: (value) => value!.isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _ibuNikController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'NIK Ibu (16 Digit)', border: OutlineInputBorder()),
                    validator: (value) => value!.length != 16 ? 'NIK Ibu harus 16 digit' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Jenis Kelamin', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
                      DropdownMenuItem(value: 'P', child: Text('Perempuan')),
                    ],
                    onChanged: (val) => setState(() => _selectedGender = val),
                    validator: (value) => value == null ? 'Pilih jenis kelamin' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_selectedDate == null ? 'Pilih Tgl Lahir' : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}"),
                          onPressed: _pickDate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Berat Lahir (kg)', border: OutlineInputBorder()),
                          validator: (value) => value!.isEmpty ? 'Wajib diisi' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Panjang Lahir (cm)', border: OutlineInputBorder()),
                          validator: (value) => value!.isEmpty ? 'Wajib diisi' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _submitForm,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text('Simpan Data Anak', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
        ),
    );
  }
}