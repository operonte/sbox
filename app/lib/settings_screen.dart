import 'package:flutter/material.dart';

import 'settings.dart';
import 'theme.dart';

/// Pantalla de Configuración: tamaño de texto (1×…4×) y nombre del dispositivo.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: Settings.instance.deviceName.value);

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: cCard.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('TAMAÑO DEL TEXTO'),
                        const SizedBox(height: 10),
                        _textSizeSelector(),
                        const SizedBox(height: 24),
                        const _Label('NOMBRE DEL DISPOSITIVO'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameCtrl,
                          onChanged: (v) =>
                              Settings.instance.setDeviceName(v.trim()),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Mi PC',
                            hintStyle: const TextStyle(color: cDim),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.25),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: cBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: cAccent.withValues(alpha: 0.6)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Con este nombre te verá el otro dispositivo al emparejar.',
                          style: TextStyle(color: cDim, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: cDim, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text(
            'Configuración',
            style: TextStyle(
              fontFamily: fontMono,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _textSizeSelector() {
    const options = <String, double>{'1×': 1.0, '2×': 2.0, '3×': 3.0, '4×': 4.0};
    return ValueListenableBuilder<double>(
      valueListenable: Settings.instance.textScale,
      builder: (context, current, _) {
        final entries = options.entries.toList();
        return Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Expanded(
                child: _sizeChip(
                  entries[i].key,
                  entries[i].value,
                  current == entries[i].value,
                ),
              ),
              if (i < entries.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _sizeChip(String label, double value, bool selected) {
    return GestureDetector(
      onTap: () => Settings.instance.setTextScale(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cAccent.withValues(alpha: selected ? 0.18 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cAccent.withValues(alpha: selected ? 0.6 : 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: fontMono,
            fontWeight: FontWeight.w700,
            color: selected ? cAccent : cDim,
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: fontMono,
        color: cDim,
        fontSize: 11,
        letterSpacing: 2,
      ),
    );
  }
}
