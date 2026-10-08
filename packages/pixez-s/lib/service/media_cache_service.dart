import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart' hide Response;
import 'package:dio/io.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import '../config/server_config.dart';

class MediaCacheService {
  final ServerConfig config;
  late final Dio _dio;

  MediaCacheService({required this.config}) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Referer': 'https://app-api.pixiv.net/',
        'User-Agent': 'PixivAndroidApp/5.0.166 (Android 11; Pixel 5)',
      },
      responseType: ResponseType.stream,
    ));

    if (config.upstreamProxy != null && config.upstreamProxy!.isNotEmpty) {
      final adapter = _dio.httpClientAdapter;
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

  String _hashUrl(String url) {
    final bytes = utf8.encode(url);
    return md5.convert(bytes).toString();
  }

  Future<Response> proxyImage(Request request, String targetUrl) async {
    final hash = _hashUrl(targetUrl);
    final ext = p.extension(Uri.parse(targetUrl).path);
    final cacheFile = File(p.join(config.cacheDir, '$hash$ext'));

    // Cache hit
    if (cacheFile.existsSync()) {
      final mimeType = lookupMimeType(cacheFile.path) ?? 'image/jpeg';
      return Response.ok(
        cacheFile.openRead(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': cacheFile.lengthSync().toString(),
          'Cache-Control': 'public, max-age=864000',
          'X-Cache-Lookup': 'HIT',
        },
      );
    }

    // Cache miss: fetch from upstream
    try {
      final upstream = await _dio.get(targetUrl);
      final mimeType = upstream.headers.value('content-type') ??
          lookupMimeType(targetUrl) ??
          'image/jpeg';

      // Pipe to cache file
      final responseBody = upstream.data.stream as Stream<List<int>>;
      final tempFile = File('${cacheFile.path}.tmp');
      final sink = tempFile.openWrite();

      await for (final chunk in responseBody) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      if (tempFile.existsSync()) {
        tempFile.renameSync(cacheFile.path);
      }

      return Response.ok(
        cacheFile.openRead(),
        headers: {
          'Content-Type': mimeType,
          'Content-Length': cacheFile.lengthSync().toString(),
          'Cache-Control': 'public, max-age=864000',
          'X-Cache-Lookup': 'MISS',
        },
      );
    } catch (e) {
      return Response.internalServerError(
        body: 'Failed to fetch upstream media: $e',
        headers: {'Content-Type': 'text/plain'},
      );
    }
  }

  Response serveLocalFile(File file) {
    if (!file.existsSync()) {
      return Response.notFound('File not found');
    }
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': file.lengthSync().toString(),
        'Cache-Control': 'public, max-age=604800',
      },
    );
  }
}
