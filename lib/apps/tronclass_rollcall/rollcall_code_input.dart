import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Four native digit fields with continuous typing, paste and backspace.
class RollcallCodeInput extends StatefulWidget {
  const RollcallCodeInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  State<RollcallCodeInput> createState() => _RollcallCodeInputState();
}

class _RollcallCodeInputState extends State<RollcallCodeInput> {
  // An invisible prefix makes backspace in an empty slot observable on soft
  // keyboards too. It never enters the combined code or the request body.
  static const _prefix = '\u200b';
  final _fields = List.generate(4, (_) => TextEditingController());
  final _focus = List.generate(4, (_) => FocusNode());
  final _digits = List.filled(4, '');
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(covariant RollcallCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    if (_writing) return;
    final code = widget.controller.text;
    for (var i = 0; i < 4; i++) {
      _set(i, i < code.length ? code[i] : '');
    }
    if (code.isEmpty && _focus.any((node) => node.hasFocus)) _select(0);
  }

  String _digit(int index) => _digits[index];

  void _set(int index, String digit) {
    _digits[index] = digit;
    final text = '$_prefix$digit';
    _fields[index].value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _select(int index) {
    _focus[index].requestFocus();
    _fields[index].selection = TextSelection(
      baseOffset: 1,
      extentOffset: _fields[index].text.length,
    );
  }

  void _emit() {
    _writing = true;
    widget.controller.text = List.generate(4, _digit).join();
    _writing = false;
    widget.onChanged();
  }

  void _backspace(int index) {
    _set(index, '');
    if (index > 0) {
      _set(index - 1, '');
      _select(index - 1);
    }
    _emit();
  }

  void _changed(int index, String value) {
    if (value.isEmpty) {
      if (_digit(index).isEmpty) {
        _backspace(index);
      } else {
        _set(index, '');
        _emit();
      }
      return;
    }
    final digits = value.replaceAll(RegExp('[^0-9]'), '');
    final start = digits.length >= 4 ? 0 : index;
    if (digits.isEmpty) {
      _set(index, '');
    } else {
      final count = digits.length.clamp(0, 4 - start);
      for (var i = 0; i < count; i++) {
        _set(start + i, digits[i]);
      }
      _select((start + count).clamp(0, 3));
    }
    _emit();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    for (final controller in _fields) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('四位签到码'),
      const SizedBox(height: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) {
                    if (widget.enabled &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.backspace &&
                        _digit(i).isEmpty) {
                      _backspace(i);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Semantics(
                    label: '签到码第${i + 1}位',
                    child: TextField(
                      controller: _fields[i],
                      focusNode: _focus[i],
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      textInputAction:
                          i == 3 ? TextInputAction.done : TextInputAction.next,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9$_prefix]'),
                        ),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 8,
                        ),
                      ),
                      onTap: () => _select(i),
                      onChanged: (value) => _changed(i, value),
                      onSubmitted: (_) {
                        if (i < 3) {
                          _select(i + 1);
                        } else {
                          widget.onSubmitted();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
