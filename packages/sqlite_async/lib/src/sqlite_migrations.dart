import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'sqlite_connection.dart';

/// Migrations to initialize and update a database.
class SqliteMigrations {
  /// Name of table used to store migrations.
  ///
  /// Defaults to "_migrations".
  String migrationTable;

  /// List of migrations to execute, in order. Use [add] to add new migrations.
  List<SqliteMigration> migrations = [];

  /// Optional: Migration to create database from scratch.
  ///
  /// Use this to speed up initialization for a fresh database.
  ///
  /// This must be supplied _in addition to_ migrations for the same version,
  /// and should produce the same state for the database.
  SqliteMigration? createDatabase;

  SqliteMigrations({this.migrationTable = "_migrations"});

  add(SqliteMigration migration) {
    assert(
        migrations.isEmpty || migrations.last.toVersion < migration.toVersion);

    final down = migration.downMigration;
    if (down != null) {
      if (migrations.isEmpty) {
        if (down.toVersion != 0) {
          throw MigrationError(
              'Down migration for first migration must have toVersion = 0');
        }
      } else {
        if (down.toVersion > migrations.last.toVersion) {
          throw MigrationError(
              'Down migration for ${migration.toVersion} must have a toVersion <= ${migrations.last.toVersion}');
        }
      }
    }

    migrations.add(migration);
  }

  /// The current version as specified by the migrations.
  get version {
    return migrations.isEmpty ? 0 : migrations.last.toVersion;
  }

  /// Get the last applied migration version in the database.
  Future<int> getCurrentVersion(SqliteWriteContext db) async {
    try {
      final currentVersionRow = await db.getOptional(
          'SELECT ifnull(max(id), 0) as version FROM $migrationTable');
      int currentVersion =
          currentVersionRow == null ? 0 : currentVersionRow['version'];
      return currentVersion;
    } on SqliteException catch (e) {
      if (e.message.contains('no such table')) {
        return 0;
      }
      rethrow;
    }
  }

  _validateCreateDatabase() {
    if (createDatabase != null) {
      if (createDatabase!.downMigration != null) {
        throw MigrationError("createDatabase may not contain down migrations");
      }

      var hasMatchingVersion = migrations
          .where((element) => element.toVersion == createDatabase!.toVersion)
          .isNotEmpty;
      if (!hasMatchingVersion) {
        throw MigrationError(
            "createDatabase.version (${createDatabase!.toVersion} must match a migration version");
      }
    }
  }

  /// Initialize or update the database.
  ///
  /// Throws MigrationError if the database cannot be migrated.
  Future<void> migrate(SqliteConnection db) async {
    _validateCreateDatabase();

    await db.writeTransaction((tx) async {
      await tx.execute(
          'CREATE TABLE IF NOT EXISTS $migrationTable(id INTEGER PRIMARY KEY, down_migrations TEXT)');

      int currentVersion = await getCurrentVersion(tx);

      if (currentVersion == version) {
        return;
      }

      // Handle down migrations
      while (currentVersion > version) {
        final migrationRow = await tx.getOptional(
            'SELECT id, down_migrations FROM $migrationTable WHERE id > ? ORDER BY id DESC LIMIT 1',
            [version]);

        if (migrationRow == null || migrationRow['down_migrations'] == null) {
          throw MigrationError(
              'No down migration found from $currentVersion to $version');
        }

        final migrations = jsonDecode(migrationRow['down_migrations']);
        for (var migration in migrations) {
          await tx.execute(migration['sql'], migration['params']);
        }

        // Refresh version
        int prevVersion = currentVersion;
        currentVersion = await getCurrentVersion(tx);
        if (prevVersion == currentVersion) {
          throw MigrationError(
              'Database down from version $currentVersion to $version failed - version not updated after dow migration');
        }
      }

      // Clean setup
      if (currentVersion == 0 && createDatabase != null) {
        await createDatabase!.fn(tx);

        // Still need to persist the migrations
        for (var migration in migrations) {
          if (migration.toVersion <= createDatabase!.toVersion) {
            await _persistMigration(migration, tx, migrationTable);
          }
        }

        currentVersion = await getCurrentVersion(tx);
      }

      // Up migrations
      for (var migration in migrations) {
        if (migration.toVersion > currentVersion) {
          await migration.fn(tx);
          await _persistMigration(migration, tx, migrationTable);
        }
      }
    });
  }
}

Future<void> _persistMigration(SqliteMigration migration, SqliteWriteContext db,
    String migrationTable) async {
  final down = migration.downMigration;
  if (down != null) {
    List<_SqliteMigrationStatement> statements = down._statements;
    statements.insert(
        0,
        _SqliteMigrationStatement(
            'DELETE FROM $migrationTable WHERE id > ${down.toVersion}'));

    var json = jsonEncode(statements);
    await db.execute(
        'INSERT INTO $migrationTable(id, down_migrations) VALUES(?, ?)',
        [migration.toVersion, json]);
  } else {
    await db.execute(
        'INSERT INTO $migrationTable(id, down_migrations) VALUES(?, ?)',
        [migration.toVersion, null]);
  }
}

class MigrationError extends Error {
  final String message;

  MigrationError(this.message);

  @override
  String toString() {
    return 'MigrationError: $message';
  }
}

typedef SqliteMigrationFunction = FutureOr<void> Function(
    SqliteWriteContext tx);

/// A migration for a single database version.
class SqliteMigration {
  /// Function to execute for the migration.
  final SqliteMigrationFunction fn;

  /// Database version that this migration upgrades to.
  final int toVersion;

  /// Optional: Add a down migration to allow this migration to be reverted
  /// if the user installs an older version.
  ///
  /// If the user will never downgrade the application/database version, this is
  /// not required.
  ///
  /// Limited downgrade support can be added by only providing downMigrations
  /// for the last migration(s).
  SqliteDownMigration? downMigration;

  SqliteMigration(this.toVersion, this.fn, {this.downMigration});
}

class _SqliteMigrationStatement {
  final String sql;
  final List<Object?> params;

  _SqliteMigrationStatement(this.sql, [this.params = const []]);

  Map<String, dynamic> toJson() {
    return {'sql': sql, 'params': params};
  }
}

/// Set of down migration statements, persisted in the database.
///
/// Since this will execute in an older application version, only static
/// SQL statements are supported.
class SqliteDownMigration {
  /// The database version after this downgrade.
  final int toVersion;
  final List<_SqliteMigrationStatement> _statements = [];

  SqliteDownMigration({required this.toVersion});

  /// Add an statement to execute to downgrade the database version.
  add(String sql, [List<Object?>? params]) {
    _statements.add(_SqliteMigrationStatement(sql, params ?? []));
  }
}
