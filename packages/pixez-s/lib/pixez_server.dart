import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'api/archive_router.dart';
import 'api/auth_router.dart';
import 'api/media_router.dart';
import 'api/pixiv_router.dart';
import 'api/task_router.dart';
import 'config/server_config.dart';
import 'db/account_dao.dart';
import 'db/archive_dao.dart';
import 'db/database.dart';
import 'db/task_dao.dart';
import 'network/pixiv_client.dart';
import 'network/token_manager.dart';
import 'service/archive_service.dart';
import 'service/discovery_service.dart';
import 'service/download_engine.dart';
import 'service/media_cache_service.dart';
import 'ws/ws_handler.dart';

/// Middleware for handling Cross-Origin Resource Sharing (CORS) headers.
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

/// Represents an instance of the Pixez headless server.
/// Can be run as a standalone binary or embedded directly into a Flutter application.
class PixezServer {
  final ServerConfig config;

  HttpServer? _httpServer;
  DiscoveryService? _discoveryService;
  AppDatabase? _appDb;
  TokenManager? _tokenManager;
  ArchiveService? _archiveService;
  DownloadEngine? _downloadEngine;
  bool _isRunning = false;

  PixezServer({required this.config});

  bool get isRunning => _isRunning;
  int? get port => _httpServer?.port;
  String? get host => _httpServer?.address.host;
  ArchiveService? get archiveService => _archiveService;
  DownloadEngine? get downloadEngine => _downloadEngine;
  AppDatabase? get db => _appDb;

  /// Starts the server.
  /// Automatically tries subsequent ports if [preferredPort] is in use.
  Future<int> start({
    String? host,
    int? preferredPort,
    bool enableDiscovery = true,
    int maxPortAttempts = 50,
  }) async {
    if (_isRunning) {
      return _httpServer!.port;
    }

    config.ensureDirectories();

    // 1. Initialize SQLite Database & DAOs
    _appDb = AppDatabase.open(config.dbDir);
    final accountDao = AccountDao(_appDb!.db);
    final archiveDao = ArchiveDao(_appDb!.db);
    final taskDao = TaskDao(_appDb!.db);

    // 2. Token Manager & Pixiv Client
    _tokenManager = TokenManager(accountDao: accountDao, config: config);
    _tokenManager!.startPeriodicRefresh();

    final pixivClient = PixivClient(tokenManager: _tokenManager!, config: config);

    // 3. Core Services
    _archiveService = ArchiveService(archiveDao: archiveDao, config: config);
    final mediaCacheService = MediaCacheService(config: config);
    _downloadEngine = DownloadEngine(
      taskDao: taskDao,
      archiveService: _archiveService!,
      pixivClient: pixivClient,
      config: config,
    );
    final wsHandler = WsHandler(downloadEngine: _downloadEngine!);

    // 4. API Routers
    final authRouter = AuthRouter(accountDao: accountDao, tokenManager: _tokenManager!);
    final pixivRouter = PixivRouter(pixivClient: pixivClient, archiveService: _archiveService!);
    final archiveRouter = ArchiveRouter(archiveService: _archiveService!);
    final mediaRouter = MediaRouter(mediaCacheService: mediaCacheService, archiveService: _archiveService!);
    final taskRouter = TaskRouter(taskDao: taskDao, downloadEngine: _downloadEngine!);

    final app = Router();

    // Health check endpoint
    app.get('/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'version': '0.1.0',
          'service': 'Pixez-s',
          'mode': 'embedded',
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

    final bindHost = host ?? config.host;
    int candidatePort = preferredPort ?? config.port;

    for (int attempt = 0; attempt < maxPortAttempts; attempt++) {
      try {
        _httpServer = await io.serve(handler, bindHost, candidatePort);
        break;
      } on SocketException catch (_) {
        if (attempt == maxPortAttempts - 1) {
          rethrow;
        }
        candidatePort++;
      }
    }

    if (_httpServer == null) {
      throw Exception('Failed to bind server to any port in range ${preferredPort ?? config.port}..$candidatePort');
    }

    _isRunning = true;

    // 5. Start LAN discovery beacon and probe responder if requested
    if (enableDiscovery) {
      _discoveryService = DiscoveryService(
        config: config,
        actualHttpPort: _httpServer!.port,
        discoveryPort: config.discoveryPort,
      );
      await _discoveryService!.start();
    }

    return _httpServer!.port;
  }

  /// Stops the server gracefully and closes open resources.
  Future<void> stop() async {
    if (!_isRunning) return;

    try {
      _discoveryService?.stop();
      _discoveryService = null;
    } catch (_) {}

    try {
      await _httpServer?.close(force: true);
      _httpServer = null;
    } catch (_) {}

    try {
      _appDb?.close();
      _appDb = null;
    } catch (_) {}

    _isRunning = false;
  }
}
