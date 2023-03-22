import 'package:benchmarking/benchmarking.dart';
import 'package:collection/collection.dart';

import 'package:sqlite_async/sqlite_async.dart';

import '../test/util.dart';

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
  SqliteBenchmark('Write lock',
      (SqliteDatabase db, List<List<String>> parameters) async {
    for (var params in parameters) {
      await db.writeLock((tx) async {});
    }
  }, maxBatchSize: 5000),
  SqliteBenchmark('Read lock',
      (SqliteDatabase db, List<List<String>> parameters) async {
    for (var params in parameters) {
      await db.readLock((tx) async {});
    }
  }, maxBatchSize: 5000),
  SqliteBenchmark('Insert: Direct',
      (SqliteDatabase db, List<List<String>> parameters) async {
    for (var params in parameters) {
      await db.execute(
          'INSERT INTO customers(name, email) VALUES(?, ?)', params);
    }
  }, maxBatchSize: 500),
  SqliteBenchmark('Insert: writeTransaction',
      (SqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      for (var params in parameters) {
        await tx.execute(
            'INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }, maxBatchSize: 1000),
  SqliteBenchmark('Insert: writeTransaction no await',
      (SqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      for (var params in parameters) {
        tx.execute('INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }, maxBatchSize: 1000),
  SqliteBenchmark('Insert: computeWithDatabase',
      (SqliteDatabase db, List<List<String>> parameters) async {
    await db.computeWithDatabase((db) async {
      for (var params in parameters) {
        db.execute('INSERT INTO customers(name, email) VALUES(?, ?)', params);
      }
    });
  }),
  SqliteBenchmark('Insert: computeWithDatabase, prepared',
      (SqliteDatabase db, List<List<String>> parameters) async {
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
      (SqliteDatabase db, List<List<String>> parameters) async {
    await db.writeTransaction((tx) async {
      await tx.executeBatch(
          'INSERT INTO customers(name, email) VALUES(?, ?)', parameters);
    });
  }),
  SqliteBenchmark('Insert: computeWithDatabase, prepared x10',
      (SqliteDatabase db, List<List<String>> parameters) async {
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
  setupLogger();

  var parameters = List.generate(
      20000, (index) => ['Test user $index', 'user$index@example.org']);

  createTables(SqliteDatabase db) async {
    await db.writeTransaction((tx) async {
      await tx.execute(
          'CREATE TABLE IF NOT EXISTS customers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, email TEXT)');
      await tx.execute('DELETE FROM customers WHERE 1');
    });
    await db.execute('VACUUM');
    await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  final db = await setupDatabase(path: 'test-db/benchmark.db');
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
      await benchmark.fn(db, limitedParameters);
    }, teardown: () async {
      // This would make the benchmark fair, but only if each benchmark uses the
      // same batch size.
      await db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    });

    results.report(units: limitedParameters.length);
  }

  for (var entry in benchmarks) {
    await benchmark(entry);
  }
}
