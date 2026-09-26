import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  RegisterScreenState createState() => RegisterScreenState();
}

class RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _nikController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController = TextEditingController();
  final TextEditingController _kaderCodeController = TextEditingController();

  bool _isLoading = false;

  final AuthService _authService = AuthService();

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.register(
      name: _nameController.text.trim(),
      nik: _nikController.text.trim(),
      password: _passwordController.text,
      passwordConfirmation: _passwordConfirmController.text,
      // Tidak ada pilihan role di layar. Server yang menentukan:
      // kode kosong -> akun ibu, kode cadres yang cocok -> akun kader.
      kaderCode: _kaderCodeController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Registrasi berhasil'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_firstError(result)),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Mengambil pesan paling spesifik dari respons server.
  String _firstError(Map<String, dynamic> result) {
    final errors = result['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      if (first != null) return first.toString();
    }
    return result['message']?.toString() ?? 'Registrasi gagal.';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nikController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _kaderCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Daftar Akun')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Smart Posyandu',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lengkapi data di bawah ini untuk mendaftar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // NAMA LENGKAP
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty
                          ? 'Nama tidak boleh kosong'
                          : null,
                ),
                const SizedBox(height: 16),

                // NIK
                TextFormField(
                  controller: _nikController,
                  keyboardType: TextInputType.number,
                  maxLength: 16,
                  decoration: const InputDecoration(
                    labelText: 'Nomor Induk Kependudukan (NIK)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge),
                  ),
                  validator: (value) {
                    final nik = value?.trim() ?? '';
                    if (nik.isEmpty) return 'NIK tidak boleh kosong';
                    if (nik.length != 16) {
                      return 'NIK harus terdiri dari 16 digit angka';
                    }
                    if (!RegExp(r'^\d{16}$').hasMatch(nik)) {
                      return 'NIK hanya boleh berisi angka';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (value) => (value == null || value.length < 8)
                      ? 'Password minimal 8 karakter'
                      : null,
                ),
                const SizedBox(height: 16),

                // KONFIRMASI PASSWORD
                TextFormField(
                  controller: _passwordConfirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Konfirmasi Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (value) =>
                      value != _passwordController.text
                          ? 'Konfirmasi password tidak cocok'
                          : null,
                ),
                const SizedBox(height: 8),

                // KODE KADER - opsional, bukan pemilih role.
                Card(
                  margin: EdgeInsets.zero,
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.vpn_key_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Kode kader posyandu (opsional)',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Ibu tidak perlu mengisi apa pun. Kode ini hanya '
                          'untuk petugas posyandu yang mendapat kode dari koordinator.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _kaderCodeController,
                          decoration: const InputDecoration(
                            hintText: 'Kosongkan bila Anda ibu',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // TOMBOL DAFTAR
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'DAFTAR',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
