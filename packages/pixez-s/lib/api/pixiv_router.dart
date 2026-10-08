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

  Future<Response> _handleIllustDetail(Request request, String id) async {
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
  }

  Future<Response> _handleRanking(Request request) async {
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
  }

  Future<Response> _handleRecommended(Request request) async {
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
  }

  Future<Response> _handleSearch(Request request) async {
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
  }

  Future<Response> _handleUgoira(Request request, String id) async {
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
  }

  Future<Response> _handleUserDetail(Request request, String id) async {
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
  }

  Future<Response> _handleUserIllusts(Request request, String id) async {
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
  }

  Future<Response> _handleBookmarkAdd(Request request) async {
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
  }

  Future<Response> _handleBookmarkDelete(Request request) async {
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
  }

  Router get router {
    final router = Router();

    // 1. Simplified routes
    router.get('/illust/<id>', (Request r, String id) => _handleIllustDetail(r, id));
    router.get('/ranking', (Request r) => _handleRanking(r));
    router.get('/recommended', (Request r) => _handleRecommended(r));
    router.get('/search', (Request r) => _handleSearch(r));
    router.get('/ugoira/<id>/metadata', (Request r, String id) => _handleUgoira(r, id));
    router.get('/user/<id>', (Request r, String id) => _handleUserDetail(r, id));
    router.get('/user/<id>/illusts', (Request r, String id) => _handleUserIllusts(r, id));
    router.post('/bookmark/add', (Request r) => _handleBookmarkAdd(r));
    router.post('/bookmark/delete', (Request r) => _handleBookmarkDelete(r));

    // 2. Official Pixiv Native API paths (100% Drop-in Transparent Compatibility!)
    router.get('/v1/illust/detail', (Request r) {
      final id = r.url.queryParameters['illust_id'] ?? '';
      return _handleIllustDetail(r, id);
    });
    router.get('/v1/illust/ranking', (Request r) => _handleRanking(r));
    router.get('/v1/illust/recommended', (Request r) => _handleRecommended(r));
    router.get('/v1/search/illust', (Request r) => _handleSearch(r));
    router.get('/v1/ugoira/metadata', (Request r) {
      final id = r.url.queryParameters['illust_id'] ?? '';
      return _handleUgoira(r, id);
    });
    router.get('/v1/user/detail', (Request r) {
      final id = r.url.queryParameters['user_id'] ?? '';
      return _handleUserDetail(r, id);
    });
    router.get('/v1/user/illusts', (Request r) {
      final id = r.url.queryParameters['user_id'] ?? '';
      return _handleUserIllusts(r, id);
    });
    router.post('/v2/illust/bookmark/add', (Request r) => _handleBookmarkAdd(r));
    router.post('/v1/illust/bookmark/delete', (Request r) => _handleBookmarkDelete(r));

    return router;
  }
}
