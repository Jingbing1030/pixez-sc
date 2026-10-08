import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/api/archive_router.dart';
import '../lib/api/auth_router.dart';
import '../lib/api/media_router.dart';
import '../lib/api/pixiv_router.dart';
import '../lib/api/task_router.dart';
import '../lib/config/server_config.dart';
import '../lib/db/account_dao.dart';
import '../lib/db/archive_dao.dart';
import '../lib/db/database.dart';
import '../lib/db/task_dao.dart';
import '../lib/network/pixiv_client.dart';
import '../lib/network/token_manager.dart';
import '../lib/service/archive_service.dart';
import '../lib/service/discovery_service.dart';
import '../lib/service/download_engine.dart';
import '../lib/service/media_cache_service.dart';
import '../lib/ws/ws_handler.dart';

Middleware corsHeaders() {
  return createMiddleware(
    requestHandler: (Request request) {
      if (request.method.toUpperCase() == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Accept',
        });
      }
      return null;
    },
    responseHandler: (Response response) {
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Accept',
      });
    },
  );
}

void main(List<String> args) async {
  final config = ServerConfig.fromEnv();
  print('==================================================');
  print('           Pixez-s (Headless Server)              ');
  print('==================================================');
  print('[Config] Data Directory: ${config.dataDir}');
  if (config.upstreamProxy != null) {
    print('[Config] Upstream Proxy: ${config.upstreamProxy}');
  }

  // Database & DAOs
  final appDb = AppDatabase.open(config.dbDir);
  final accountDao = AccountDao(appDb.db);
  final archiveDao = ArchiveDao(appDb.db);
  final taskDao = TaskDao(appDb.db);

  // Network & Token Manager
  final tokenManager = TokenManager(accountDao: accountDao, config: config);
  tokenManager.startPeriodicRefresh();

  final pixivClient = PixivClient(tokenManager: tokenManager, config: config);

  // Services
  final archiveService = ArchiveService(archiveDao: archiveDao, config: config);
  final mediaCacheService = MediaCacheService(config: config);
  final downloadEngine = DownloadEngine(
    taskDao: taskDao,
    archiveService: archiveService,
    pixivClient: pixivClient,
    config: config,
  );
  final wsHandler = WsHandler(downloadEngine: downloadEngine);

  // Routers
  final authRouter = AuthRouter(accountDao: accountDao, tokenManager: tokenManager);
  final pixivRouter = PixivRouter(pixivClient: pixivClient, archiveService: archiveService);
  final archiveRouter = ArchiveRouter(archiveService: archiveService);
  final mediaRouter = MediaRouter(mediaCacheService: mediaCacheService, archiveService: archiveService);
  final taskRouter = TaskRouter(taskDao: taskDao, downloadEngine: downloadEngine);

  final app = Router();

  // Root health check
  app.get('/health', (Request request) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'version': '0.1.0',
        'service': 'Pixez-s',
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Mount API modules
  app.mount('/api/v1/auth', authRouter.router.call);
  app.mount('/api/v1/pixiv', pixivRouter.router.call);
  app.mount('/api/v1/archives', archiveRouter.router.call);
  app.mount('/api/v1/media', mediaRouter.router.call);
  app.mount('/api/v1/tasks', taskRouter.router.call);
  app.mount('/api/v1/ws', wsHandler.handler);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(app.call);

  HttpServer? server;
  int candidatePort = config.port;
  const maxPortAttempts = 50;

  for (int attempt = 0; attempt < maxPortAttempts; attempt++) {
    try {
      server = await io.serve(handler, config.host, candidatePort);
      break;
    } on SocketException catch (_) {
      if (attempt == maxPortAttempts - 1) {
        rethrow;
      }
      print('[Server] Port $candidatePort is in use, automatically incrementing to ${candidatePort + 1}...');
      candidatePort++;
    }
  }

  if (server == null) {
    throw Exception('Failed to bind server to any port in range ${config.port}..$candidatePort');
  }

  print('[Server] Running on http://${server.address.host}:${server.port}');

  // Start LAN discovery beacon and probe responder (announcing the actual bound HTTP port!)
  final discoveryService = DiscoveryService(
    config: config,
    actualHttpPort: server.port,
    discoveryPort: config.discoveryPort,
  );
  await discoveryService.start();
  print('==================================================');

  // Graceful shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\n[Server] Shutting down...');
    discoveryService.stop();
    tokenManager.stop();
    await server?.close();
    appDb.close();
    exit(0);
  });
}
