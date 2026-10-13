import 'package:flutter/material.dart';

import '../../models/visit.dart';
import '../../services/visit_service.dart';
import '../../utils/month_label.dart';
import '../login_screen.dart';
import 'catatan_keluhan_screen.dart';
import 'imunisasi_screen.dart';
import 'input_penimbangan_screen.dart';
import 'rujukan_screen.dart';

/// Aksi yang dipilih kader dari lembar detail kunjungan.
enum _AksiKunjungan { ubah }

/// Jenis data yang bisa dicatat pada satu kunjungan.
///
/// Dipakai alur "buat kunjungan → input data → selesai": setelah kunjungan
/// tersimpan, kader memilih data apa yang mau dicatat, dan layar yang dibuka
/// membawa `visit_id` kunjungan itu.
enum _JenisInput { penimbangan, imunisasi, keluhan, rujukan }

/// Kunjungan satu anak: daftar, detail, dan pembuatan (Kader).
///
/// Kunjungan adalah "wadah" satu sesi layanan. Rujukan menempel pada kunjungan,
/// jadi layar ini juga yang membuat rujukan mungkin walau anak belum punya
/// kunjungan sama sekali (lihat `docs/RANCANGAN_VISIT.md`).
class KunjunganScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const KunjunganScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<KunjunganScreen> createState() => _KunjunganScreenState();
}

class _KunjunganScreenState extends State<KunjunganScreen> {
  final VisitService _service = VisitService();

