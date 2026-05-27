@TestOn('browser')
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';

import '../utils/test_utils_impl.dart';

const _isDart2Wasm = bool.fromEnvironment('dart.tool.dart2wasm');
final testUtils = TestUtils();

void main() {
  group('Web database tests', () {
    late String path;

    setUp(() async {
      path = testUtils.dbPath();
      await testUtils.cleanDb(path: path);
    });

    tearDown(() async {
      await testUtils.cleanDb(path: path);
    });

    test('can bind all types', () async {
      final db = await testUtils.setupDatabase(path: path);
      addTearDown(db.close);

      Future<void> assertTypeOf(Object? value, String typeName) async {
        final row = await db.get('SELECT typeof(?)', [value]);
        expect(row.values[0], typeName);
      }

      await assertTypeOf(null, 'null');
      await assertTypeOf('hello web', 'text');
      await assertTypeOf(Uint8List(12), 'blob');
      await assertTypeOf(2, 'integer');
      await assertTypeOf(BigInt.two, 'integer');
      await assertTypeOf(BigInt.one << 62, 'integer');
      await assertTypeOf(pi, 'real');
    });

    test('large integers are read as bigints on JS', () async {
      final db = await testUtils.setupDatabase(path: path);
      addTearDown(db.close);

      final value = (await db.get('SELECT 1 << 62')).values[0];
      if (_isDart2Wasm) {
        // We have 64bit ints on dart2wasm, which should be used here.
        expect(value, isA<int>());
        expect(value, 1 << 62);
      } else {
        expect(value, isA<BigInt>());
        expect(value, BigInt.parse('4611686018427387904'));
      }
    });
  });
}
