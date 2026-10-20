import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class AppearanceColorDialog extends StatefulWidget {
  const AppearanceColorDialog({
    super.key,
    required this.initial,
    this.allowAlpha = false,
    this.onChanged,
  });
  final Color initial;
  final bool allowAlpha;
  final ValueChanged<Color>? onChanged;

  @override
  State<AppearanceColorDialog> createState() => _AppearanceColorDialogState();
}

class _AppearanceColorDialogState extends State<AppearanceColorDialog> {
  final _formKey = GlobalKey<FormState>();
  int _fieldRevision = 0;
  late double _alpha = widget.allowAlpha ? widget.initial.a : 1;
  late HSVColor _hsv = HSVColor.fromColor(widget.initial).withAlpha(_alpha);

  void _pickColor(Color color) {
    setState(() {
      _alpha = widget.allowAlpha ? color.a : 1;
      _hex =
          (color.toARGB32() & 0xffffff)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase();
      _fieldRevision++;
    });
    _preview();
  }

  void _preview() {
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(_hex)) {
      widget.onChanged?.call(
        Color(
          0xff000000 | int.parse(_hex, radix: 16),
        ).withValues(alpha: _alpha),
      );
    }
  }

  late String _hex =
      (widget.initial.toARGB32() & 0xffffff)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择颜色'),
    content: SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorPicker(
              key: const ValueKey('schedule-color-palette'),
              pickerColor: _hsv.toColor(),
              pickerHsvColor: _hsv,
              onColorChanged: _pickColor,
              onHsvColorChanged: (value) => _hsv = value.withAlpha(_alpha),
              enableAlpha: widget.allowAlpha,
              labelTypes: const [],
              displayThumbColor: true,
              portraitOnly: true,
              colorPickerWidth: 260,
              pickerAreaHeightPercent: .75,
              pickerAreaBorderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('schedule-color-hex-$_fieldRevision'),
              initialValue: _hex,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '色值',
                prefixText: '#',
                counterText: '',
              ),
              onChanged: (value) {
                setState(() {
                  _hex = value;
                  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
                    _hsv = HSVColor.fromColor(
                      Color(0xff000000 | int.parse(value, radix: 16)),
                    ).withAlpha(_alpha);
                  }
                });
                _preview();
              },
              validator:
                  (value) =>
                      RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value ?? '')
                          ? null
                          : '请输入6位色值',
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('应用')),
    ],
  );

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        Color(
          0xff000000 | int.parse(_hex, radix: 16),
        ).withValues(alpha: _alpha),
      );
    }
  }
}
