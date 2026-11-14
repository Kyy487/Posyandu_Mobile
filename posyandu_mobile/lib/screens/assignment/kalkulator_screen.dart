import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class KalkulatorScreen extends StatefulWidget {
  const KalkulatorScreen({super.key});

  @override
  State<KalkulatorScreen> createState() => _KalkulatorScreenState();
}

class _KalkulatorScreenState extends State<KalkulatorScreen> {
  String _display = '0';
  String _history = '';
  double? _stored;
  String? _operator;
  bool _resetOnNextInput = false;

  double get _nilaiSekarang => double.tryParse(_display) ?? 0;

  String _format(double value) {
    if (value.isNaN || value.isInfinite) return 'Error';
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(8)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  double? _hitung(double a, double b, String operator) {
    switch (operator) {
      case '+':
        return a + b;
      case '−':
        return a - b;
      case '×':
        return a * b;
      case '÷':
        if (b == 0) return null;
        return a / b;
    }
    return null;
  }

  void _masukkanAngka(String angka) {
    setState(() {
      if (_resetOnNextInput || _display == 'Error') {
        _display = angka;
        _resetOnNextInput = false;
        _history = '';
      } else if (_display == '0') {
        _display = angka;
      } else if (_display.length < 18) {
        _display += angka;
      }
    });
  }

  void _masukkanDesimal() {
    setState(() {
      if (_resetOnNextInput || _display == 'Error') {
        _display = '0.';
        _resetOnNextInput = false;
        _history = '';
        return;
      }
      if (!_display.contains('.')) _display += '.';
    });
  }

  void _masukkanOperator(String operator) {
    setState(() {
      if (_display == 'Error') return;
      if (_operator != null && _stored != null && !_resetOnNextInput) {
        final hasil = _hitung(_stored!, _nilaiSekarang, _operator!);
        if (hasil == null) {
          _tampilkanError();
          return;
        }
        _display = _format(hasil);
        _stored = hasil;
      } else {
        _stored = _nilaiSekarang;
      }
      _operator = operator;
      _resetOnNextInput = true;
      _history = '${_format(_stored!)} $operator';
    });
  }

  void _samaDengan() {
    setState(() {
      if (_operator == null || _stored == null || _display == 'Error') return;
      final kanan = _nilaiSekarang;
      final hasil = _hitung(_stored!, kanan, _operator!);
      if (hasil == null) {
        _tampilkanError();
        return;
      }
      _history = '${_format(_stored!)} $_operator ${_format(kanan)} =';
      _display = _format(hasil);
      _stored = null;
      _operator = null;
      _resetOnNextInput = true;
    });
  }

  void _kuadrat() {
    setState(() {
      if (_display == 'Error') return;
      final nilai = _nilaiSekarang;
      _history = '${_format(nilai)}² =';
      _display = _format(nilai * nilai);
      _stored = null;
      _operator = null;
      _resetOnNextInput = true;
    });
  }

  void _akarKuadrat() {
    setState(() {
      if (_display == 'Error') return;
      final nilai = _nilaiSekarang;
      if (nilai < 0) {
        _history = '√${_format(nilai)}';
        _tampilkanError();
        return;
      }
      _history = '√${_format(nilai)} =';
      _display = _format(math.sqrt(nilai));
      _stored = null;
      _operator = null;
      _resetOnNextInput = true;
    });
  }

  void _hapus() {
    setState(() {
      if (_display == 'Error' || _resetOnNextInput) {
        _display = '0';
        _history = '';
        _resetOnNextInput = false;
        return;
      }
      _display = _display.length <= 1
          ? '0'
          : _display.substring(0, _display.length - 1);
      if (_display == '-') _display = '0';
    });
  }

  void _bersihkan() {
    setState(() {
      _display = '0';
      _history = '';
      _stored = null;
      _operator = null;
      _resetOnNextInput = false;
    });
  }

  void _tampilkanError() {
    _display = 'Error';
    _history = 'Operasi tidak valid';
    _stored = null;
    _operator = null;
    _resetOnNextInput = true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF12302F), Color(0xFF0E7C7B)],
              ),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.24),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calculate_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Kalkulator Sederhana',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    _history,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _display,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _tombol('C', aksi: true, onTap: _bersihkan),
                      _tombol('⌫', aksi: true, onTap: _hapus),
                      _tombol('x²', aksi: true, onTap: _kuadrat),
                      _tombol('√', aksi: true, onTap: _akarKuadrat),
                    ],
                  ),
                ),
                Expanded(child: _baris(['7', '8', '9'])),
                Expanded(child: _baris(['4', '5', '6'])),
                Expanded(child: _baris(['1', '2', '3'])),
                Expanded(
                  child: Row(
                    children: [
                      _tombol('0', onTap: () => _masukkanAngka('0')),
                      _tombol('.', onTap: _masukkanDesimal),
                      _tombol('=', samaDengan: true, onTap: _samaDengan),
                      _tombol(
                        '+',
                        operator: true,
                        onTap: () => _masukkanOperator('+'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Gunakan tombol C untuk hapus semua dan ⌫ untuk hapus satu karakter.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.9),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _baris(List<String> angka) {
    const operator = ['÷', '×', '−'];
    final index = switch (angka.first) {
      '7' => 0,
      '4' => 1,
      '1' => 2,
      _ => 0,
    };
    final op = operator[index];
    return Row(
      children: [
        for (final value in angka)
          _tombol(value, onTap: () => _masukkanAngka(value)),
        _tombol(op, operator: true, onTap: () => _masukkanOperator(op)),
      ],
    );
  }

  Widget _tombol(
    String label, {
    required VoidCallback onTap,
    bool operator = false,
    bool aksi = false,
    bool samaDengan = false,
  }) {
    final background = samaDengan
        ? AppTheme.brand
        : operator
        ? AppTheme.brand.withValues(alpha: 0.12)
        : aksi
        ? AppTheme.accent.withValues(alpha: 0.12)
        : Colors.white;
    final foreground = samaDengan
        ? Colors.white
        : operator
        ? AppTheme.brandDark
        : aksi
        ? AppTheme.accent
        : AppTheme.ink;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: samaDengan
                      ? Colors.transparent
                      : AppTheme.border.withValues(alpha: 0.8),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: label == '⌫' ? 22 : 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
