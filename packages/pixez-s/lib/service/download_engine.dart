import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import '../config/server_config.dart';
import '../db/task_dao.dart';
import '../network/pixiv_client.dart';
import 'archive_service.dart';

class DownloadEngine {
  final TaskDao taskDao;
  final ArchiveService archiveService;
  final PixivClient pixivClient;
  final ServerConfig config;
  late final Dio _downloadDio;

  final StreamController<Map<String, dynamic>> _progressStreamController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get progressStream => _progressStreamController.stream;

  final List<StoredTask> _queue = [];
  bool _isProcessing = false;

  DownloadEngine({
    required this.taskDao,
    required this.archiveService,
    required this.pixivClient,
    required this.config,
  }) {
    _downloadDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Referer': 'https://app-api.pixiv.net/',
        'User-Agent': 'PixivAndroidApp/5.0.166 (Android 11; Pixel 5)',
      },
      responseType: ResponseType.stream,
    ));

    if (config.upstreamProxy != null && config.upstreamProxy!.isNotEmpty) {
      final adapter = _downloadDio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => "PROXY ${config.upstreamProxy}";
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
    }
  }

  Future<StoredTask> enqueueIllustDownload({
    required String illustId,
    Map<String, dynamic>? illustJson,
  }) async {
    Map<String, dynamic> metadata;
    if (illustJson != null) {
      metadata = illustJson;
    } else {
      final resp = await pixivClient.getIllustDetail(illustId);
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      metadata = data['illust'] as Map<String, dynamic>;
    }

    final title = metadata['title']?.toString() ?? 'Illust $illustId';
    final pageCount = (metadata['page_count'] as num?)?.toInt() ?? 1;
    final workType = (metadata['type'] ?? 'illust').toString();
    final targetDir = p.join(config.archiveDir, workType, illustId);

    final task = StoredTask(
      id: 'task_${illustId}_${DateTime.now().millisecondsSinceEpoch}',
      workId: illustId,
      workType: workType,
      title: title,
      targetDir: targetDir,
      totalPages: pageCount,
      downloadedPages: 0,
      status: 'pending',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    taskDao.insert(task);
    _queue.add(task);
    _triggerProcess(metadata);
    return task;
  }

  void _triggerProcess([Map<String, dynamic>? metadata]) {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;
    final task = _queue.removeAt(0);

    _processTask(task, metadata).whenComplete(() {
      _isProcessing = false;
      _triggerProcess();
    });
  }

  Future<void> _processTask(StoredTask task, Map<String, dynamic>? metadata) async {
    try {
      taskDao.updateProgress(task.id, 0, task.totalPages, 'running');
      _notifyProgress(task.id, 0, task.totalPages, 'running');

      Map<String, dynamic> workMeta;
      if (metadata != null) {
        workMeta = metadata;
      } else {
        final resp = await pixivClient.getIllustDetail(task.workId);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        workMeta = data['illust'] as Map<String, dynamic>;
      }

      final dir = Directory(task.targetDir);
      dir.createSync(recursive: true);

      // Collect image URLs
      final urls = <String>[];
      final metaSingle = workMeta['meta_single_page'] as Map<String, dynamic>?;
      final metaPages = workMeta['meta_pages'] as List<dynamic>?;

      if (metaPages != null && metaPages.isNotEmpty) {
        for (final p in metaPages) {
          final imgUrl = p['image_urls']?['original']?.toString();
          if (imgUrl != null) urls.add(imgUrl);
        }
      } else if (metaSingle != null && metaSingle['original_image_url'] != null) {
        urls.add(metaSingle['original_image_url'].toString());
      } else if (workMeta['image_urls']?['large'] != null) {
        urls.add(workMeta['image_urls']['large'].toString());
      }

      final downloadedFiles = <String>[];

      for (int i = 0; i < urls.length; i++) {
        final url = urls[i];
        final ext = p.extension(Uri.parse(url).path);
        final fileName = '${task.workId}_p$i$ext';
        final filePath = p.join(task.targetDir, fileName);
        final file = File(filePath);

        if (!file.existsSync() || file.lengthSync() == 0) {
          await _downloadFile(url, file);
        }
        downloadedFiles.add(file.path);

        taskDao.updateProgress(task.id, i + 1, urls.length, 'running');
        _notifyProgress(task.id, i + 1, urls.length, 'running');
      }

      // Automatically archive metadata alongside the downloaded files
      await archiveService.archiveIllustration(
        illustJson: workMeta,
        downloadedFilePaths: downloadedFiles,
      );

      taskDao.updateProgress(task.id, urls.length, urls.length, 'completed');
      _notifyProgress(task.id, urls.length, urls.length, 'completed');
    } catch (e) {
      print('[DownloadEngine] Task ${task.id} failed: $e');
      taskDao.updateProgress(task.id, task.downloadedPages, task.totalPages, 'failed', errorMsg: e.toString());
      _notifyProgress(task.id, task.downloadedPages, task.totalPages, 'failed', error: e.toString());
    }
  }

  Future<void> _downloadFile(String url, File targetFile) async {
    final response = await _downloadDio.get(url);
    final stream = response.data.stream as Stream<List<int>>;
    final sink = targetFile.openWrite();
    await for (final chunk in stream) {
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
  }

  void _notifyProgress(String taskId, int progress, int total, String status, {String? error}) {
    _progressStreamController.add({
      'type': 'task_progress',
      'task_id': taskId,
      'progress': progress,
      'total': total,
      'status': status,
      if (error != null) 'error': error,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
