import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../config/server_config.dart';
import 'token_manager.dart';

class PixivClient {
  final TokenManager tokenManager;
  final ServerConfig config;
  late final Dio dio;

  static const String baseApiHost = 'app-api.pixiv.net';
  static const String baseApiUrl = 'https://$baseApiHost';

  PixivClient({required this.tokenManager, required this.config}) {
    dio = Dio(BaseOptions(
      baseUrl: baseApiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': 'PixivAndroidApp/5.0.166 (Android 11; Pixel 5)',
        'App-OS-Version': 'Android 11',
        'Accept-Language': 'zh-CN',
      },
    ));

    _setupProxy();

    // Token injector interceptor
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenManager.getValidAccessToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  void _setupProxy() {
    if (config.upstreamProxy != null && config.upstreamProxy!.isNotEmpty) {
      final adapter = dio.httpClientAdapter;
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

  Future<Response> getIllustDetail(String illustId) async {
    return await dio.get('/v1/illust/detail', queryParameters: {'illust_id': illustId});
  }

  Future<Response> getRanking({
    String mode = 'day',
    String? filter = 'for_android',
    String? date,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'mode': mode,
      if (filter != null) 'filter': filter,
      if (date != null) 'date': date,
      if (offset > 0) 'offset': offset,
    };
    return await dio.get('/v1/illust/ranking', queryParameters: params);
  }

  Future<Response> getRecommended({
    String? filter = 'for_android',
    bool includeRankingIllusts = true,
    int? minBookmarkIdForRecentIllust,
    int? maxBookmarkIdForRecentIllust,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      if (filter != null) 'filter': filter,
      'include_ranking_illusts': includeRankingIllusts,
      if (minBookmarkIdForRecentIllust != null)
        'min_bookmark_id_for_recent_illust': minBookmarkIdForRecentIllust,
      if (maxBookmarkIdForRecentIllust != null)
        'max_bookmark_id_for_recent_illust': maxBookmarkIdForRecentIllust,
      if (offset > 0) 'offset': offset,
    };
    return await dio.get('/v1/illust/recommended', queryParameters: params);
  }

  Future<Response> searchIllust(
    String word, {
    String searchTarget = 'partial_match_for_tags',
    String sort = 'date_desc',
    String? duration,
    String? filter = 'for_android',
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'word': word,
      'search_target': searchTarget,
      'sort': sort,
      if (duration != null) 'duration': duration,
      if (filter != null) 'filter': filter,
      if (offset > 0) 'offset': offset,
    };
    return await dio.get('/v1/search/illust', queryParameters: params);
  }

  Future<Response> getUgoiraMetadata(String illustId) async {
    return await dio.get('/v1/ugoira/metadata', queryParameters: {'illust_id': illustId});
  }

  Future<Response> getNovelDetail(String novelId) async {
    return await dio.get('/v2/novel/detail', queryParameters: {'novel_id': novelId});
  }

  Future<Response> getUserDetail(String userId, {String? filter = 'for_android'}) async {
    return await dio.get('/v1/user/detail', queryParameters: {
      'user_id': userId,
      if (filter != null) 'filter': filter,
    });
  }

  Future<Response> getUserIllusts(
    String userId, {
    String type = 'illust',
    String? filter = 'for_android',
    int offset = 0,
  }) async {
    return await dio.get('/v1/user/illusts', queryParameters: {
      'user_id': userId,
      'type': type,
      if (filter != null) 'filter': filter,
      if (offset > 0) 'offset': offset,
    });
  }

  Future<Response> postBookmarkAdd(String illustId, {String restrict = 'public'}) async {
    return await dio.post(
      '/v2/illust/bookmark/add',
      data: {'illust_id': illustId, 'restrict': restrict},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  Future<Response> postBookmarkDelete(String illustId) async {
    return await dio.post(
      '/v1/illust/bookmark/delete',
      data: {'illust_id': illustId},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }
}
