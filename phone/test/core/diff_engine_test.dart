import 'package:flutter_test/flutter_test.dart';
import 'package:phone/core/diff_engine.dart';
import 'package:phone/models/text_delta.dart';

void main() {
  group('DiffEngine', () {
    test('边界：空到非空 -> APPEND', () {
      final engine = DiffEngine();

      final delta = engine.computeDelta('你好');

      expect(delta.op, DeltaOp.append);
      expect(delta.position, 0);
      expect(delta.text, '你好');
      expect(delta.clipboardHint, false);
    });

    test('边界：非空到空 -> DELETE all', () {
      final engine = DiffEngine();
      engine.computeDelta('你好');

      final delta = engine.computeDelta('');

      expect(delta.op, DeltaOp.delete);
      expect(delta.position, 0);
      expect(delta.deleteCount, 2);
      expect(delta.text, '');
    });

    test('边界：相同文本 -> NO_CHANGE', () {
      final engine = DiffEngine();
      engine.computeDelta('abc');

      final delta = engine.computeDelta('abc');

      expect(delta.op, DeltaOp.noChange);
    });

    test('Scenario A: 拼音逐字输入 你好世界', () {
      final engine = DiffEngine();

      final d1 = engine.computeDelta('你');
      final d2 = engine.computeDelta('你好');
      final d3 = engine.computeDelta('你好世');
      final d4 = engine.computeDelta('你好世界');

      expect(d1.op, DeltaOp.append);
      expect(d2.op, DeltaOp.append);
      expect(d3.op, DeltaOp.append);
      expect(d4.op, DeltaOp.append);
      expect(d4.text, '界');
    });

    test('Scenario B: 语音整句输入(15+) -> clipboardHint=true', () {
      final engine = DiffEngine();

      final delta = engine.computeDelta('今天天气真不错我们去公园散步吧');

      expect(delta.op, DeltaOp.append);
      expect(delta.clipboardHint, true);
    });

    test('Scenario C: 候选词替换 北京 -> 南京', () {
      final engine = DiffEngine();
      engine.computeDelta('我想去北京旅游');

      final delta = engine.computeDelta('我想去南京旅游');

      expect(delta.op, DeltaOp.replace);
      expect(delta.text, '南');
      expect(delta.deleteCount, 1);
    });

    test('Scenario D: 自动补全 苹 -> 苹果', () {
      final engine = DiffEngine();
      engine.computeDelta('苹');

      final delta = engine.computeDelta('苹果');

      expect(delta.op, DeltaOp.append);
      expect(delta.text, '果');
    });

    test('Scenario E1: 尾部删除', () {
      final engine = DiffEngine();
      engine.computeDelta('你好世界');

      final delta = engine.computeDelta('你好世');

      expect(delta.op, DeltaOp.delete);
      expect(delta.position, 3);
      expect(delta.deleteCount, 1);
    });

    test('Scenario E2: 中间删除', () {
      final engine = DiffEngine();
      engine.computeDelta('abcde');

      final delta = engine.computeDelta('abde');

      expect(delta.op, DeltaOp.delete);
      expect(delta.position, 2);
      expect(delta.deleteCount, 1);
    });

    test('Scenario F: 全选替换变化>60% -> FULL_SYNC', () {
      final engine = DiffEngine();
      engine.computeDelta('abcdefghij');

      final delta = engine.computeDelta('1234567890');

      expect(delta.op, DeltaOp.fullSync);
      expect(delta.text, '1234567890');
      expect(delta.clipboardHint, false);
    });

    test('Scenario G: 中间插入', () {
      final engine = DiffEngine();
      engine.computeDelta('abde');

      final delta = engine.computeDelta('abcde');

      expect(delta.op, DeltaOp.insert);
      expect(delta.position, 2);
      expect(delta.text, 'c');
    });

    test('边界：单字符替换', () {
      final engine = DiffEngine();
      engine.computeDelta('a');

      final delta = engine.computeDelta('b');

      expect(delta.op, DeltaOp.replace);
      expect(delta.position, 0);
      expect(delta.deleteCount, 1);
      expect(delta.text, 'b');
    });
  });
}
