import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:benchmarking/benchmarking.dart';
import 'package:collection/collection.dart';
import 'package:sqlite_async/sqlite_async.dart';

import '../test/utils/test_utils_impl.dart';

final testUtils = TestUtils();

typedef BenchmarkFunction = Future<void> Function(
    SqliteDatabase, List<List<String>>);

class SqliteBenchmark {
  String name;
  int maxBatchSize;
  BenchmarkFunction fn;
  bool enabled;

  SqliteBenchmark(this.name, this.fn,
      {this.maxBatchSize = 100000, this.enabled = true});
}

List<SqliteBenchmark> benchmarks = [
  SqliteBenchmark('Insert: JSON1',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      for (var i = 0; i < parameters.length; i += 5000) {
        var sublist = parameters.sublist(i, min(parameters.length, i + 5000));
        await tx.execute(
            "WITH list AS (SELECT e.value ->> 0 as name, e.value ->> 1 as email FROM json_each(?) e)"
            'INSERT INTO customers(name, email) SELECT name, email FROM list',
            [jsonEncode(sublist)]);
      }
    });
  }, maxBatchSize: 20000),
  SqliteBenchmark('Read: JSON1',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.readTransaction((tx) async {
      for (var i = 0; i < parameters.length; i += 10000) {
        var sublist = List.generate(10000, (index) => index);
        await tx.getAll(
            'SELECT name, email FROM customers WHERE id IN (SELECT e.value FROM json_each(?) e)',
            [jsonEncode(sublist)]);
      }
    });
  }, maxBatchSize: 200000, enabled: false),
  SqliteBenchmark('writeLock in isolate',
      (SqliteDatabase db, List<List<String>> parameters) async {
    var factory = db.isolateConnectionFactory();
    var len = parameters.length;
    await Isolate.run(() async {
      final db = factory.open();
      for (var i = 0; i < len; i++) {
        await db.writeLock((tx) async {});
      }
      await db.close();
    });
  }, maxBatchSize: 10000, enabled: true),
  SqliteBenchmark('Write lock',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    for (var _ in parameters) {
      await db.writeLock((tx) async {});
    }
  }, maxBatchSize: 5000, enabled: false),
  SqliteBenchmark('Read lock',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    for (var _ in parameters) {
      await db.readLock((tx) async {});
    }
  }, maxBatchSize: 5000, enabled: false),
  SqliteBenchmark('Insert: Direct',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    for (var params in parameters) {
      await db.execute(
          'INSERT INTO customers(name, email) VALUES(?, ?)', params);
    }
  }, maxBatchSize: 500),
  SqliteBenchmark('Insert: writeTransaction',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      for (var params in parameters) {
        await tx.execute(
            'INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }, maxBatchSize: 1000),
  SqliteBenchmark('Insert: executeBatch in isolate',
      (SqliteDatabase db, List<List<String>> parameters) async {
    var factory = db.isolateConnectionFactory();
    await Isolate.run(() async {
      final db = factory.open();
      await db.executeBatch(
          'INSERT INTO customers(name, email) VALUES(?, ?)', parameters);
      await db.close();
    });
  }, maxBatchSize: 20000, enabled: true),
  SqliteBenchmark('Insert: direct write in isolate',
      (SqliteDatabase db, List<List<String>> parameters) async {
    var factory = db.isolateConnectionFactory();
    await Isolate.run(() async {
      final db = factory.open();
      for (var params in parameters) {
        await db.execute(
            'INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
      await db.close();
    });
  }, maxBatchSize: 2000),
  SqliteBenchmark('Insert: writeTransaction no await',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      for (var params in parameters) {
        tx.execute('INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }, maxBatchSize: 1000),
  SqliteBenchmark('Insert: computeWithDatabase',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.computeWithDatabase((db) async {
      for (var params in parameters) {
        db.execute('INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }),
  SqliteBenchmark('Insert: computeWithDatabase, prepared',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.computeWithDatabase((db) async {
      var stmt = db.prepare('INSERT INTO customers(name, email) VALUES(?, ?)');
      try {
        for (var params in parameters) {
          stmt.execute(params);
        }
      } finally {
        stmt.dispose();
      }
    });
  }),
  SqliteBenchmark('Insert: executeBatch',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      await tx.executeBatch(
          'INSERT INTO customers(name, email) VALUES(?, ?)', parameters);
    });
  }),
  SqliteBenchmark('Insert: computeWithDatabase, prepared x10',
      (AbstractSqliteDatabase db, List<List<String>> parameters) async {
    await db.computeWithDatabase((db) async {
      var stmt = db.prepare(
          'INSERT INTO customers(name, email) VALUES (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?), (?, ?)');
      try {
        for (var i = 0; i < parameters.length; i += 10) {
          var myParams =
              parameters.sublist(i, i + 10).flattened.toList(growable: false);
          stmt.execute(myParams);
        }
      } finally {
        stmt.dispose();
      }
    });
  }, enabled: false)
];

void main() async {
  var parameters = List.generate(
      20000, (index) => ['Test user $index', 'user$index@example.org']);

  createTables(AbstractSqliteDatabase db) async {
    await db.writeTransaction((tx) async {
      await tx.execute('DROP TABLE IF EXISTS customers');
      await tx.execute(
          'CREATE TABLE customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      // await tx.execute('CREATE INDEX customer_email ON customers(email, id)');
    });
    await db.execute('VACUUM');
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  final db = await testUtils.setupDatabase(path: 'test-db/benchmark.db');
  await db.execute('PRAGMA wal_autocheckpoint = 0');
  await createTables(db);

  benchmark(SqliteBenchmark benchmark) async {
    if (!benchmark.enabled) {
      return;
    }
    await createTables(db);

    var limitedParameters = parameters;
    if (limitedParameters.length > benchmark.maxBatchSize) {
      limitedParameters = limitedParameters.sublist(0, benchmark.maxBatchSize);
    }

    final rows1 = await db.execute('SELECT count(*) as count FROM customers');
    assert(rows1[0]['count'] == 0);
    final results = await asyncBenchmark(benchmark.name, () async {
      final stopwatch = Stopwatch()..start();
      await benchmark.fn(db, limitedParameters);
      final duration = stopwatch.elapsedMilliseconds;
      print("${benchmark.name} $duration");
    }, teardown: () async {
      // This would make the benchmark fair if it runs inside the benchmark,
      // but only if each benchmark uses the same batch size.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    });

    results.report(units: limitedParameters.length);
  }

  for (var entry in benchmarks) {
    await benchmark(entry);
  }

  await db.close();
}
