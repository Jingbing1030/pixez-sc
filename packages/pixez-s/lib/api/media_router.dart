import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../service/archive_service.dart';
import '../service/media_cache_service.dart';

class MediaRouter {
  final MediaCacheService mediaCacheService;
  final ArchiveService archiveService;

  MediaRouter({required this.mediaCacheService, required this.archiveService});

  Router get router {
    final router = Router();

    // GET /api/v1/media/image?url=... - Image caching proxy
    router.get('/image', (Request request) async {
      final url = request.url.queryParameters['url'];
      if (url == null || url.isEmpty) {
        return Response.badRequest(body: 'Missing "url" query parameter');
      }
      return await mediaCacheService.proxyImage(request, url);
    });

    // GET /api/v1/media/archive/<work_type>/<work_id>/<file_name> - Local mirror media stream
    router.get('/archive/<work_type>/<work_id>/<file_name>', (
      Request request,
      String workType,
      String workId,
      String fileName,
    ) async {
      final file = archiveService.resolveLocalFile(workType, workId, fileName);
      if (file == null) {
        return Response.notFound('Media file not found');
      }
      return mediaCacheService.serveLocalFile(file);
    });

    return router;
  }
}
