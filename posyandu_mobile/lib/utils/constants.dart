// Isi file lib/utils/constants.dart
class ApiConstants {
  // Ubah sesuai device testing kamu (10.0.2.2 untuk Emulator Android)
  static const String baseUrl = 'http://10.0.2.2:8000/api'; 
  
  static const String loginEndpoint = '/login';
  static const String registerEndpoint = '/register';
  static const String childrenEndpoint = '/children';
}