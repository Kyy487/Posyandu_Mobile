import 'package:flutter/material.dart';

import '../../models/referral.dart';
import '../../models/visit.dart';
import '../../services/referral_service.dart';
import '../../services/visit_service.dart';
import '../../utils/month_label.dart';
import '../login_screen.dart';

/// Aksi yang dipilih kader dari lembar detail rujukan.
enum _AksiRujukan { ubah, batal }

/// Rujukan satu anak: daftar, detail, dan pembuatan (Kader).
///
/// Membuat rujukan selalu menempel pada satu kunjungan (`visit_id`), jadi form
/// di sini meminta kader memilih kunjungan anak lebih dulu. Kalau anak belum
/// punya kunjungan sama sekali, tombol simpan tidak bisa ditekan - server pasti
/// menolaknya, dan lebih baik kader tahu alasannya sebelum mengisi form.
class RujukanScreen extends StatefulWidget {
  final String childId;
  final String childName;

  /// Kunjungan yang langsung terpilih di form pembuatan (opsional).
  ///
  /// Dipakai alur "buat kunjungan → input data → rujukan" dari
  /// `KunjunganScreen`, supaya kader tidak perlu memilih ulang kunjungan yang
  /// baru saja dibuatnya.
  final String? initialVisitId;

  const RujukanScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.initialVisitId,
  });

  @override
  State<RujukanScreen> createState() => _RujukanScreenState();
}

class _RujukanScreenState extends State<RujukanScreen> {
  final ReferralService _service = ReferralService();

  ReferralList? _data;
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

    if (result['success'] == true && result['data'] is ReferralList) {
      setState(() {
        _data = result['data'] as ReferralList;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _errorMessage = result['message']?.toString() ?? 'Gagal memuat rujukan.';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Rujukan'),
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
        onPressed: _bukaForm,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Buat Rujukan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[800],
      ),
    );
  }

  /// Membuka form rujukan. Tanpa [referral] berarti buat baru; dengan
  /// [referral] berarti koreksi. Muat ulang daftar bila kader menyimpannya.
  Future<void> _bukaForm({Referral? referral}) async {
    final tersimpan = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FormRujukan(
        childId: widget.childId,
        childName: widget.childName,
        service: _service,
        referral: referral,
        initialVisitId: widget.initialVisitId,
      ),
    );

