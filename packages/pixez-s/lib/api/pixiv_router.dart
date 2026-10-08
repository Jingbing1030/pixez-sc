import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../network/pixiv_client.dart';
import '../service/archive_service.dart';

class PixivRouter {
  final PixivClient pixivClient;
  final ArchiveService archiveService;

  PixivRouter({required this.pixivClient, required this.archiveService});

  String _getBaseUrl(Request request) {
    final scheme = request.requestedUri.scheme;
    final host = request.requestedUri.host;
    final port = request.requestedUri.port;
    return '$scheme://$host:$port';
  }

  Router get router {
    final router = Router();

    // GET /api/v1/pixiv/illust/<id> - with fallback to local archive mirror!
    router.get('/illust/<id>', (Request request, String id) async {
      final baseUrl = _getBaseUrl(request);
      try {
        final resp = await pixivClient.getIllustDetail(id);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } on DioException catch (dioErr) {
        final statusCode = dioErr.response?.statusCode;
        // Upstream 404 or 400 (work deleted or not found)
        if (statusCode == 404 || statusCode == 400) {
          final archived = archiveService.getById(id);
          if (archived != null) {
            archiveService.markDeletedUpstream(id);
            final mirrorResponse = archiveService.formatAsIllustDetailResponse(archived, baseUrl);
            return Response.ok(
              jsonEncode(mirrorResponse),
              headers: {
                'Content-Type': 'application/json',
                'X-Pixez-Mirror': 'fallback-local',
              },
            );
          }
        }

        // Return error if not archived
        final errBody = dioErr.response?.data != null
            ? (dioErr.response!.data is String ? dioErr.response!.data : jsonEncode(dioErr.response!.data))
            : jsonEncode({'error': dioErr.message});
        return Response(
          dioErr.response?.statusCode ?? 502,
          body: errBody,
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/ranking
    router.get('/ranking', (Request request) async {
      try {
        final params = request.url.queryParameters;
        final mode = params['mode'] ?? 'day';
        final filter = params['filter'] ?? 'for_android';
        final date = params['date'];
        final offset = int.tryParse(params['offset'] ?? '') ?? 0;

        final resp = await pixivClient.getRanking(
          mode: mode,
          filter: filter,
          date: date,
          offset: offset,
        );
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/recommended
    router.get('/recommended', (Request request) async {
      try {
        final params = request.url.queryParameters;
        final filter = params['filter'] ?? 'for_android';
        final offset = int.tryParse(params['offset'] ?? '') ?? 0;

        final resp = await pixivClient.getRecommended(
          filter: filter,
          offset: offset,
        );
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/search
    router.get('/search', (Request request) async {
      try {
        final params = request.url.queryParameters;
        final word = params['word'] ?? '';
        final searchTarget = params['search_target'] ?? 'partial_match_for_tags';
        final sort = params['sort'] ?? 'date_desc';
        final duration = params['duration'];
        final offset = int.tryParse(params['offset'] ?? '') ?? 0;

        final resp = await pixivClient.searchIllust(
          word,
          searchTarget: searchTarget,
          sort: sort,
          duration: duration,
          offset: offset,
        );
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/ugoira/<id>/metadata
    router.get('/ugoira/<id>/metadata', (Request request, String id) async {
      try {
        final resp = await pixivClient.getUgoiraMetadata(id);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/user/<id>
    router.get('/user/<id>', (Request request, String id) async {
      try {
        final resp = await pixivClient.getUserDetail(id);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // GET /api/v1/pixiv/user/<id>/illusts
    router.get('/user/<id>/illusts', (Request request, String id) async {
      try {
        final params = request.url.queryParameters;
        final type = params['type'] ?? 'illust';
        final offset = int.tryParse(params['offset'] ?? '') ?? 0;

        final resp = await pixivClient.getUserIllusts(id, type: type, offset: offset);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // POST /api/v1/pixiv/bookmark/add
    router.post('/bookmark/add', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final illustId = body['illust_id']?.toString() ?? '';
        final restrict = body['restrict']?.toString() ?? 'public';

        final resp = await pixivClient.postBookmarkAdd(illustId, restrict: restrict);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // POST /api/v1/pixiv/bookmark/delete
    router.post('/bookmark/delete', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final illustId = body['illust_id']?.toString() ?? '';

        final resp = await pixivClient.postBookmarkDelete(illustId);
        final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
        return Response.ok(
          jsonEncode(data),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    return router;
  }
}
