import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/task_dao.dart';
import '../service/download_engine.dart';

class TaskRouter {
  final TaskDao taskDao;
  final DownloadEngine downloadEngine;

  TaskRouter({required this.taskDao, required this.downloadEngine});

  Router get router {
    final router = Router();

    // GET /api/v1/tasks - List download tasks
    router.get('/', (Request request) async {
      final status = request.url.queryParameters['status'];
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50;
      final tasks = taskDao.getAll(status: status, limit: limit);
      return Response.ok(
        jsonEncode({'tasks': tasks.map((t) => t.toJson()).toList()}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // POST /api/v1/tasks - Enqueue download task
    router.post('/', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final illustId = body['illust_id']?.toString();
        if (illustId == null || illustId.isEmpty) {
          return Response.badRequest(body: jsonEncode({'error': 'Missing illust_id'}));
        }

        final illustJson = body['illust_json'] as Map<String, dynamic>?;
        final task = await downloadEngine.enqueueIllustDownload(
          illustId: illustId,
          illustJson: illustJson,
        );

        return Response.ok(
          jsonEncode({
            'message': 'Download task enqueued',
            'task': task.toJson(),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // GET /api/v1/tasks/<id> - Get single task
    router.get('/<id>', (Request request, String id) async {
      final task = taskDao.findById(id);
      if (task == null) {
        return Response.notFound(jsonEncode({'error': 'Task not found'}));
      }
      return Response.ok(
        jsonEncode({'task': task.toJson()}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // DELETE /api/v1/tasks/<id> - Delete task
    router.delete('/<id>', (Request request, String id) async {
      final success = taskDao.delete(id);
      return Response.ok(
        jsonEncode({'success': success}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router;
  }
}
