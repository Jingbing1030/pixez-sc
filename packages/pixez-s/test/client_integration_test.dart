import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' hide Response;
import 'package:pixez_s/api/archive_router.dart';
import 'package:pixez_s/api/auth_router.dart';
import 'package:pixez_s/api/media_router.dart';
import 'package:pixez_s/api/pixiv_router.dart';
import 'package:pixez_s/api/task_router.dart';
import 'package:pixez_s/config/server_config.dart';
import 'package:pixez_s/db/account_dao.dart';
import 'package:pixez_s/db/archive_dao.dart';
import 'package:pixez_s/db/database.dart';
import 'package:pixez_s/db/task_dao.dart';
import 'package:pixez_s/network/pixiv_client.dart';
import 'package:pixez_s/network/token_manager.dart';
import 'package:pixez_s/service/archive_service.dart';
import 'package:pixez_s/service/discovery_service.dart';
import 'package:pixez_s/service/download_engine.dart';
import 'package:pixez_s/service/media_cache_service.dart';
import 'package:pixez_s/ws/ws_handler.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

void main() {
  group('Pixez-cs Client-Server Transparent Integration Tests', () {
    late Directory tempDir;
    late ServerConfig config;
    late AppDatabase appDb;
    late HttpServer server;
    late DiscoveryService discoveryService;
    late ArchiveService archiveService;
    late Dio clientDio;

    const testDiscoveryPort = 41288;
    const testHttpPort = 48899;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('pixez_integration_');
      config = ServerConfig(
        dataDir: tempDir.path,
        port: testHttpPort,
        discoveryPort: testDiscoveryPort,
      );
      config.ensureDirectories();

      appDb = AppDatabase.open(config.dbDir);
      final accountDao = AccountDao(appDb.db);
      final archiveDao = ArchiveDao(appDb.db);
      final taskDao = TaskDao(appDb.db);

      final tokenManager = TokenManager(accountDao: accountDao, config: config);
      final pixivClient = PixivClient(tokenManager: tokenManager, config: config);
      archiveService = ArchiveService(archiveDao: archiveDao, config: config);
      final mediaCacheService = MediaCacheService(config: config);
      final downloadEngine = DownloadEngine(
        taskDao: taskDao,
        archiveService: archiveService,
        pixivClient: pixivClient,
        config: config,
      );
      final wsHandler = WsHandler(downloadEngine: downloadEngine);

      final authRouter = AuthRouter(accountDao: accountDao, tokenManager: tokenManager);
      final pixivRouter = PixivRouter(pixivClient: pixivClient, archiveService: archiveService);
      final archiveRouter = ArchiveRouter(archiveService: archiveService);
      final mediaRouter = MediaRouter(mediaCacheService: mediaCacheService, archiveService: archiveService);
      final taskRouter = TaskRouter(taskDao: taskDao, downloadEngine: downloadEngine);

      final app = Router();
      app.get('/health', (Request request) {
        return Response.ok(
          jsonEncode({'status': 'ok', 'service': 'Pixez-s'}),
          headers: {'content-type': 'application/json'},
        );
      });
      app.mount('/api/v1/auth', authRouter.router.call);
      app.mount('/api/v1/pixiv', pixivRouter.router.call);
      app.mount('/api/v1/archives', archiveRouter.router.call);
      app.mount('/api/v1/media', mediaRouter.router.call);
      app.mount('/api/v1/tasks', taskRouter.router.call);
      app.mount('/api/v1/ws', wsHandler.handler);

      server = await io.serve(app.call, '127.0.0.1', testHttpPort);

      discoveryService = DiscoveryService(
        config: config,
        actualHttpPort: server.port,
        discoveryPort: testDiscoveryPort,
      );
      await discoveryService.start();

      clientDio = Dio(BaseOptions(
        baseUrl: 'http://127.0.0.1:${server.port}',
        connectTimeout: const Duration(seconds: 5),
      ));
    });

    tearDown(() async {
      discoveryService.stop();
      await server.close();
      appDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('health check returns ok', () async {
      final resp = await clientDio.get('/health');
      expect(resp.statusCode, equals(200));
      expect(resp.data['status'], equals('ok'));
    });

    test('LAN UDP discovery responds with correct HTTP port', () async {
      final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final completer = Completer<Map<String, dynamic>>();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) {
            final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
            if (!completer.isCompleted) {
              completer.complete(json);
            }
          }
        }
      });

      final probe = jsonEncode({'action': 'discover', 'service': 'pixez-s'});
      socket.send(utf8.encode(probe), InternetAddress.loopbackIPv4, testDiscoveryPort);

      final result = await completer.future.timeout(const Duration(seconds: 3));
      socket.close();

      expect(result['service'], equals('pixez-s'));
      expect(result['port'], equals(testHttpPort));
    });

    test('native Pixiv API path /v1/illust/detail falls back to local mirror when archived', () async {
      // 1. Pre-seed local archive for deleted work ID 555666
      final fakeWork = {
        'id': 555666,
        'title': 'Deleted Masterpiece',
        'type': 'illust',
        'caption': 'Author deleted this work on Pixiv',
        'user': {'id': 999, 'name': 'Deleted Artist'},
        'tags': [{'name': 'archive'}, {'name': 'art'}],
        'image_urls': {'large': 'https://i.pximg.net/c/600x1200_90/custom.jpg'},
      };
      final localFile = File('${config.archiveDir}/illust/555666/555666_p0.jpg');
      localFile.parent.createSync(recursive: true);
      localFile.writeAsStringSync('fake-image');

      await archiveService.archiveIllustration(
        illustJson: fakeWork,
        downloadedFilePaths: [localFile.path],
      );

      // 2. Client calls Pixiv native path: /api/v1/pixiv/v1/illust/detail?illust_id=555666
      // Since upstream Pixiv doesn't have it (or fails), it falls back to local mirror!
      final resp = await clientDio.get(
        '/api/v1/pixiv/v1/illust/detail',
        queryParameters: {'illust_id': '555666'},
      );

      expect(resp.statusCode, equals(200));
      expect(resp.headers.value('X-Pixez-Mirror'), equals('fallback-local'));
      expect(resp.data['illust']['title'], equals('Deleted Masterpiece'));
      expect(resp.data['_is_local_mirror'], isTrue);

      // Verify rewritten local media url
      final localImageUrl = resp.data['illust']['image_urls']['large'] as String;
      expect(localImageUrl, contains('/api/v1/media/archive/illust/555666/555666_p0.jpg'));

      // 3. Test downloading the local mirror media file directly
      final mediaResp = await clientDio.get('/api/v1/media/archive/illust/555666/555666_p0.jpg');
      expect(mediaResp.statusCode, equals(200));
    });
  });
}
