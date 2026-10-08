import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

class AppDatabase {
  final Database db;

  AppDatabase(this.db);

  static AppDatabase open(String dbDir) {
    final dbFile = File(p.join(dbDir, 'pixez_s.db'));
    if (!dbFile.parent.existsSync()) {
      dbFile.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(dbFile.path);
    final instance = AppDatabase(db);
    instance._initTables();
    return instance;
  }

  void _initTables() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        user_name TEXT,
        user_account TEXT,
        mail_address TEXT,
        access_token TEXT,
        refresh_token TEXT,
        expires_at INTEGER,
        is_active INTEGER DEFAULT 0,
        is_premium INTEGER DEFAULT 0,
        x_restrict INTEGER DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS archived_works (
        work_id TEXT PRIMARY KEY,
        work_type TEXT NOT NULL,
        title TEXT,
        user_id TEXT,
        user_name TEXT,
        create_date TEXT,
        tags_json TEXT,
        caption TEXT,
        raw_metadata TEXT,
        local_files_json TEXT,
        is_deleted_upstream INTEGER DEFAULT 0,
        archived_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_archived_user ON archived_works(user_id);
      CREATE INDEX IF NOT EXISTS idx_archived_type ON archived_works(work_type);
      CREATE INDEX IF NOT EXISTS idx_archived_at ON archived_works(archived_at DESC);
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS download_tasks (
        id TEXT PRIMARY KEY,
        work_id TEXT NOT NULL,
        work_type TEXT NOT NULL,
        title TEXT,
        target_dir TEXT,
        total_pages INTEGER DEFAULT 1,
        downloaded_pages INTEGER DEFAULT 0,
        status TEXT NOT NULL,
        error_msg TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON download_tasks(status);
      CREATE INDEX IF NOT EXISTS idx_tasks_work_id ON download_tasks(work_id);
    ''');
  }

  void close() {
    db.dispose();
  }
}
