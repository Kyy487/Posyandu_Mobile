import 'package:flutter/material.dart';

import '/../../models/medical_note.dart';
import '/../../services/medical_note_service.dart';
// Tetap diimpor seperti sebelumnya (widget bersama dengan layar Ibu). Kartu dan
// keadaan kosong di layar ini digambar sendiri supaya layar Ibu tidak berubah.
// ignore: unused_import
import '/../../widgets/medical_note_list_view.dart';
import '/../../screens/shared/login_screen.dart';

// Warna lokal layar ini, mengikuti palet desain Kader.
const Color _teal = Color(0xFF0E7C7B);
const Color _ink = Color(0xFF12302F);
const Color _muted = Color(0xFF5C7F7C);
const Color _koral = Color(0xFFF2845C);
const Color _permukaan = Color(0xFFF2F6F5);
const Color _amber = Color(0xFF9A6B00);
const Color _demam = Color(0xFFD64545);
const Color _rewel = Color(0xFFE08A1E);
const Color _diare = Color(0xFF4A6FA5);

const _bulanPanjang = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

/// "24 Oktober 2026" dari teks ISO; teks asli bila tidak bisa dibaca.
String _tanggalIndo(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return iso ?? '-';
  return '${d.day} ${_bulanPanjang[d.month - 1]} ${d.year}';
}

/// Catatan keluhan untuk Kader: daftar, catat baru, koreksi, dan batalkan.
///
/// Kader memakai layar terpisah dari Ibu karena endpoint tulisnya ada di
/// prefix `/kader/`. Role `ibu` tidak akan pernah sampai ke sini lewat UI,
/// dan backend juga menolak request tulis dari role tersebut.
///
/// Tampilan baru: kartu catatan dengan label keluhan berikon, pilihan
/// "Bulan ini / Semua bulan" berupa chip, dan form berupa lembar dari bawah
/// dengan tombol keluhan besar. Seluruh logika sama seperti sebelumnya.
class CatatanKeluhanScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Id penimbangan yang dipakai bila kader mencatat keluhan sekaligus
  /// menimbang. Null berarti catatan tetap sah tanpa penimbangan, karena
  /// anak bisa mengeluh tanpa ditimbang hari itu juga.
  final String? measurementId;

  /// Kunjungan tempat catatan baru menempel (opsional). Dipakai alur "buat
  /// kunjungan → input data" dari `KunjunganScreen`.
  final String? visitId;

  /// Label kunjungan untuk ditampilkan di banner. Boleh null bila [visitId]
  /// null.
  final String? visitLabel;

  const CatatanKeluhanScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.measurementId,
    this.visitId,
    this.visitLabel,
  });

  @override
  State<CatatanKeluhanScreen> createState() => _CatatanKeluhanScreenState();
}

class _CatatanKeluhanScreenState extends State<CatatanKeluhanScreen> {
  final MedicalNoteService _service = MedicalNoteService();

  MedicalNoteList? _data;

  /// Spinner penuh hanya untuk muat pertama; muat ulang berikutnya (ganti
  /// bulan, refresh) cukup bar tipis supaya daftar tidak berkedip.
  bool _isLoading = true;
  bool _menyegarkan = false;
  String? _errorMessage;

