import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:phone/core/protocol.dart';
import 'package:phone/models/text_delta.dart';
import 'package:phone/utils/constants.dart';

void main() {
  group('Protocol encoder', () {
    final protocol = Protocol();

    test('encode TextDelta to protocol JSON', () {
      const delta = TextDelta(
        op: DeltaOp.append,
        position: 0,
        deleteCount: 0,
        text: '你好',
        clipboardHint: false,
      );

      final result = jsonDecode(protocol.encode(delta, 42)) as Map<String, dynamic>;

      expect(result['t'], Constants.msgTextDelta);
      expect(result['s'], 42);
      expect(result['o'], 'A');
      expect(result['p'], 0);
      expect(result['n'], 0);
      expect(result['d'], '你好');
      expect(result['c'], false);
    });

    test('encode full sync JSON', () {
      final result =
          jsonDecode(protocol.encodeFullSync('完整文本', 7)) as Map<String, dynamic>;

      expect(result['t'], Constants.msgTextFullSync);
      expect(result['s'], 7);
      expect(result['d'], '完整文本');
    });

    test('encode heartbeat JSON', () {
      final result =
          jsonDecode(protocol.encodeHeartbeat(85, '搜狗输入法')) as Map<String, dynamic>;

      expect(result['t'], Constants.msgHeartbeat);
      expect(result['bat'], 85);
      expect(result['ime'], '搜狗输入法');
    });

    test('encode segment complete JSON', () {
      final result =
          jsonDecode(protocol.encodeSegmentComplete(50, 500)) as Map<String, dynamic>;

      expect(result['t'], Constants.msgSegmentComplete);
      expect(result['s'], 50);
      expect(result['total_chars'], 500);
    });

    test('encode special key JSON', () {
      final result =
          jsonDecode(protocol.encodeSpecialKey(51, 'Ctrl+V')) as Map<String, dynamic>;

      expect(result['t'], Constants.msgSpecialKey);
      expect(result['s'], 51);
      expect(result['k'], 'Ctrl+V');
    });
  });
}
