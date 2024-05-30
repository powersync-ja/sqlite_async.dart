import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/src/web/database/connection/drift_sqlite_connection.dart';

void setupCommonWorkerDB(CommonDatabase database) {
  /// Exposes autocommit via a query function
  database.createFunction(
      functionName: sqliteAsyncAutoCommitCommand,
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        return database.autocommit;
      });
}
