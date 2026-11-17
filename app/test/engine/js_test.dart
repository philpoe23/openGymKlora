import 'package:flutter_test/flutter_test.dart';
import 'package:klora_app/engine/js.dart';

void main() {
  test('truthy follows JS', () {
    for (final v in [null, false, 0, 0.0, double.nan, '']) {
      expect(truthy(v), isFalse, reason: '$v');
    }
    for (final v in [true, 1, -1, '0', 'a', [], {}]) {
      expect(truthy(v), isTrue, reason: '$v');
    }
  });

  test('toNum / numOr / parseFloatJs', () {
    expect(toNum(null), 0);
    expect(toNum('2.5'), 2.5);
    expect(toNum(''), 0);
    expect(toNum('x').isNaN, isTrue);
    expect(numOr('abc', 7), 7);
    expect(numOr(0, 7), 7);
    expect(numOr('3', 7), 3);
    expect(parseFloatJs('12.5kg'), 12.5);
    expect(parseFloatJs('kg').isNaN, isTrue);
    expect(parseIntJs('08'), 8);
  });

  test('clone is deep', () {
    final a = <String, dynamic>{'x': [1, {'y': 2}]};
    final b = clone(a) as Map<String, dynamic>;
    ((b['x'] as List)[1] as Map)['y'] = 3;
    expect(((a['x'] as List)[1] as Map)['y'], 2);
  });

  test('fmtJsNum and mathRound', () {
    expect(fmtJsNum(5.0), '5');
    expect(fmtJsNum(2.50), '2.5');
    expect(mathRound(2.5), 3);
    expect(mathRound(-2.5), -2);
    expect(toFixedNum(1.005 * 100, 1), 100.5);
  });

  test('jsonEq treats 5 and 5.0 alike', () {
    expect(jsonEq({'a': [5.0]}, {'a': [5]}), isTrue);
    expect(jsonEq({'a': 1}, {'a': 2}), isFalse);
  });

  test('jsString / jsJoin follow String() and Array.join', () {
    expect(jsString(null), 'null');
    expect(jsString(5.0), '5');
    expect(jsString([1, null, 'a']), '1,,a');
    expect(jsString({'a': 1}), '[object Object]');
    expect(jsJoin(['a', null, 2.5], ' '), 'a  2.5');
  });

  test('jsSort is stable and cmpNum reads a numeric difference', () {
    final xs = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')];
    jsSort(xs, (a, b) => a.$1 - b.$1);
    expect(xs.map((x) => x.$2).join(), 'bdac');
    expect(cmpNum(-0.5), -1);
    expect(cmpNum(double.nan), 0);
  });

  test('jsFind is Array.find, also on a typed list', () {
    final typed = <Map<String, int>>[{'a': 1}, {'a': 2}];
    expect(jsFind(typed, (x) => x['a'] == 2), {'a': 2});
    expect(jsFind(typed, (x) => x['a'] == 3), isNull);
  });

  test('jsKeys orders integer keys first, like Object.keys', () {
    expect(jsKeys({'b': 1, '10': 1, '2.5': 1, '2': 1, 'a': 1}), ['2', '10', 'b', '2.5', 'a']);
  });
}
