import 'dart:convert';

import '../models/text_delta.dart';
import '../utils/constants.dart';

class Protocol {
  String encode(TextDelta delta, int seq) {
    final payload = <String, dynamic>{
      't': Constants.msgTextDelta,
      's': seq,
      'o': _opCode(delta.op),
      'p': delta.position,
      'n': delta.deleteCount,
      'd': delta.text,
      'c': delta.clipboardHint,
    };
    return jsonEncode(payload);
  }

  String encodeFullSync(String fullText, int seq) {
    final payload = <String, dynamic>{
      't': Constants.msgTextFullSync,
      's': seq,
      'd': fullText,
    };
    return jsonEncode(payload);
  }

  String encodeHeartbeat(int batteryPercent, String imeName) {
    final payload = <String, dynamic>{
      't': Constants.msgHeartbeat,
      'bat': batteryPercent,
      'ime': imeName,
    };
    return jsonEncode(payload);
  }

  String encodeSegmentComplete(int seq, int totalChars) {
    final payload = <String, dynamic>{
      't': Constants.msgSegmentComplete,
      's': seq,
      'total_chars': totalChars,
    };
    return jsonEncode(payload);
  }

  String encodeSpecialKey(int seq, String keyName) {
    final payload = <String, dynamic>{
      't': Constants.msgSpecialKey,
      's': seq,
      'k': keyName,
    };
    return jsonEncode(payload);
  }

  String _opCode(DeltaOp op) {
    switch (op) {
      case DeltaOp.append:
        return 'A';
      case DeltaOp.insert:
        return 'I';
      case DeltaOp.delete:
        return 'D';
      case DeltaOp.replace:
        return 'R';
      case DeltaOp.fullSync:
      case DeltaOp.noChange:
        return 'A';
    }
  }
}
