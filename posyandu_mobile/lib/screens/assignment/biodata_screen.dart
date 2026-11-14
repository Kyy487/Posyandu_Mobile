import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_theme.dart';
import 'assignment_config.dart';

class BiodataScreen extends StatefulWidget {
  const BiodataScreen({super.key});

  @override
  State<BiodataScreen> createState() => _BiodataScreenState();
}

class _BiodataScreenState extends State<BiodataScreen> {
  final _formKey = GlobalKey<FormState>();
  final _namaController = TextEditingController(text: 'Nama Mahasiswa');
  final _nikController = TextEditingController();
  final _emailController = TextEditingController();
  final _teleponController = TextEditingController();
  final _alamatController = TextEditingController();
  final _imagePicker = ImagePicker();

  DateTime? _tanggalLahir;
  String _jenisKelamin = 'Perempuan';
  String _pendidikan = 'SMA/SMK';
  String _golonganDarah = 'O';
  File? _fotoProfil;
  bool _sedangMengambilFoto = false;

  static const List<String> _pilihanPendidikan = [
    'SD',
    'SMP',
    'SMA/SMK',
    'D3',
    'S1',
    'S2',
    'S3',
  ];

  static const List<String> _pilihanDarah = ['A', 'B', 'AB', 'O'];

  @override
  void dispose() {
    _namaController.dispose();
    _nikController.dispose();
    _emailController.dispose();
    _teleponController.dispose();
    _alamatController.dispose();
    super.dispose();
  }

  Future<void> _pilihSumberFoto() async {
    final sumber = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ganti Foto Profil',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Ambil dari kamera'),
                  subtitle: const Text('Foto langsung menggunakan HP'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Pilih dari galeri'),
                  subtitle: const Text('Gunakan foto yang sudah ada'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (sumber == null) return;
    await _ambilFoto(sumber);
  }

  Future<void> _ambilFoto(ImageSource sumber) async {
    setState(() => _sedangMengambilFoto = true);
    try {
      final hasil = await _imagePicker.pickImage(
        source: sumber,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (hasil == null) return;
      if (!mounted) return;
      setState(() => _fotoProfil = File(hasil.path));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto profil berhasil diperbarui')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto tidak dapat diambil. Periksa izin kamera.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sedangMengambilFoto = false);
    }
  }

  Future<void> _pilihTanggalLahir() async {
    final sekarang = DateTime.now();
    final terpilih = await showDatePicker(
      context: context,
      initialDate: _tanggalLahir ?? DateTime(sekarang.year - 20),
      firstDate: DateTime(1950),
      lastDate: sekarang,
      helpText: 'Pilih tanggal lahir',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (terpilih == null) return;
    setState(() => _tanggalLahir = terpilih);
  }

  String get _tanggalLahirLabel {
    final tanggal = _tanggalLahir;
    if (tanggal == null) return 'Belum dipilih';
    return '${tanggal.day.toString().padLeft(2, '0')}/'
        '${tanggal.month.toString().padLeft(2, '0')}/'
        '${tanggal.year}';
  }

  void _simpan() {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_tanggalLahir == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih tanggal lahir')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Biodata tersimpan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _barisRingkasan('Nama', _namaController.text),
                _barisRingkasan('NIK', _nikController.text),
                _barisRingkasan('Email', _emailController.text),
                _barisRingkasan('Telepon', _teleponController.text),
                _barisRingkasan('Tanggal lahir', _tanggalLahirLabel),
                _barisRingkasan('Jenis kelamin', _jenisKelamin),
                _barisRingkasan('Pendidikan', _pendidikan),
                _barisRingkasan('Golongan darah', _golonganDarah),
                _barisRingkasan('Alamat', _alamatController.text),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Widget _barisRingkasan(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            nilai.isEmpty ? '-' : nilai,
            style: const TextStyle(fontSize: 14, color: AppTheme.ink),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _kartuFoto(),
          const SizedBox(height: 18),
          _SectionCard(
            title: 'Informasi Pribadi',
            icon: Icons.person_outline_rounded,
            child: Column(
              children: [
                TextFormField(
                  controller: _namaController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama lengkap',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nama tidak boleh kosong';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nikController,
                  keyboardType: TextInputType.number,
                  maxLength: 16,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'NIK',
                    prefixIcon: Icon(Icons.credit_card_rounded),
                    counterText: '',
                  ),
                  validator: (value) {
                    if (value == null || value.length != 16) {
                      return 'NIK harus 16 digit angka';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Email tidak boleh kosong';
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Format email tidak valid';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _teleponController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(15),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Nomor telepon',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nomor telepon tidak boleh kosong';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _alamatController,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Alamat',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Alamat tidak boleh kosong';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Data Tambahan',
            icon: Icons.tune_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: _pilihTanggalLahir,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal lahir',
                      prefixIcon: Icon(Icons.calendar_month_outlined),
                      suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                    ),
                    child: Text(
                      _tanggalLahirLabel,
                      style: TextStyle(
                        color: _tanggalLahir == null
                            ? AppTheme.muted
                            : AppTheme.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const _Label('Jenis kelamin'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _radioJenisKelamin('Perempuan'),
                    _radioJenisKelamin('Laki-laki'),
                  ],
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: _pendidikan,
                  decoration: const InputDecoration(
                    labelText: 'Pendidikan terakhir',
                    prefixIcon: Icon(Icons.school_outlined),
                  ),
                  items: _pilihanPendidikan
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _pendidikan = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _golonganDarah,
                  decoration: const InputDecoration(
                    labelText: 'Golongan darah',
                    prefixIcon: Icon(Icons.bloodtype_outlined),
                  ),
                  items: _pilihanDarah
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _golonganDarah = value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _simpan,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Simpan Biodata'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Data hanya disimpan selama aplikasi berjalan dan tidak dikirim ke database.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _radioJenisKelamin(String nilai) {
    return ChoiceChip(
      label: Text(nilai),
      selected: _jenisKelamin == nilai,
      onSelected: (_) => setState(() => _jenisKelamin = nilai),
      selectedColor: AppTheme.brand.withValues(alpha: 0.16),
      labelStyle: TextStyle(
        color: _jenisKelamin == nilai ? AppTheme.brandDark : AppTheme.ink,
        fontWeight: _jenisKelamin == nilai ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: _jenisKelamin == nilai ? AppTheme.brand : AppTheme.border,
      ),
    );
  }

  Widget _kartuFoto() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brand.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -28,
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.72),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _fotoProfil == null
                          ? Image.asset(
                              AssignmentConfig.studentPhoto,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 92,
                                  height: 92,
                                  color: Colors.white24,
                                  child: const Icon(
                                    Icons.person_rounded,
                                    color: Colors.white,
                                    size: 54,
                                  ),
                                );
                              },
                            )
                          : Image.file(
                              _fotoProfil!,
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Material(
                      color: AppTheme.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sedangMengambilFoto ? null : _pilihSumberFoto,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: _sedangMengambilFoto
                              ? const Padding(
                                  padding: EdgeInsets.all(9),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.photo_camera_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Foto Profil',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedBuilder(
                      animation: _namaController,
                      builder: (context, child) {
                        final nama = _namaController.text.trim();
                        return Text(
                          nama.isEmpty ? 'Nama Mahasiswa' : nama,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ketuk ikon kamera untuk mengambil foto dari kamera HP.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.brand, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
