import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ChildService {
  final String baseUrl = 'http://10.0.2.2:8000/api';
  final storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> getChildren() async {
    try {
      final token = await storage.read(key: 'token');
      
      final response = await http.get(
        Uri.parse('$baseUrl/children'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token', // Sertakan token Sanctum
        },
      );

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      return responseData;
      
    } catch (e) {
      return {
        'success': false,
        'message': 'Terjadi kesalahan koneksi jaringan.',
        'data': null
      };
    }
  }
}