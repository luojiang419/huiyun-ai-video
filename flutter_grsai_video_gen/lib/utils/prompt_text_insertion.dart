import 'package:flutter/services.dart';

TextEditingValue insertTextAtSelection({
  required TextEditingValue value,
  required String insertion,
}) {
  final text = value.text;
  final selection = value.selection;
  final hasValidSelection =
      selection.isValid &&
      selection.start <= text.length &&
      selection.end <= text.length;
  final start = hasValidSelection ? selection.start : text.length;
  final end = hasValidSelection ? selection.end : text.length;
  final nextText = text.replaceRange(start, end, insertion);
  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: start + insertion.length),
  );
}
