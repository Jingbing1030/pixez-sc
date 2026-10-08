import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/server_config.dart';
import '../db/archive_dao.dart';

class ArchiveService {
  final ArchiveDao archiveDao;
  final ServerConfig config;

  ArchiveService({required this.archiveDao, required this.config});

  /// Archive an illustration metadata alongside downloaded file paths
  Future<ArchivedWork> archiveIllustration({
    required Map<String, dynamic> illustJson,
    required List<String> downloadedFilePaths,
  }) async {
    final workId = illustJson['id'].toString();
    final title = illustJson['title']?.toString() ?? 'Untitled';
    final user = illustJson['user'] as Map<String, dynamic>? ?? {};
    final userId = user['id']?.toString() ?? '';
    final userName = user['name']?.toString() ?? '';
    final createDate = illustJson['create_date']?.toString() ?? '';
    final caption = illustJson['caption']?.toString() ?? '';

    final tagsList = <String>[];
    if (illustJson['tags'] is List) {
      for (final t in illustJson['tags']) {
        if (t is Map && t['name'] != null) {
          tagsList.add(t['name'].toString());
        } else if (t is String) {
          tagsList.add(t);
        }
      }
    }

    final workType = (illustJson['type'] ?? 'illust').toString();

    // Store relative paths inside archive directory
    final relativeFiles = downloadedFilePaths.map((fullPath) {
      if (p.isWithin(config.archiveDir, fullPath)) {
        return p.relative(fullPath, from: config.archiveDir);
      }
      return fullPath;
    }).toList();

    final work = ArchivedWork(
      workId: workId,
      workType: workType,
      title: title,
      userId: userId,
      userName: userName,
      createDate: createDate,
      tags: tagsList,
      caption: caption,
      rawMetadata: illustJson,
      localFiles: relativeFiles,
      isDeletedUpstream: false,
      archivedAt: DateTime.now().millisecondsSinceEpoch,
    );

    archiveDao.upsert(work);
    return work;
  }

  /// Archive a novel metadata
  Future<ArchivedWork> archiveNovel({
    required Map<String, dynamic> novelJson,
    required String textContent,
    List<String> downloadedFilePaths = const [],
  }) async {
    final workId = novelJson['id'].toString();
    final title = novelJson['title']?.toString() ?? 'Untitled';
    final user = novelJson['user'] as Map<String, dynamic>? ?? {};
    final userId = user['id']?.toString() ?? '';
    final userName = user['name']?.toString() ?? '';
    final createDate = novelJson['create_date']?.toString() ?? '';
    final caption = novelJson['caption']?.toString() ?? '';

    final tagsList = <String>[];
    if (novelJson['tags'] is List) {
      for (final t in novelJson['tags']) {
        if (t is Map && t['name'] != null) {
          tagsList.add(t['name'].toString());
        }
      }
    }

    // Save novel text to local storage
    final novelDir = Directory(p.join(config.archiveDir, 'novels', workId));
    novelDir.createSync(recursive: true);
    final textFile = File(p.join(novelDir.path, 'content.txt'));
    await textFile.writeAsString(textContent);

    final allFiles = [
      p.relative(textFile.path, from: config.archiveDir),
      ...downloadedFilePaths.map((f) => p.isWithin(config.archiveDir, f) ? p.relative(f, from: config.archiveDir) : f),
    ];

    final work = ArchivedWork(
      workId: workId,
      workType: 'novel',
      title: title,
      userId: userId,
      userName: userName,
      createDate: createDate,
      tags: tagsList,
      caption: caption,
      rawMetadata: novelJson,
      localFiles: allFiles,
      isDeletedUpstream: false,
      archivedAt: DateTime.now().millisecondsSinceEpoch,
    );

    archiveDao.upsert(work);
    return work;
  }

  ArchivedWork? getById(String workId) {
    return archiveDao.findById(workId);
  }

  void markDeletedUpstream(String workId) {
    archiveDao.markDeletedUpstream(workId, true);
  }

  List<ArchivedWork> search({
    String? keyword,
    String? tag,
    String? workType,
    int limit = 30,
    int offset = 0,
  }) {
    return archiveDao.search(
      keyword: keyword,
      tag: tag,
      workType: workType,
      limit: limit,
      offset: offset,
    );
  }

  /// Reconstruct standard Pixiv Illust Detail JSON from archived work
  /// Replaces original pximg URLs with local mirror endpoints
  Map<String, dynamic> formatAsIllustDetailResponse(ArchivedWork work, String baseUrl) {
    final raw = Map<String, dynamic>.from(work.rawMetadata);

    // If local files exist, rewrite URLs to point to local mirror
    if (work.localFiles.isNotEmpty) {
      final firstFileName = p.basename(work.localFiles.first);
      final localImageUrl = '$baseUrl/api/v1/media/archive/${work.workType}/${work.workId}/$firstFileName';

      raw['image_urls'] = {
        'square_medium': localImageUrl,
        'medium': localImageUrl,
        'large': localImageUrl,
      };

      if (raw['meta_single_page'] is Map) {
        raw['meta_single_page'] = {
          'original_image_url': localImageUrl,
        };
      }

      if (raw['meta_pages'] is List) {
        final pages = <Map<String, dynamic>>[];
        for (int i = 0; i < work.localFiles.length; i++) {
          final fileName = p.basename(work.localFiles[i]);
          final url = '$baseUrl/api/v1/media/archive/${work.workType}/${work.workId}/$fileName';
          pages.add({
            'image_urls': {
              'square_medium': url,
              'medium': url,
              'large': url,
              'original': url,
            }
          });
        }
        raw['meta_pages'] = pages;
      }
    }

    return {
      'illust': raw,
      '_is_local_mirror': true,
      '_archived_at': work.archivedAt,
      '_is_deleted_upstream': work.isDeletedUpstream,
    };
  }

  File? resolveLocalFile(String workType, String workId, String fileName) {
    final possiblePath = p.join(config.archiveDir, workType, workId, fileName);
    final file = File(possiblePath);
    if (file.existsSync()) return file;

    // Also check downloads dir
    final dlPath = p.join(config.downloadDir, workType, workId, fileName);
    final dlFile = File(dlPath);
    if (dlFile.existsSync()) return dlFile;

    return null;
  }
}
