import '../models/text_delta.dart';

class DiffEngine {
  String _previousText = '';

  TextDelta computeDelta(String newText) {
    final oldText = _previousText;
    _previousText = newText;

    if (oldText.isEmpty && newText.isEmpty) {
      return TextDelta.noChange;
    }

    if (oldText.isEmpty && newText.isNotEmpty) {
      return TextDelta(
        op: DeltaOp.append,
        position: 0,
        text: newText,
        clipboardHint: newText.length > 10,
      );
    }

    if (newText.isEmpty && oldText.isNotEmpty) {
      return TextDelta(
        op: DeltaOp.delete,
        position: 0,
        deleteCount: oldText.length,
      );
    }

    int prefixLen = 0;
    final minLen = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefixLen < minLen && oldText[prefixLen] == newText[prefixLen]) {
      prefixLen++;
    }

    if (prefixLen == oldText.length && prefixLen == newText.length) {
      return TextDelta.noChange;
    }

    int suffixLen = 0;
    while (
        suffixLen < (minLen - prefixLen) &&
        oldText[oldText.length - 1 - suffixLen] == newText[newText.length - 1 - suffixLen]) {
      suffixLen++;
    }

    final deletedLen = oldText.length - prefixLen - suffixLen;
    final insertedText = newText.substring(prefixLen, newText.length - suffixLen);

    if (oldText.length > 5 && deletedLen > oldText.length * 0.6) {
      return TextDelta(
        op: DeltaOp.fullSync,
        text: newText,
        clipboardHint: newText.length > 10,
      );
    }

    if (deletedLen == 0 && insertedText.isNotEmpty) {
      final isAppend = prefixLen == oldText.length;
      return TextDelta(
        op: isAppend ? DeltaOp.append : DeltaOp.insert,
        position: prefixLen,
        text: insertedText,
        clipboardHint: insertedText.length > 10,
      );
    }

    if (deletedLen > 0 && insertedText.isEmpty) {
      return TextDelta(
        op: DeltaOp.delete,
        position: prefixLen,
        deleteCount: deletedLen,
      );
    }

    return TextDelta(
      op: DeltaOp.replace,
      position: prefixLen,
      deleteCount: deletedLen,
      text: insertedText,
      clipboardHint: insertedText.length > 10,
    );
  }

  void reset() {
    _previousText = '';
  }
}
