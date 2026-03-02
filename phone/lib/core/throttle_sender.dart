import 'dart:async';

import '../models/text_delta.dart';
import '../utils/constants.dart';
import 'diff_engine.dart';

typedef DeltaSendCallback = void Function(TextDelta delta);

class ThrottledDiffSender {
  ThrottledDiffSender({
    required DeltaSendCallback onSend,
    Duration? throttleWindow,
  })  : _onSend = onSend,
        _throttleWindow = throttleWindow ?? const Duration(milliseconds: Constants.throttleWindowMs);

  final DeltaSendCallback _onSend;
  final Duration _throttleWindow;
  final DiffEngine _diffEngine = DiffEngine();

  Timer? _windowTimer;
  String? _bufferedText;
  String _lastSentText = '';

  void onTextChanged(String newText) {
    if (_windowTimer == null) {
      _emitText(newText);
      _startWindow();
      return;
    }

    _bufferedText = newText;
  }

  void reset() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _bufferedText = null;
    _lastSentText = '';
    _diffEngine.reset();
  }

  void _startWindow() {
    _windowTimer?.cancel();
    _windowTimer = Timer(_throttleWindow, _onWindowElapsed);
  }

  void _onWindowElapsed() {
    _windowTimer = null;

    final pendingText = _bufferedText;
    _bufferedText = null;

    if (pendingText == null || pendingText == _lastSentText) {
      return;
    }

    _emitText(pendingText);
    _startWindow();
  }

  void _emitText(String text) {
    final delta = _diffEngine.computeDelta(text);
    _lastSentText = text;
    if (delta.op != DeltaOp.noChange) {
      _onSend(delta);
    }
  }
}
