import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';

class ArchivedWork {
  final String workId;
  final String workType;
  final String title;
  final String userId;
  final String userName;
  final String createDate;
  final List<String> tags;
  final String caption;
  final Map<String, dynamic> rawMetadata;
  final List<String> localFiles;
  final bool isDeletedUpstream;
  final int archivedAt;

  ArchivedWork({
    required this.workId,
    required this.workType,
    required this.title,
    required this.userId,
    required this.userName,
    required this.createDate,
    required this.tags,
    required this.caption,
    required this.rawMetadata,
    required this.localFiles,
    required this.isDeletedUpstream,
    required this.archivedAt,
  });

  factory ArchivedWork.fromRow(Row row) {
    List<String> parsedTags = [];
    try {
      final tagsRaw = row['tags_json'];
      if (tagsRaw != null) {
        final decoded = jsonDecode(tagsRaw as String);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}

    Map<String, dynamic> parsedRawMetadata = {};
    try {
      final metaRaw = row['raw_metadata'];
      if (metaRaw != null) {
        parsedRawMetadata = jsonDecode(metaRaw as String) as Map<String, dynamic>;
      }
    } catch (_) {}

    List<String> parsedLocalFiles = [];
    try {
      final filesRaw = row['local_files_json'];
      if (filesRaw != null) {
        final decoded = jsonDecode(filesRaw as String);
        if (decoded is List) {
          parsedLocalFiles = decoded.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}

    return ArchivedWork(
      workId: (row['work_id'] ?? '').toString(),
      workType: (row['work_type'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      userName: (row['user_name'] ?? '').toString(),
      createDate: (row['create_date'] ?? '').toString(),
      tags: parsedTags,
      caption: (row['caption'] ?? '').toString(),
      rawMetadata: parsedRawMetadata,
      localFiles: parsedLocalFiles,
      isDeletedUpstream: (row['is_deleted_upstream'] as int? ?? 0) == 1,
      archivedAt: (row['archived_at'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'work_id': workId,
    'work_type': workType,
    'title': title,
    'user_id': userId,
    'user_name': userName,
    'create_date': createDate,
    'tags': tags,
    'caption': caption,
    'raw_metadata': rawMetadata,
    'local_files': localFiles,
    'is_deleted_upstream': isDeletedUpstream,
    'archived_at': archivedAt,
  };
}

class ArchiveDao {
  final Database db;

  ArchiveDao(this.db);

  void upsert(ArchivedWork work) {
    final stmt = db.prepare('''
      INSERT INTO archived_works (
        work_id, work_type, title, user_id, user_name, create_date,
        tags_json, caption, raw_metadata, local_files_json,
        is_deleted_upstream, archived_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(work_id) DO UPDATE SET
        title = excluded.title,
        user_name = excluded.user_name,
        tags_json = excluded.tags_json,
        caption = excluded.caption,
        raw_metadata = excluded.raw_metadata,
        local_files_json = excluded.local_files_json,
        is_deleted_upstream = excluded.is_deleted_upstream,
        archived_at = excluded.archived_at;
    ''');

    stmt.execute([
      work.workId,
      work.workType,
      work.title,
      work.userId,
      work.userName,
      work.createDate,
      jsonEncode(work.tags),
      work.caption,
      jsonEncode(work.rawMetadata),
      jsonEncode(work.localFiles),
      work.isDeletedUpstream ? 1 : 0,
      work.archivedAt,
    ]);
    stmt.dispose();
  }

  ArchivedWork? findById(String workId) {
    final stmt = db.prepare('SELECT * FROM archived_works WHERE work_id = ? LIMIT 1;');
    final result = stmt.select([workId]);
    ArchivedWork? work;
    if (result.isNotEmpty) {
      work = ArchivedWork.fromRow(result.first);
    }
    stmt.dispose();
    return work;
  }

  void markDeletedUpstream(String workId, bool isDeleted) {
    final stmt = db.prepare('UPDATE archived_works SET is_deleted_upstream = ? WHERE work_id = ?;');
    stmt.execute([isDeleted ? 1 : 0, workId]);
    stmt.dispose();
  }

  List<ArchivedWork> search({
    String? keyword,
    String? tag,
    String? workType,
    int limit = 30,
    int offset = 0,
  }) {
    final conditions = <String>[];
    final params = <dynamic>[];

    if (workType != null && workType.isNotEmpty) {
      conditions.add('work_type = ?');
      params.add(workType);
    }

    if (keyword != null && keyword.trim().isNotEmpty) {
      conditions.add('(title LIKE ? OR user_name LIKE ? OR caption LIKE ?)');
      final pattern = '%${keyword.trim()}%';
      params.add(pattern);
      params.add(pattern);
      params.add(pattern);
    }

    if (tag != null && tag.trim().isNotEmpty) {
      conditions.add('tags_json LIKE ?');
      params.add('%"${tag.trim()}"%');
    }

    final whereClause = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final sql = '''
      SELECT * FROM archived_works
      $whereClause
      ORDER BY archived_at DESC
      LIMIT ? OFFSET ?;
    ''';

    params.add(limit);
    params.add(offset);

    final stmt = db.prepare(sql);
    final results = stmt.select(params);
    final list = results.map((r) => ArchivedWork.fromRow(r)).toList();
    stmt.dispose();
    return list;
  }

  bool delete(String workId) {
    final stmt = db.prepare('DELETE FROM archived_works WHERE work_id = ?;');
    stmt.execute([workId]);
    final deleted = db.updatedRows > 0;
    stmt.dispose();
    return deleted;
  }
}