  /// false = bulan berjalan, true = semua bulan.
  bool _semuaBulan = false;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() {
      _errorMessage = null;
      _menyegarkan = true;
    });

    final result = await _service.getNotes(widget.childId, all: _semuaBulan);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is MedicalNoteList) {
      setState(() {
        _data = result['data'] as MedicalNoteList;
        _isLoading = false;
        _menyegarkan = false;
      });
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat catatan.';
      _isLoading = false;
      _menyegarkan = false;
    });
  }

  void _setSemuaBulan(bool nilai) {
    if (_semuaBulan == nilai) return;
    setState(() => _semuaBulan = nilai);
    _muatData();
  }

  Future<void> _bukaForm({MedicalNote? note}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (context) => _FormCatatanKeluhan(
        childId: widget.childId,
        service: _service,
        note: note,
        measurementId: widget.measurementId,
        visitId: widget.visitId,
      ),
    );

    if (tersimpan == true) {
      _muatData();
    }
  }

  // ----------------------------------------------------------------- BUILD

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _permukaan,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaForm(),
        backgroundColor: _koral,
        foregroundColor: Colors.white,
        elevation: 6,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Catat Keluhan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _barAtas(),
          Expanded(child: _buildBody()),
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
            _tombolBar(
              Icons.arrow_back_rounded,
              'Kembali',
              Colors.white,
              _ink,
              () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Catatan Keluhan',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  Text(
                    widget.childName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            _tombolBar(
              Icons.refresh_rounded,
              'Muat ulang',
              _teal.withValues(alpha: 0.12),
              _teal,
              _menyegarkan ? null : _muatData,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tombolBar(
    IconData ikon,
    String tooltip,
    Color latar,
    Color warnaIkon,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: latar,
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              ikon,
              size: 24,
              color: onTap == null ? warnaIkon.withValues(alpha: 0.4) : warnaIkon,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _data == null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
        children: [
          if (widget.visitId != null) ...[
            _buildBannerKunjungan(),
            const SizedBox(height: 12),
          ],
          _barisFilter(data),
          const SizedBox(height: 6),
          SizedBox(
            height: 3,
            child: _menyegarkan
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: const LinearProgressIndicator(),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (data.notes.isEmpty)
            _kosong()
          else
            for (final n in data.notes) _kartuCatatan(n),
        ],
      ),
    );
  }

  Widget _barisFilter(MedicalNoteList data) {
    return Row(
      children: [
        _chipBulan('Bulan ini', Icons.calendar_today_rounded, !_semuaBulan, () {
          _setSemuaBulan(false);
        }),
        const SizedBox(width: 8),
        _chipBulan('Semua bulan', Icons.date_range_rounded, _semuaBulan, () {
          _setSemuaBulan(true);
        }),
        const Spacer(),
        Flexible(
          child: Text(
            data.labelFilter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _chipBulan(String label, IconData ikon, bool aktif, VoidCallback onTap) {
    return Material(
      color: aktif ? _teal : Colors.white,
      elevation: aktif ? 0 : 1,
      shadowColor: Colors.black12,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikon, size: 16, color: aktif ? Colors.white : _muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: aktif ? Colors.white : _ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ KARTU

  Widget _kartuCatatan(MedicalNote n) {
    final gejala = <(IconData, String, Color)>[
      if (n.demam == true) (Icons.thermostat_rounded, 'Demam', _demam),
      if (n.rewel == true)
        (Icons.sentiment_dissatisfied_rounded, 'Rewel', _rewel),
      if (n.diare == true) (Icons.water_drop_outlined, 'Diare', _diare),
    ];
    final catatan = (n.catatan ?? '').toString().trim();
    final tindak = n.tindakLanjut;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _bukaForm(note: n),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.sticky_note_2_outlined,
                        size: 22,
                        color: _amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _tanggalIndo(n.noteDate),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ],
                ),
                const SizedBox(height: 12),
                if (gejala.isEmpty)
                  const Text(
                    'Tanpa keluhan tercatat, hanya catatan.',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: _muted,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in gejala) _chipGejala(g.$1, g.$2, g.$3),
                    ],
                  ),
                if (catatan.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    catatan,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: _ink,
                      height: 1.4,
                    ),
                  ),
                ],
                if (tindak != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.flag_outlined, size: 16, color: _teal),
                      const SizedBox(width: 6),
                      Text(
                        'Tindak lanjut: ${TindakLanjut.label(tindak)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _teal,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipGejala(IconData ikon, String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikon, size: 15, color: warna),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: warna,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kosong() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
      child: Column(
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 56, color: _muted),
          const SizedBox(height: 14),
          const Text(
            'Belum ada catatan keluhan',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _semuaBulan
                ? 'Belum pernah ada catatan keluhan untuk anak ini.'
                : 'Tidak ada catatan bulan ini. Pilih "Semua bulan" untuk '
                      'melihat yang lebih lama.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.4, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Penanda bahwa catatan baru menempel pada satu kunjungan.
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
                  'Catatan baru menempel pada kunjungan',
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

  Widget _buildErrorState(String pesan) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: _muted),
            const SizedBox(height: 16),
            const Text(
              'Gagal memuat catatan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _muatData,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form catatan keluhan dalam bottom sheet.
///
/// Satu form melayani dua mode. [note] null berarti membuat catatan baru;
/// filled berarti mengoreksi catatan yang sudah ada. Bedanya penting karena
/// backend menolak duplikat tanggal dengan 422 - merevisi catatan yang ada
/// adalah respons yang benar, bukan mencatat yang baru.
class _FormCatatanKeluhan extends StatefulWidget {
  final String childId;
  final MedicalNoteService service;
  final MedicalNote? note;
  final String? measurementId;

  /// Kunjungan tempat catatan baru menempel (opsional). Diabaikan saat koreksi
  /// catatan lama.
  final String? visitId;

  const _FormCatatanKeluhan({
    required this.childId,
    required this.service,
    this.note,
    this.measurementId,
    this.visitId,
  });

  @override
  State<_FormCatatanKeluhan> createState() => _FormCatatanKeluhanState();
}

class _FormCatatanKeluhanState extends State<_FormCatatanKeluhan> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _catatanController = TextEditingController();

  late DateTime _tanggal;
  late bool _demamAktif;
  late bool _rewelAktif;
  late bool _diareAktif;
  String? _tindakLanjut;

  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isEdit => widget.note != null;

  @override
  void initState() {
    super.initState();

    final note = widget.note;
    _tanggal = DateTime.tryParse(note?.noteDate ?? '') ?? DateTime.now();
    _demamAktif = note?.demam ?? false;
    _rewelAktif = note?.rewel ?? false;
    _diareAktif = note?.diare ?? false;
    _tindakLanjut = note?.tindakLanjut;
    _catatanController.text = note?.catatan ?? '';
  }

  @override
  void dispose() {
    _catatanController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _tanggal = picked);
    }
  }

  /// Validasi lokal yang mencerminkan CHECK constraint di database.
  ///
  /// Server tetap memvalidasi ulang - ini hanya supaya kader mendapat umpan
  /// balik cepat tanpa satu putaran jaringan, dan supaya alasan catatan tidak
  /// bisa disimpan terlihat sebelum menekan tombol.
  ///
  /// Mengembalikan null berarti isi catatan sudah sah.
  String? _validasiIsi() {
    if (!_demamAktif &&
        !_rewelAktif &&
        !_diareAktif &&
        _catatanController.text.trim().isEmpty) {
      return 'Pilih minimal satu keluhan, atau isi catatan.';
    }
    return null;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final pesanLokal = _validasiIsi();
    if (pesanLokal != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pesanLokal), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final catatan = _catatanController.text.trim();

    final result = _isEdit
        ? await widget.service.updateNote(
            noteId: widget.note!.id,
            noteDate: tanggal,
            demam: _demamAktif,
            rewel: _rewelAktif,
            diare: _diareAktif,
            catatan: catatan,
            tindakLanjut: _tindakLanjut,
          )
        : await widget.service.addNote(
            childId: widget.childId,
            noteDate: tanggal,
            demam: _demamAktif,
            rewel: _rewelAktif,
            diare: _diareAktif,
            catatan: catatan,
            tindakLanjut: _tindakLanjut,
            measurementId: widget.measurementId,
            visitId: widget.visitId,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit
                    ? 'Catatan diperbarui.'
                    : 'Catatan keluhan tersimpan.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_pesanError(result)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Membatalkan catatan yang keliru tercatat.
  ///
  /// Yang biasanya salah adalah tanggalnya, bukan keluhan anak. Karena tanggal
  /// boleh diubah lewat PATCH, pembatalan sebaiknya jadi pilihan terakhir -
  /// untuk salah tanggal, pilih Ubah saja.
  Future<void> _hapus() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan catatan?'),
        content: const Text(
          'Catatan keluhan ini akan dibatalkan.\n\n'
          'Data tidak hilang permanen dari database, dan tanggal yang sama '
          'boleh dicatat ulang nanti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );

    if (konfirmasi != true) return;

    setState(() => _isDeleting = true);

    final result = await widget.service.cancelNote(widget.note!.id);

    if (!mounted) return;

    setState(() => _isDeleting = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? 'Catatan dibatalkan.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_pesanError(result)),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Menggabungkan pesan utama dengan detail validasi per field dari Laravel.
  String _pesanError(Map<String, dynamic> result) {
    var pesan = result['message']?.toString() ?? 'Gagal menyimpan.';
    final errors = result['errors'];

    if (errors is Map) {
      final detail = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
      if (detail.isNotEmpty) pesan = '$pesan\n$detail';
    }

    return pesan;
  }

  // ----------------------------------------------------------------- BUILD

  Widget _tileGejala(
    IconData ikon,
    String label,
    Color warna,
    bool aktif,
    ValueChanged<bool> onChanged,
  ) {
    return Expanded(
      child: Material(
        color: aktif ? warna.withValues(alpha: 0.14) : _permukaan,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => onChanged(!aktif),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: aktif ? warna : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(ikon, size: 28, color: aktif ? warna : _muted),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: aktif ? warna : _ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFE0DD),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.sticky_note_2_outlined,
                      size: 28,
                      color: _amber,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEdit ? 'Koreksi Catatan Keluhan' : 'Catat Keluhan',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Tutup',
                    child: Material(
                      color: _permukaan,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(false),
                        borderRadius: BorderRadius.circular(14),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(Icons.close_rounded, color: _ink),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tanggal. Bisa diubah walau mode koreksi, karena salah pilih
              // tanggal di kalender adalah kesalahan yang wajar terjadi.
              Material(
                color: _permukaan,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          color: _amber,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Tanggal keluhan',
                                style: TextStyle(fontSize: 12, color: _muted),
                              ),
                              Text(
                                _tanggalIndo(
                                  _tanggal.toIso8601String().substring(0, 10),
                                ),
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
              ),
              const SizedBox(height: 18),

              const Text(
                'Keluhan yang dilihat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Boleh lebih dari satu. Bila tidak ada keluhan, cukup isi '
                'catatan saja.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _tileGejala(
                    Icons.thermostat_rounded,
                    'Demam',
                    _demam,
                    _demamAktif,
                    (v) => setState(() => _demamAktif = v),
                  ),
                  const SizedBox(width: 10),
                  _tileGejala(
                    Icons.sentiment_dissatisfied_rounded,
                    'Rewel',
                    _rewel,
                    _rewelAktif,
                    (v) => setState(() => _rewelAktif = v),
                  ),
                  const SizedBox(width: 10),
                  _tileGejala(
                    Icons.water_drop_outlined,
                    'Diare',
                    _diare,
                    _diareAktif,
                    (v) => setState(() => _diareAktif = v),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _catatanController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: 'Catatan (opsional)',
                  hintText: 'Contoh: Demam sejak semalam, masih mau makan.',
                  filled: true,
                  fillColor: _permukaan,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              const Text(
                'Tindak lanjut',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Boleh dikosongkan bila kader memutuskan nanti.',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(height: 8),
              // Radio butuh satu ancestor yang memegang nilai grup, jadi
              // `RadioListTile` tidak lagi menerima groupValue/onChanged
              // secara langsung (deprecated sejak Flutter 3.32).
              Container(
                decoration: BoxDecoration(
                  color: _permukaan,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: RadioGroup<String>(
                  groupValue: _tindakLanjut,
                  onChanged: (v) => setState(() => _tindakLanjut = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final pilihan in TindakLanjut.semua)
                        RadioListTile<String>(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          activeColor: _teal,
                          value: pilihan,
                          title: Text(
                            TindakLanjut.label(pilihan),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            TindakLanjut.petunjuk(pilihan),
                            style: const TextStyle(
                              fontSize: 11,
                              color: _muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_tindakLanjut != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _tindakLanjut = null),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text(
                      'Kosongkan pilihan',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),

              const SizedBox(height: 16),
              DecoratedBox(
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
                  height: 58,
                  child: FilledButton.icon(
                    onPressed: (_isSaving || _isDeleting) ? null : _simpan,
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
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _isEdit ? 'Simpan Perubahan' : 'Simpan Catatan',
                    ),
                  ),
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: (_isSaving || _isDeleting) ? null : _hapus,
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  icon: _isDeleting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Batalkan Catatan'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}