    if (tersimpan == true) {
      _muatData();
    }
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
              itemCount: data.referrals.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildRingkasan(data);
                }
                final referral = data.referrals[index - 1];
                return _buildKartu(referral);
              },
            ),
    );
  }

  /// Ringkasan singkat di atas daftar.
  Widget _buildRingkasan(ReferralList data) {
    final belumSelesai = data.jumlahBelumSelesai;

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
            '${data.jumlah} rujukan'
            '${belumSelesai > 0 ? ' · $belumSelesai belum selesai' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            'Catatan rujukan yang dibuat kader saat kunjungan.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500], height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _buildKosong(ReferralList data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.local_hospital_outlined, size: 64, color: Colors.blue[200]),
          const SizedBox(height: 16),
          const Text(
            'Belum ada rujukan.',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${data.childName.isEmpty ? widget.childName : data.childName} '
            'belum pernah dirujuk ke fasilitas kesehatan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tekan "Buat Rujukan" untuk mencatat rujukan baru.',
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

  /// Satu kartu rujukan. Ketuk untuk membuka detail.
  Widget _buildKartu(Referral referral) {
    final warna = _warnaStatus(referral.status);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _bukaDetail(referral),
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
                      referral.tanggalLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _buildChip(referral.statusLabel, warna),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.local_hospital, size: 15, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      referral.facilityName?.isNotEmpty == true
                          ? referral.facilityName!
                          : referral.tipeLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildChip(referral.tipeLabel, Colors.blueGrey),
              if (referral.adaCatatan) ...[
                const SizedBox(height: 8),
                Text(
                  referral.reason!,
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

  /// Detail lengkap satu rujukan, dengan aksi koreksi dan pembatalan.
  ///
  /// Semua field sudah ada di daftar, jadi detailnya cukup ditampilkan dari
  /// objek yang sudah dimuat - tidak perlu memanggil `GET /referrals/{id}`
  /// untuk data yang sama.
  Future<void> _bukaDetail(Referral referral) async {
    final aksi = await showModalBottomSheet<_AksiRujukan>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final warna = _warnaStatus(referral.status);

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
                          'Detail Rujukan',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _buildChip(referral.statusLabel, warna),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _baris('Tanggal', referral.tanggalLabel),
                  _baris('Jenis', referral.tipeLabel),
                  _baris(
                    'Fasilitas',
                    referral.facilityName?.isNotEmpty == true
                        ? referral.facilityName!
                        : '-',
                  ),
                  _baris(
                    'Alasan',
                    referral.adaCatatan ? referral.reason! : '-',
                  ),
                  _baris(
                    'Dicatat oleh',
                    referral.kaderName ?? 'Tidak diketahui',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.pop(context, _AksiRujukan.ubah),
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Ubah'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.pop(context, _AksiRujukan.batal),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Batalkan'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || aksi == null) return;

    if (aksi == _AksiRujukan.ubah) {
      await _bukaForm(referral: referral);
    } else if (aksi == _AksiRujukan.batal) {
      await _konfirmasiBatal(referral);
    }
  }

  /// Konfirmasi lalu batalkan rujukan (soft delete di server).
  Future<void> _konfirmasiBatal(Referral referral) async {
    final setuju = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan rujukan?'),
        content: Text(
          'Rujukan tanggal ${referral.tanggalLabel} ke '
          '${referral.facilityName?.isNotEmpty == true ? referral.facilityName : 'fasilitas kesehatan'} '
          'akan dibatalkan dan hilang dari daftar serta timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );

    if (setuju != true || !mounted) return;

    final result = await _service.cancel(referral.id);
    if (!mounted) return;

    final berhasil = result['success'] == true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result['message']?.toString() ?? 'Rujukan dibatalkan.',
        ),
        backgroundColor: berhasil ? Colors.green : Colors.red,
      ),
    );

    if (berhasil) _muatData();
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

  /// Warna badge status. "dibuat" belum ditangani, "dilaporkan" sedang jalan,
  /// "selesai" selesai - urutannya sengaja dipetakan ke warna yang berbeda
  /// supaya kader bisa membedakan sekilas.
  Color _warnaStatus(String? status) {
    switch (status) {
      case ReferralStatus.dibuat:
        return Colors.orange[800] ?? Colors.orange;
      case ReferralStatus.dilaporkan:
        return Colors.blue[700] ?? Colors.blue;
      case ReferralStatus.selesai:
        return Colors.green[700] ?? Colors.green;
      default:
        return Colors.blueGrey;
    }
  }
}

/// Form rujukan dalam bottom sheet: buat baru, atau koreksi bila [referral]
/// diisi.
///
/// Dalam mode koreksi, kunjungan (`visit_id`) sengaja tidak bisa diubah -
/// server memang mengunci `child_id`/`visit_id` pada PATCH. Rujukan yang salah
/// anak/kunjungan harus dibatalkan lalu dibuat ulang.
class _FormRujukan extends StatefulWidget {
  final String childId;
  final String childName;
  final ReferralService service;

  /// Bila tidak null, form berjalan dalam mode koreksi.
  final Referral? referral;

  /// Kunjungan yang langsung terpilih saat membuat rujukan baru (opsional).
  final String? initialVisitId;

  const _FormRujukan({
    required this.childId,
    required this.childName,
    required this.service,
    this.referral,
    this.initialVisitId,
  });

  @override
  State<_FormRujukan> createState() => _FormRujukanState();
}

class _FormRujukanState extends State<_FormRujukan> {
  final _formKey = GlobalKey<FormState>();
  final _facilityController = TextEditingController();
  final _reasonController = TextEditingController();
  final VisitService _visitService = VisitService();

  late DateTime _tanggal;
  String? _tipe = ReferralTipe.puskesmas;
  String? _status = ReferralStatus.dibuat;

  List<Visit> _visits = const <Visit>[];
  bool _memuatVisits = true;
  String? _galatVisits;
  Visit? _visitDipilih;

  bool _isSaving = false;

  bool get _isEdit => widget.referral != null;

  @override
  void initState() {
    super.initState();

    if (_isEdit) {
      final r = widget.referral!;
      _tanggal = _parseTanggal(r.referralDate) ?? DateTime.now();
      _tipe = ReferralTipe.semua.contains(r.referralType)
          ? r.referralType
          : ReferralTipe.puskesmas;
      _status = ReferralStatus.semua.contains(r.status)
          ? r.status
          : ReferralStatus.dibuat;
      _facilityController.text = r.facilityName ?? '';
      _reasonController.text = r.reason ?? '';
      // Kunjungan tidak diubah, jadi tidak perlu memuat daftarnya.
      _memuatVisits = false;
      return;
    }

    _tanggal = DateTime.now();
    _muatVisits();
  }

  /// Membaca tanggal `YYYY-MM-DD` dari server. Tanggal rusak/kosong dianggap
  /// tidak ada supaya form jatuh ke hari ini, bukan crash.
  DateTime? _parseTanggal(String? nilai) {
    if (nilai == null || nilai.trim().isEmpty) return null;
    return DateTime.tryParse(nilai);
  }

  /// Mencari kunjungan berdasarkan id. Mengembalikan null bila [id] null atau
  /// tidak ada di daftar (mis. kunjungan sudah dibatalkan).
  Visit? _cariKunjungan(List<Visit> visits, String? id) {
    if (id == null) return null;
    for (final visit in visits) {
      if (visit.id == id) return visit;
    }
    return null;
  }

  @override
  void dispose() {
    _facilityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Muat daftar kunjungan anak. Rujukan wajib menempel pada salah satunya.
  Future<void> _muatVisits() async {
    setState(() {
      _memuatVisits = true;
      _galatVisits = null;
    });

    final result = await _visitService.getByChild(widget.childId);

    if (!mounted) return;

    if (result['success'] == true && result['data'] is VisitList) {
      final visits = (result['data'] as VisitList).visits;
      setState(() {
        _visits = visits;
        // Kalau layar meminta kunjungan tertentu (alur "buat kunjungan →
        // rujukan"), pakai itu; kalau tidak, kunjungan terbaru sebagai titik
        // awal yang paling mungkin. Kader tetap bisa menggantinya.
        _visitDipilih = _cariKunjungan(visits, widget.initialVisitId) ??
            (visits.isEmpty ? null : visits.first);
        _memuatVisits = false;
      });
      return;
    }

    setState(() {
      _memuatVisits = false;
      _galatVisits =
          result['message']?.toString() ?? 'Gagal memuat daftar kunjungan.';
    });
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
    final visit = _visitDipilih;

    if (!_isEdit && visit == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih kunjungan tujuan rujukan terlebih dahulu.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final tanggal = _tanggal.toIso8601String().substring(0, 10);
    final alasan = _reasonController.text.trim();
    final fasilitas = _facilityController.text.trim();

    final result = _isEdit
        ? await widget.service.update(
            referralId: widget.referral!.id,
            referralDate: tanggal,
            referralType: _tipe,
            reason: alasan,
            facilityName: fasilitas,
            status: _status,
          )
        : await widget.service.create(
            childId: widget.childId,
            visitId: visit!.id,
            referralDate: tanggal,
            referralType: _tipe ?? ReferralTipe.puskesmas,
            reason: alasan,
            facilityName: fasilitas,
            status: _status,
          );

    if (!mounted) return;

    setState(() => _isSaving = false);

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                (_isEdit
                    ? 'Rujukan berhasil diperbarui.'
                    : 'Rujukan berhasil disimpan.'),
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

  /// Menggabungkan pesan utama dengan detail validasi per field dari Laravel.
  String _pesanError(Map<String, dynamic> result) {
    var pesan = result['message']?.toString() ?? 'Gagal menyimpan rujukan.';
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
                _isEdit ? 'Koreksi Rujukan' : 'Buat Rujukan',
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

              // Kunjungan: dikunci saat koreksi, dapat dipilih saat membuat.
              if (_isEdit)
                _buildKunjunganTerkunci()
              else if (_memuatVisits)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_galatVisits != null)
                _buildGalatVisits(_galatVisits!)
              else if (_visits.isEmpty)
                _buildTanpaKunjungan()
              else
                DropdownButtonFormField<Visit>(
                  initialValue: _visitDipilih,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Kunjungan',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final visit in _visits)
                      DropdownMenuItem<Visit>(
                        value: visit,
                        child: Text(
                          visit.ringkasan,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _visitDipilih = v),
                ),
              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month, color: Colors.blue),
                title: const Text(
                  'Tanggal Rujukan',
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
                  labelText: 'Jenis Fasilitas Tujuan',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final tipe in ReferralTipe.semua)
                    DropdownMenuItem<String>(
                      value: tipe,
                      child: Text(ReferralTipe.label(tipe)),
                    ),
                ],
                onChanged: (v) => setState(() => _tipe = v),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _facilityController,
                maxLength: 255,
                decoration: const InputDecoration(
                  labelText: 'Nama Fasilitas',
                  hintText: 'Contoh: Puskesmas Sukamaju',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Nama fasilitas wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 4),

              TextFormField(
                controller: _reasonController,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Alasan Rujukan',
                  hintText: 'Contoh: Demam tinggi 3 hari, perlu pemeriksaan lab.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Alasan rujukan wajib diisi.'
                    : null,
              ),
              const SizedBox(height: 4),

              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final status in ReferralStatus.semua)
                    DropdownMenuItem<String>(
                      value: status,
                      child: Text(ReferralStatus.label(status)),
                    ),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
              const SizedBox(height: 16),

              FilledButton.icon(
                onPressed: (_isSaving || (!_isEdit && _visitDipilih == null))
                    ? null
                    : _simpan,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isEdit ? 'Simpan Perubahan' : 'Simpan Rujukan'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGalatVisits(String pesan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pesan,
            style: TextStyle(fontSize: 12, color: Colors.red[700]),
          ),
          TextButton.icon(
            onPressed: _muatVisits,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    );
  }

  /// Anak belum punya kunjungan. Rujukan selalu menempel pada kunjungan, jadi
  /// tidak ada yang bisa dipilih sampai kunjungan dibuat.
  Widget _buildTanpaKunjungan() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.childName} belum punya kunjungan. Buat kunjungan '
              'terlebih dahulu sebelum mencatat rujukan.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber[900],
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Penanda bahwa kunjungan terkunci saat koreksi.
  ///
  /// Rujukan selalu menempel pada kunjungan tempat ia dibuat; memindahkannya ke
  /// kunjungan lain berarti mengubah rekam medis, jadi server mengunci
  /// `visit_id` pada PATCH.
  Widget _buildKunjunganTerkunci() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: Colors.blueGrey[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kunjungan tidak dapat diubah. Bila rujukan salah kunjungan, '
              'batalkan lalu buat ulang.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey[800],
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
