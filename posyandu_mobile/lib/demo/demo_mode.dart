class DemoMode {
  static const bool frontendOnly = bool.fromEnvironment(
    'FRONTEND_ONLY',
    defaultValue: true,
  );

  static bool _enabled = false;
  static String _role = 'kader';
  static String token = 'demo-token';

  static bool get enabled => _enabled;
  static String get role => _role;
  static bool get isIbu => _role == 'ibu';

  static void enable({String role = 'kader'}) {
    _enabled = true;
    _role = role.toLowerCase() == 'ibu' ? 'ibu' : 'kader';
  }

  static void disable() => _enabled = false;

  static Map<String, dynamic> get currentUser => {
    'id': 'demo-user-1',
    'name': _role == 'ibu' ? 'Siti Rahma' : 'Rina Kader',
    'nik': _role == 'ibu' ? '3201010101010001' : '3201010101010002',
    'role': _role,
    'status': 'active',
    'phone_number': '081234567890',
    'whatsapp': '081234567890',
    'instagram': '@demo_posyandu',
    'facebook': 'demo.posyandu',
    'address': 'Jl. Kesehatan No. 1, Desa Sehat',
  };
}
