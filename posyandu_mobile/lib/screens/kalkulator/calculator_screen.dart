import 'package:flutter/material.dart';

import 'zscore_calculator_screen.dart';

class CalculatorScreen extends StatelessWidget {
  const CalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalkulator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Kalkulator Biasa'),
              subtitle: const Text('Penjumlahan, pengurangan, perkalian, pembagian'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const _BasicCalculatorScreen()));
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Kalkulator Z-Score WHO 2006'),
              subtitle: const Text('Hitung status gizi anak'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ZScoreCalculatorScreen()));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BasicCalculatorScreen extends StatefulWidget {
  const _BasicCalculatorScreen();

  @override
  State<_BasicCalculatorScreen> createState() => _BasicCalculatorScreenState();
}

class _BasicCalculatorScreenState extends State<_BasicCalculatorScreen> {
  String _display = '0';
  String _prev = '';
  String _op = '';
  bool _shouldReset = false;
  String _expression = '';

  String _fmt(num n) {
    if (n.isNaN || n.isInfinite) return 'Error';
    if (n % 1 == 0) return n.toInt().toString();
    return n.toStringAsFixed(10).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _onPressed(String value) {
    setState(() {
      if (value == 'C') {
        _display = '0';
        _prev = '';
        _op = '';
        _shouldReset = false;
        _expression = '';
        return;
      }
      if (value == '=') {
        if (_op.isNotEmpty && _prev.isNotEmpty) {
          final a = double.tryParse(_prev) ?? 0;
          final b = double.tryParse(_display) ?? 0;
          double res = 0;
          if (_op == '+') res = a + b;
          if (_op == '-') res = a - b;
          if (_op == '×') res = a * b;
          if (_op == '÷') res = b == 0 ? 0 : a / b;
          _expression = '$_prev $_op $_display =';
          _display = _fmt(res);
          _prev = '';
          _op = '';
          _shouldReset = true;
        }
        return;
      }
      if (['+', '-', '×', '÷'].contains(value)) {
        if (_op.isNotEmpty && _prev.isNotEmpty && !_shouldReset) {
          final a = double.tryParse(_prev) ?? 0;
          final b = double.tryParse(_display) ?? 0;
          double res = 0;
          if (_op == '+') res = a + b;
          if (_op == '-') res = a - b;
          if (_op == '×') res = a * b;
          if (_op == '÷') res = b == 0 ? 0 : a / b;
          _prev = _fmt(res);
          _expression = '$_prev $value';
        } else {
          _prev = _display;
          _expression = '$_display $value';
        }
        _op = value;
        _shouldReset = true;
        return;
      }
      if (_shouldReset && _op.isEmpty) {
        _display = value == '0' ? '0' : value;
        _shouldReset = false;
        _expression = '';
      } else if (_shouldReset) {
        _display = value == '0' ? '0' : value;
        _shouldReset = false;
      } else {
        if (_display == '0' && value != '.') {
          _display = value;
        } else {
          _display += value;
        }
      }
    });
  }

  Widget _btn(String v, {Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? Colors.grey.shade200,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.all(20),
          ),
          onPressed: () => _onPressed(v),
          child: Text(v, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalkulator')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_expression, style: const TextStyle(fontSize: 24, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text(_display, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          Column(
            children: [
              Row(children: [_btn('7'), _btn('8'), _btn('9'), _btn('÷', color: Colors.orange.shade200)]),
              Row(children: [_btn('4'), _btn('5'), _btn('6'), _btn('×', color: Colors.orange.shade200)]),
              Row(children: [_btn('1'), _btn('2'), _btn('3'), _btn('-', color: Colors.orange.shade200)]),
              Row(children: [_btn('0'), _btn('C'), _btn('='), _btn('+', color: Colors.orange.shade200)]),
            ],
          ),
        ],
      ),
    );
  }
}
