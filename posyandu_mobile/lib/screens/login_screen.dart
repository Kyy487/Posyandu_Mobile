import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'register_screen.dart'; // Pastikan import file register
import 'ibu/dashboard_ibu_screen.dart';
import 'kader/kader_dashboard_screen.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nikController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

void _handleLogin() async {
    if (_nikController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NIK dan Password harus diisi')),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    final result = await _authService.login(
      _nikController.text, 
      _passwordController.text
    );

    setState(() => _isLoading = false);

    if (result['success'] == true) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Login berhasil'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1), 
        ),
      );
      
      // CARA AMAN MENGAMBIL ROLE DARI JSON
      String? role;
      if (result['data'] != null) {
        // Mengecek apakah role ada di dalam object 'user', atau langsung di dalam 'data'
        if (result['data']['user'] != null && result['data']['user']['role'] != null) {
          role = result['data']['user']['role'];
        } else if (result['data']['role'] != null) {
          role = result['data']['role'];
        }
      }

      // Bersihkan teks role untuk mencegah error karena spasi atau huruf besar
      role = role?.toString().trim().toLowerCase();

      // LOGIKA NAVIGASI
      if (role == 'ibu') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const DashboardIbuScreen()),
          (Route<dynamic> route) => false,
        );
      } else if (role == 'kader') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const DashboardKaderScreen()),
          (Route<dynamic> route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: Role tidak ditemukan di JSON (Nilai: $role)'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Login gagal'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  void dispose() {
    _nikController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView( // Tambahkan ini agar tidak overflow saat keyboard muncul
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60), // Spacer atas
              const Text(
                'Smart Posyandu',
                style: TextStyle(
                  fontSize: 28, 
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _nikController,
                decoration: const InputDecoration(
                  labelText: 'NIK',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge), // Tambahkan ikon agar lebih rapi
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              _isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _handleLogin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Masuk', 
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                      ),
                    ),
              const SizedBox(height: 16),
              
              // TOMBOL MENUJU HALAMAN DAFTAR
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RegisterScreen(),
                    ),
                  );
                },
                child: const Text('Belum punya akun? Daftar di sini'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}