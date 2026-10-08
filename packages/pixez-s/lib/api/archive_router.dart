import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../service/archive_service.dart';

class ArchiveRouter {
  final ArchiveService archiveService;

  ArchiveRouter({required this.archiveService});

  String _getBaseUrl(Request request) {
    final scheme = request.requestedUri.scheme;
    final host = request.requestedUri.host;
    final port = request.requestedUri.port;
    return '$scheme://$host:$port';
  }

  Router get router {
    final router = Router();

    // GET /api/v1/archives - Search / list offline archives
    router.get('/', (Request request) async {
      final params = request.url.queryParameters;
      final keyword = params['keyword'];
      final tag = params['tag'];
      final workType = params['type'];
      final limit = int.tryParse(params['limit'] ?? '') ?? 30;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;

      final results = archiveService.search(
        keyword: keyword,
        tag: tag,
        workType: workType,
        limit: limit,
        offset: offset,
      );

      return Response.ok(
        jsonEncode({
          'count': results.length,
          'archives': results.map((e) => e.toJson()).toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // GET /api/v1/archives/<id> - Get single archive
    router.get('/<id>', (Request request, String id) async {
      final archived = archiveService.getById(id);
      if (archived == null) {
        return Response.notFound(
          jsonEncode({'error': 'Archive not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final baseUrl = _getBaseUrl(request);
      final formatted = archiveService.formatAsIllustDetailResponse(archived, baseUrl);
      return Response.ok(
        jsonEncode(formatted),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // DELETE /api/v1/archives/<id> - Delete archive
    router.delete('/<id>', (Request request, String id) async {
      final success = archiveService.archiveDao.delete(id);
      return Response.ok(
        jsonEncode({'success': success}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router;
  }
}
