import 'package:sqlite3/sqlite3.dart';

class StoredTask {
  final String id;
  final String workId;
  final String workType;
  final String title;
  final String targetDir;
  final int totalPages;
  final int downloadedPages;
  final String status; // 'pending' | 'running' | 'completed' | 'failed' | 'paused'
  final String? errorMsg;
  final int createdAt;
  final int updatedAt;

  StoredTask({
    required this.id,
    required this.workId,
    required this.workType,
    required this.title,
    required this.targetDir,
    required this.totalPages,
    required this.downloadedPages,
    required this.status,
    this.errorMsg,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StoredTask.fromRow(Row row) {
    return StoredTask(
      id: (row['id'] ?? '').toString(),
      workId: (row['work_id'] ?? '').toString(),
      workType: (row['work_type'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      targetDir: (row['target_dir'] ?? '').toString(),
      totalPages: (row['total_pages'] as int? ?? 1),
      downloadedPages: (row['downloaded_pages'] as int? ?? 0),
      status: (row['status'] ?? 'pending').toString(),
      errorMsg: row['error_msg']?.toString(),
      createdAt: (row['created_at'] as int? ?? 0),
      updatedAt: (row['updated_at'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'work_id': workId,
    'work_type': workType,
    'title': title,
    'target_dir': targetDir,
    'total_pages': totalPages,
    'downloaded_pages': downloadedPages,
    'status': status,
    'error_msg': errorMsg,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class TaskDao {
  final Database db;

  TaskDao(this.db);

  void insert(StoredTask task) {
    final stmt = db.prepare('''
      INSERT INTO download_tasks (
        id, work_id, work_type, title, target_dir,
        total_pages, downloaded_pages, status, error_msg, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        downloaded_pages = excluded.downloaded_pages,
        status = excluded.status,
        error_msg = excluded.error_msg,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      task.id,
      task.workId,
      task.workType,
      task.title,
      task.targetDir,
      task.totalPages,
      task.downloadedPages,
      task.status,
      task.errorMsg,
      task.createdAt,
      task.updatedAt,
    ]);
    stmt.dispose();
  }

  void updateProgress(String id, int downloadedPages, int totalPages, String status, {String? errorMsg}) {
    final stmt = db.prepare('''
      UPDATE download_tasks SET
        downloaded_pages = ?,
        total_pages = ?,
        status = ?,
        error_msg = ?,
        updated_at = ?
      WHERE id = ?;
    ''');
    stmt.execute([
      downloadedPages,
      totalPages,
      status,
      errorMsg,
      DateTime.now().millisecondsSinceEpoch,
      id,
    ]);
    stmt.dispose();
  }

  StoredTask? findById(String id) {
    final stmt = db.prepare('SELECT * FROM download_tasks WHERE id = ? LIMIT 1;');
    final result = stmt.select([id]);
    StoredTask? task;
    if (result.isNotEmpty) {
      task = StoredTask.fromRow(result.first);
    }
    stmt.dispose();
    return task;
  }

  List<StoredTask> getAll({String? status, int limit = 50}) {
    if (status != null && status.isNotEmpty) {
      final stmt = db.prepare('SELECT * FROM download_tasks WHERE status = ? ORDER BY created_at DESC LIMIT ?;');
      final results = stmt.select([status, limit]);
      final list = results.map((r) => StoredTask.fromRow(r)).toList();
      stmt.dispose();
      return list;
    } else {
      final stmt = db.prepare('SELECT * FROM download_tasks ORDER BY created_at DESC LIMIT ?;');
      final results = stmt.select([limit]);
      final list = results.map((r) => StoredTask.fromRow(r)).toList();
      stmt.dispose();
      return list;
    }
  }

  bool delete(String id) {
    final stmt = db.prepare('DELETE FROM download_tasks WHERE id = ?;');
    stmt.execute([id]);
    final deleted = db.updatedRows > 0;
    stmt.dispose();
    return deleted;
  }
}
