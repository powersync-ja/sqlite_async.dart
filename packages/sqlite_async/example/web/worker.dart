import 'package:sqlite_async/sqlite3_web.dart';
import 'package:sqlite_async/sqlite3_web_worker.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: AsyncSqliteController());
}
