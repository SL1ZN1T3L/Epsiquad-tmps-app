import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../providers/app_provider.dart';
import '../services/secure_store.dart';
import '../theme.dart';
import '../widgets/brand.dart';

class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.value,
    required this.onDigit,
    required this.onErase,
    this.onBiometric,
    this.busy = false,
  });

  final String value;
  final ValueChanged<String> onDigit;
  final VoidCallback onErase;
  final VoidCallback? onBiometric;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(SecureStore.pinLength, (i) {
            final filled = i < value.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 9),
              width: filled ? 15 : 13,
              height: filled ? 15 : 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? TmpsColors.accent : Colors.transparent,
                border: Border.all(
                  color: filled ? TmpsColors.accent : TmpsColors.border,
                  width: 1.6,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 34),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _Key(label: d, onTap: busy ? null : () => onDigit(d))],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            onBiometric == null
                ? const _Key(label: '')
                : _Key(icon: Ico.fingerprint, onTap: busy ? null : onBiometric),
            _Key(label: '0', onTap: busy ? null : () => onDigit('0')),
            _Key(
              icon: Ico.x,
              onTap: busy || value.isEmpty ? null : onErase,
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.onTap});

  final String? label;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = label != null && label!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: SizedBox(
        width: 72,
        height: 62,
        child: empty
            ? const SizedBox.shrink()
            : Material(
                color: TmpsColors.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: onTap == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onTap!();
                        },
                  child: Center(
                    child: icon != null
                        ? TmpsIcon(icon!, size: 23,
                            color: onTap == null ? TmpsColors.faint : TmpsColors.text)
                        : Text(
                            label!,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                          ),
                  ),
                ),
              ),
      ),
    );
  }
}

enum PinMode { unlock, create }

class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.mode});

  final PinMode mode;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _value = '';
  String? _first;
  String? _error;
  bool _busy = false;

  bool get _confirming => _first != null;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinMode.unlock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final app = context.read<AppProvider>();
        if (app.biometricEnabled && app.biometricAvailable) _biometric();
      });
    }
  }

  Future<void> _biometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final error = await context.read<AppProvider>().unlockWithBiometrics();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error != null) _error = error;
    });
  }

  void _digit(String d) {
    if (_value.length >= SecureStore.pinLength) return;
    setState(() {
      _value += d;
      _error = null;
    });
    if (_value.length == SecureStore.pinLength) _submit();
  }

  void _erase() => setState(() {
        _value = _value.substring(0, _value.length - 1);
        _error = null;
      });

  Future<void> _submit() async {
    final app = context.read<AppProvider>();
    final entered = _value;
    setState(() => _busy = true);

    if (widget.mode == PinMode.create) {
      if (!_confirming) {
        setState(() {
          _first = entered;
          _value = '';
          _busy = false;
        });
        return;
      }
      if (_first != entered) {
        HapticFeedback.heavyImpact();
        setState(() {
          _first = null;
          _value = '';
          _busy = false;
          _error = 'Пин-коды не совпали, попробуйте ещё раз';
        });
        return;
      }
      final error = await app.definePin(entered);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _value = '';
        _first = null;
        _error = error;
      });
      return;
    }

    final error = await app.unlockWithPin(entered);
    if (!mounted) return;
    if (error != null) HapticFeedback.heavyImpact();
    setState(() {
      _busy = false;
      _value = '';
      _error = error;
    });
  }

  String get _title {
    if (widget.mode == PinMode.unlock) return 'Введите пин-код';
    return _confirming ? 'Повторите пин-код' : 'Придумайте пин-код';
  }

  String get _subtitle {
    if (widget.mode == PinMode.unlock) return 'Он защищает вход в ваши хранилища';
    return _confirming
        ? 'Ещё раз, чтобы не ошибиться'
        : 'Четыре цифры. Понадобится при каждом запуске';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final biometric = widget.mode == PinMode.unlock &&
        app.biometricEnabled &&
        app.biometricAvailable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const BrandMark(size: 54, withText: false),
              const SizedBox(height: 22),
              Text(
                _title,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? _subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _error == null ? TmpsColors.muted : TmpsColors.danger,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              PinPad(
                value: _value,
                busy: _busy,
                onDigit: _digit,
                onErase: _erase,
                onBiometric: biometric ? _biometric : null,
              ),
              const Spacer(flex: 2),
              if (widget.mode == PinMode.unlock)
                TextButton(
                  onPressed: _busy ? null : () => context.read<AppProvider>().signOut(),
                  child: const Text('Войти в другой аккаунт'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> askPin(BuildContext context, String title) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: TmpsColors.bg2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheet) => _PinSheet(title: title),
  );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title});

  final String title;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  String _value = '';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 22),
            PinPad(
              value: _value,
              onDigit: (d) {
                if (_value.length >= SecureStore.pinLength) return;
                setState(() => _value += d);
                if (_value.length == SecureStore.pinLength) {
                  Navigator.of(context).pop(_value);
                }
              },
              onErase: () => setState(() => _value = _value.substring(0, _value.length - 1)),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }
}
