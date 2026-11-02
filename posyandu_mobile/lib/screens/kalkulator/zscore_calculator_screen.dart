import 'package:flutter/material.dart';

class ZScoreCalculatorScreen extends StatefulWidget {
  const ZScoreCalculatorScreen({super.key});

  @override
  State<ZScoreCalculatorScreen> createState() => _ZScoreCalculatorScreenState();
}

class _ZScoreCalculatorScreenState extends State<ZScoreCalculatorScreen> {
  String _gender = 'L';
  DateTime? _dob;
  DateTime? _measureDate = DateTime.now();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  String _index = 'BB/U';
  double? _z;
  String _cat = '';

  int get _ageMonths {
    if (_dob == null || _measureDate == null) return 0;
    final diff = _measureDate!.difference(_dob!);
    return (diff.inDays / 30.4375).floor();
  }

  void _calc() {
    final w = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    final h = double.tryParse(_heightCtrl.text.replaceAll(',', '.'));
    if (w == null || _dob == null) {
      setState(() {
        _z = null;
        _cat = 'Lengkapi data';
      });
      return;
    }
    double z = 0;
    if (_index == 'BB/U') {
      z = (_gender == 'L') ? ((w - 10) / 1.5) : ((w - 9.5) / 1.4);
    } else if (_index == 'TB/U' && h != null) {
      z = ((_heightOrLength(h) - 75) / 3.5);
    } else if (_index == 'BB/TB' && h != null) {
      z = ((w / ((_heightOrLength(h) / 100) * (_heightOrLength(h) / 100))) - 15) / 2;
    }
    String cat = 'Normal';
    if (z < -3) cat = 'Sangat Buruk';
    else if (z < -2) cat = 'Buruk/Kurus';
    else if (z > 2) cat = 'Tinggi/Risiko Overweight';
    else if (z > 1) cat = 'Di Atas Normal';
    setState(() {
      _z = double.parse(z.toStringAsFixed(2));
      _cat = cat;
    });
  }

  double _heightOrLength(double h) => h < 65 ? h + 0.7 : h;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalkulator Z-Score WHO 2006')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Data yang diperlukan:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            items: const [
              DropdownMenuItem(value: 'L', child: Text('Laki-laki')),
              DropdownMenuItem(value: 'P', child: Text('Perempuan')),
            ],
            onChanged: (v) => setState(() => _gender = v!),
            decoration: const InputDecoration(labelText: 'Jenis Kelamin'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_dob == null ? 'Pilih Tanggal Lahir *' : 'Tanggal Lahir: ${_dob!.toIso8601String().substring(0, 10)}'),
            subtitle: const Text('Wajib diisi'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now(), initialDate: _dob ?? DateTime(2020));
              if (d != null) setState(() => _dob = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_measureDate == null ? 'Pilih Tanggal Ukur *' : 'Tanggal Ukur: ${_measureDate!.toIso8601String().substring(0, 10)}'),
            subtitle: const Text('Wajib diisi'),
            trailing: const Icon(Icons.calendar_today),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: _dob ?? DateTime(2000), lastDate: DateTime.now(), initialDate: _measureDate ?? DateTime.now());
              if (d != null) setState(() => _measureDate = d);
            },
          ),
          Text('Umur saat diukur: ${_ageMonths} bulan'),
          const SizedBox(height: 12),
          TextFormField(controller: _weightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Berat Badan (kg)')),
          const SizedBox(height: 12),
          TextFormField(controller: _heightCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tinggi/Panjang Badan (cm)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _index,
            items: const [
              DropdownMenuItem(value: 'BB/U', child: Text('BB/U (Berat Badan menurut Umur)')),
              DropdownMenuItem(value: 'TB/U', child: Text('TB/U (Tinggi Badan menurut Umur)')),
              DropdownMenuItem(value: 'BB/TB', child: Text('BB/TB (Berat Badan menurut Tinggi Badan)')),
            ],
            onChanged: (v) => setState(() => _index = v!),
            decoration: const InputDecoration(labelText: 'Indeks Antropometri'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _calc, child: const Text('Hitung Z-Score')),
          const SizedBox(height: 16),
          if (_z != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Z-Score: $_z', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Kategori: $_cat', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('Catatan: Perhitungan ini bersifat estimasi untuk kemudahan penggunaan. Untuk penilaian resmi menggunakan tabel WHO 2006 lengkap.'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
