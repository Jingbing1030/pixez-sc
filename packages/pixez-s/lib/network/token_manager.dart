import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../config/server_config.dart';
import '../db/account_dao.dart';

class TokenManager {
  final AccountDao accountDao;
  final ServerConfig config;
  late final Dio _oauthDio;
  Timer? _refreshTimer;

  static const String hashSalt =
      "28c1fdd170a5204386cb1313c7077b34f83e4aaf4aa829ce78c231e05b0bae2c";
  static const String oauthHost = "oauth.secure.pixiv.net";
  static const String oauthUrl = "https://$oauthHost/auth/token";

  static const String clientId = "MOBrBDS8blbauoSck0ZfDbtuzpyT";
  static const String clientSecret = "lsACyCD94FhDUtGTXi3QzcFE2uU1hqtDaKeqrdwj";
  static const String refreshClientId = "KzEZED7aC0vird8jWyHM38mXjNTY";
  static const String refreshClientSecret = "W9JZoJe00qPvJsiyCGT3CCtC6ZUtdpKpzMbNlUGP";

  TokenManager({required this.accountDao, required this.config}) {
    _oauthDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'PixivAndroidApp/5.0.166 (Android 11; Pixel 5)',
        'App-OS-Version': 'Android 11',
      },
    ));
    _setupProxy();
  }

  void _setupProxy() {
    if (config.upstreamProxy != null && config.upstreamProxy!.isNotEmpty) {
      // Setup Dio proxy adapter if configured
      // ignore: deprecated_member_use
      (_oauthDio.httpClientAdapter as dynamic).onHttpClientCreate = (HttpClient client) {
        client.findProxy = (uri) => "PROXY ${config.upstreamProxy}";
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
  }

  void startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      checkAndRefreshAll();
    });
  }

  void stop() {
    _refreshTimer?.cancel();
  }

  String _getIsoDate() {
    final dateTime = DateTime.now().toUtc();
    return DateFormat("yyyy-MM-dd'T'HH:mm:ss'+00:00'").format(dateTime);
  }

  String _getHash(String string) {
    final content = utf8.encode(string);
    return md5.convert(content).toString();
  }

  Future<StoredAccount?> addOrUpdateByRefreshToken(String refreshToken, {bool setActive = true}) async {
    final time = _getIsoDate();
    final clientHash = _getHash('$time$hashSalt');

    try {
      final response = await _oauthDio.post(
        oauthUrl,
        data: {
          'client_id': refreshClientId,
          'client_secret': refreshClientSecret,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        },
        options: Options(
          headers: {
            'X-Client-Time': time,
            'X-Client-Hash': clientHash,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      final data = response.data is String ? jsonDecode(response.data) : response.data;
      final resp = data['response'];
      final user = resp['user'];
      final accessToken = resp['access_token'] as String;
      final newRefreshToken = resp['refresh_token'] as String;
      final expiresIn = (resp['expires_in'] as num?)?.toInt() ?? 3600;
      final expiresAt = DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000);

      final account = StoredAccount(
        id: user['id'].toString(),
        userId: user['id'].toString(),
        userName: (user['name'] ?? '').toString(),
        userAccount: (user['account'] ?? '').toString(),
        mailAddress: (user['mail_address'] ?? '').toString(),
        accessToken: accessToken,
        refreshToken: newRefreshToken,
        expiresAt: expiresAt,
        isActive: setActive,
        isPremium: (user['is_premium'] as bool? ?? false),
        xRestrict: (user['x_restrict'] as num?)?.toInt() ?? 0,
      );

      accountDao.upsert(account);
      if (setActive) {
        accountDao.setActive(account.id);
      }
      return account;
    } catch (e) {
      print('[TokenManager] Error refreshing token: $e');
      rethrow;
    }
  }

  Future<void> checkAndRefreshAll() async {
    final accounts = accountDao.getAllAccounts();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final acc in accounts) {
      // Refresh if less than 15 minutes remaining
      if (acc.expiresAt - now < 15 * 60 * 1000) {
        try {
          await addOrUpdateByRefreshToken(acc.refreshToken, setActive: acc.isActive);
        } catch (e) {
          print('[TokenManager] Auto-refresh failed for account ${acc.userName}: $e');
        }
      }
    }
  }

  Future<String?> getValidAccessToken() async {
    final active = accountDao.getActiveAccount();
    if (active == null) return null;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (active.expiresAt - now < 5 * 60 * 1000) {
      final updated = await addOrUpdateByRefreshToken(active.refreshToken, setActive: true);
      return updated?.accessToken;
    }
    return active.accessToken;
  }
}