  VisitList? _data;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _muatData();
  }

  Future<void> _muatData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _service.getByChild(widget.childId);

    if (!mounted) return;

    if (result['status'] == 401) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      return;
    }

    if (result['success'] == true && result['data'] is VisitList) {
      setState(() {
        _data = result['data'] as VisitList;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage =
          result['message']?.toString() ?? 'Gagal memuat daftar kunjungan.';
      _isLoading = false;
    });
  }

  /// Membuka form kunjungan. Tanpa [visit] berarti buat baru; dengan [visit]
  /// berarti koreksi.
  ///
  /// Setelah membuat kunjungan baru, lanjut ke alur input data supaya kader
  /// bisa langsung mencatat penimbangan/imunisasi/keluhan/rujukan pada
  /// kunjungan itu - itulah inti "buat kunjungan → input data → selesai".
  Future<void> _bukaForm({Visit? visit}) async {
    final hasil = await showModalBottomSheet<Visit>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormKunjungan(
        childId: widget.childId,
        childName: widget.childName,
        service: _service,
        visit: visit,
      ),
    );

    if (!mounted || hasil == null) return;

    await _muatData();

    // Hanya kunjungan BARU yang menawarkan alur. Koreksi kunjungan tidak,
    // supaya kader tidak diarahkan mencatat data setiap kali memperbaiki typo.
    if (mounted && visit == null) {
      await _tawarkanInputData(hasil);
    }
  }

  /// Menawarkan pencatatan data pada [visit] sampai kader memilih "Selesai".
  ///
  /// Diulang, bukan sekali jalan: satu kunjungan biasanya butuh lebih dari satu
  /// jenis data (timbang lalu imunisasi lalu catatan keluhan). Tiap selesai
  /// satu, jumlah data di daftar disegarkan dan pilihan muncul lagi.
  Future<void> _tawarkanInputData(Visit visit) async {
    var pilihan = await _pilihJenisInput(visit);

    while (pilihan != null && mounted) {
      await _bukaInput(pilihan, visit);

      if (!mounted) return;

      await _muatData();
      if (!mounted) return;

      pilihan = await _pilihJenisInput(visit);
    }
  }

  /// Lembar pilihan jenis data. Null berarti kader selesai/menutup lembar.
  Future<_JenisInput?> _pilihJenisInput(Visit visit) {
    return showModalBottomSheet<_JenisInput>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  'Catat data untuk kunjungan ini',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  visit.ringkasan,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              _tileInput(
                _JenisInput.penimbangan,
                Icons.monitor_weight_outlined,
                'Penimbangan',
                'Berat dan tinggi badan',
              ),
              _tileInput(
                _JenisInput.imunisasi,
                Icons.vaccines,
                'Imunisasi',
                'Catat suntikan dosis',
              ),
              _tileInput(
                _JenisInput.keluhan,
                Icons.monitor_heart_outlined,
                'Catatan Keluhan',
                'Demam, rewel, diare, tindak lanjut',
              ),
              _tileInput(
                _JenisInput.rujukan,
                Icons.local_hospital_outlined,
                'Rujukan',
                'Rujuk ke fasilitas kesehatan',
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Selesai'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tileInput(
    _JenisInput jenis,
    IconData ikon,
    String judul,
    String keterangan,
  ) {
    return ListTile(
      leading: Icon(ikon, color: Colors.blue[800]),
      title: Text(judul),
      subtitle: Text(keterangan, style: const TextStyle(fontSize: 11)),
      onTap: () => Navigator.pop(context, jenis),
    );
  }

  /// Membuka layar input yang sesuai, membawa `visit_id` kunjungan.
  Future<void> _bukaInput(_JenisInput jenis, Visit visit) async {
    final label = visit.ringkasan;

    final Widget layar;
    switch (jenis) {
      case _JenisInput.penimbangan:
        layar = InputPenimbanganScreen(
          childId: widget.childId,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.imunisasi:
        layar = ImunisasiScreen(
          childId: widget.childId,
          childName: widget.childName,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.keluhan:
        layar = CatatanKeluhanScreen(
          childId: widget.childId,
          childName: widget.childName,
          visitId: visit.id,
          visitLabel: label,
        );
      case _JenisInput.rujukan:
        layar = RujukanScreen(
          childId: widget.childId,
          childName: widget.childName,
          initialVisitId: visit.id,
        );
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => layar),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Kunjungan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _muatData,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _bukaForm(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Buat Kunjungan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[800],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    final data = _data;
    if (data == null) {
      return _buildErrorState('Data tidak tersedia.');
    }

    return RefreshIndicator(
      onRefresh: _muatData,
      child: data.kosong
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [_buildKosong(data)],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: data.visits.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildRingkasan(data);
                }
                return _buildKartu(data.visits[index - 1]);
              },
            ),
    );
  }

  /// Ringkasan singkat di atas daftar.
  Widget _buildRingkasan(VisitList data) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.childName.isEmpty ? widget.childName : data.childName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${data.jumlah} kunjungan tercatat',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            'Satu kunjungan menjadi wadah penimbangan, imunisasi, keluhan, '
            'dan rujukan pada satu sesi layanan.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildKosong(VisitList data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.event_available, size: 64, color: Colors.blue[200]),
          const SizedBox(height: 16),
          const Text(
            'Belum ada kunjungan.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${data.childName.isEmpty ? widget.childName : data.childName} '
            'belum punya kunjungan layanan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tekan "Buat Kunjungan" untuk mencatat kunjungan baru. Rujukan '
            'butuh kunjungan, jadi mulai dari sini.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey),
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
            Icon(Icons.cloud_off, size: 64, color: Colors.blue[200]),
            const SizedBox(height: 16),
            Text(
              pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _muatData,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }

  /// Satu kartu kunjungan. Ketuk untuk membuka detail.
  Widget _buildKartu(Visit visit) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _bukaDetail(visit),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      visit.tanggalLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _buildChip(visit.tipeLabel, Colors.blueGrey),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 15, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      visit.kaderName ?? 'Kader tidak diketahui',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildDataTertaut(visit),
              if (visit.anamnesis != null) ...[
                const SizedBox(height: 8),
                Text(
                  visit.anamnesis!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[700],
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Baris jumlah data yang menempel pada kunjungan ini.
  Widget _buildDataTertaut(Visit visit) {
    if (!visit.adaDataTertaut) {
      return Text(
        'Belum ada data tercatat pada kunjungan ini.',
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey[500],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (visit.jumlahPengukuran > 0)
          _buildChip('${visit.jumlahPengukuran} penimbangan', Colors.blue),
        if (visit.jumlahImunisasi > 0)
          _buildChip('${visit.jumlahImunisasi} imunisasi', Colors.teal),
        if (visit.jumlahKeluhan > 0)
          _buildChip('${visit.jumlahKeluhan} keluhan', Colors.orange[800]!),
      ],
    );
  }

  Widget _buildChip(String label, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: warna,
        ),
      ),
    );
  }

  /// Detail lengkap satu kunjungan, dengan aksi koreksi.
  ///
  /// Data yang ditampilkan cukup yang dibawa daftar - anamnesis, catatan kader,
  /// dan jumlah data tertaut. Detail penimbangan/imunisasi/keluhan dibuka lewat
  /// layarnya masing-masing, bukan di sini.
  Future<void> _bukaDetail(Visit visit) async {
    final aksi = await showModalBottomSheet<_AksiKunjungan>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Detail Kunjungan',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildChip(visit.tipeLabel, Colors.blueGrey),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _baris('Tanggal', visit.tanggalLabel),
                  _baris('Jenis', visit.tipeLabel),
                  _baris('Kader', visit.kaderName ?? 'Tidak diketahui'),
                  _baris('Penimbangan', '${visit.jumlahPengukuran}'),
                  _baris('Imunisasi', '${visit.jumlahImunisasi}'),
                  _baris('Keluhan', '${visit.jumlahKeluhan}'),
                  _baris(
                    'Anamnesis',
                    visit.anamnesis?.isNotEmpty == true ? visit.anamnesis! : '-',
                  ),
                  _baris(
                    'Catatan Kader',
                    visit.catatanKader?.isNotEmpty == true
                        ? visit.catatanKader!
                        : '-',
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, _AksiKunjungan.ubah),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Ubah'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || aksi == null) return;

    if (aksi == _AksiKunjungan.ubah) {
      await _bukaForm(visit: visit);
    }
  }

  Widget _baris(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form kunjungan dalam bottom sheet: buat baru, atau koreksi bila [visit]
/// diisi.
///
/// `child_id` sengaja tidak bisa diubah: kunjungan yang salah anak dibatalkan
/// lalu dibuat ulang (lihat `VisitController@update`).
class _FormKunjungan extends StatefulWidget {
  final String childId;
  final String childName;
  final VisitService service;

  /// Bila tidak null, form berjalan dalam mode koreksi.
  final Visit? visit;

  const _FormKunjungan({
    required this.childId,
    required this.childName,
    required this.service,
    this.visit,
  });

  @override
  State<_FormKunjungan> createState() => _FormKunjunganState();
}

class _FormKunjunganState extends State<_FormKunjungan> {
  final _formKey = GlobalKey<FormState>();
  final _anamnesisController = TextEditingController();
  final _catatanController = TextEditingController();

  late DateTime _tanggal;
  String? _tipe = VisitTipe.posyandu;
  bool _isSaving = false;

  bool get _isEdit => widget.visit != null;

  @override
  void initState() {
    super.initState();

    if (_isEdit) {
      final v = widget.visit!;
      _tanggal = _parseTanggal(v.visitDate) ?? DateTime.now();
      _tipe = VisitTipe.semua.contains(v.visitType)
          ? v.visitType
          : VisitTipe.posyandu;
      _anamnesisController.text = v.anamnesis ?? '';
      _catatanController.text = v.catatanKader ?? '';
      return;
    }

    _tanggal = DateTime.now();
  }

  @override
  void dispose() {
    _anamnesisController.dispose();
    _catatanController.dispose();
    super.dispose();
  }

  /// Membaca tanggal `YYYY-MM-DD` dari server. Tanggal rusak/kosong dianggap
  /// tidak ada supaya form jatuh ke hari ini, bukan crash.
  DateTime? _parseTanggal(String? nilai) {
    if (nilai == null || nilai.trim().isEmpty) return null;
    return DateTime.tryParse(nilai);
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

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final anamnesis = _anamnesisController.text.trim();
    final catatan = _catatanController.text.trim();

    final result = _isEdit
        ? await widget.service.update(
            visitId: widget.visit!.id,
            visitDate: tanggal,
            visitType: _tipe,
            anamnesis: anamnesis,
            catatanKader: catatan,
          )
        : await widget.service.create(
            childId: widget.childId,
            visitDate: tanggal,
            visitType: _tipe ?? VisitTipe.posyandu,
            anamnesis: anamnesis,
            catatanKader: catatan,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit
                    ? 'Kunjungan berhasil diperbarui.'
                    : 'Kunjungan berhasil disimpan.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
      // Kembalikan kunjungan hasil simpan supaya layar bisa menawarkan input
      // data yang menempel padanya.
      Navigator.of(context).pop(result['data'] as Visit?);
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
    var pesan = result['message']?.toString() ?? 'Gagal menyimpan kunjungan.';
    final errors = result['errors'];

    if (errors is Map) {
      final detail = errors.values
          .map((e) => e is List ? e.join(', ') : e.toString())
          .join('\n');
      if (detail.isNotEmpty) pesan = '$pesan\n$detail';
    }

    return pesan;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isEdit ? 'Koreksi Kunjungan' : 'Buat Kunjungan',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.childName,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: Colors.blue),
                title: const Text(
                  'Tanggal Kunjungan',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  '${labelTanggal(_tanggal.toIso8601String().substring(0, 10))}'
                  ' · tidak boleh melebihi hari ini',
                ),
                trailing: OutlinedButton(
                  onPressed: _isSaving ? null : _pickDate,
                  child: const Text('Ubah'),
                ),
              ),
              const SizedBox(height: 4),

              DropdownButtonFormField<String>(
                initialValue: _tipe,
                decoration: const InputDecoration(
                  labelText: 'Jenis Kunjungan',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final tipe in VisitTipe.semua)
                    DropdownMenuItem<String>(
                      value: tipe,
                      child: Text(VisitTipe.label(tipe)),
                    ),
                ],
                onChanged: (v) => setState(() => _tipe = v),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _anamnesisController,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Anamnesis (opsional)',
                  hintText: 'Contoh: Ibu melaporkan anak demam sejak 2 hari.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),

              TextFormField(
                controller: _catatanController,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Catatan Kader (opsional)',
                  hintText: 'Contoh: Diarahkan kembali bulan depan.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: _isSaving ? null : _simpan,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _isEdit ? 'Simpan Perubahan' : 'Simpan Kunjungan',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
