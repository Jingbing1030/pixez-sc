import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../db/account_dao.dart';
import '../network/token_manager.dart';

class AuthRouter {
  final AccountDao accountDao;
  final TokenManager tokenManager;

  AuthRouter({required this.accountDao, required this.tokenManager});

  Router get router {
    final router = Router();

    // GET /api/v1/auth/accounts - list accounts
    router.get('/accounts', (Request request) async {
      final accounts = accountDao.getAllAccounts();
      final list = accounts.map((a) => a.toJson(maskTokens: true)).toList();
      return Response.ok(
        jsonEncode({'accounts': list}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // POST /api/v1/auth/token - add or update account via refresh token
    router.post('/token', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final refreshToken = body['refresh_token']?.toString();
        if (refreshToken == null || refreshToken.isEmpty) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Missing refresh_token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final account = await tokenManager.addOrUpdateByRefreshToken(refreshToken);
        if (account == null) {
          return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to authenticate with refresh token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        return Response.ok(
          jsonEncode({
            'message': 'Account added successfully',
            'account': account.toJson(maskTokens: true),
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // POST /api/v1/auth/switch - switch active account
    router.post('/switch', (Request request) async {
      try {
        final bodyStr = await request.readAsString();
        final body = jsonDecode(bodyStr);
        final accountId = body['account_id']?.toString();
        if (accountId == null) {
          return Response.badRequest(body: jsonEncode({'error': 'Missing account_id'}));
        }
        accountDao.setActive(accountId);
        return Response.ok(
          jsonEncode({'message': 'Active account switched'}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    // DELETE /api/v1/auth/accounts/<id> - remove account
    router.delete('/accounts/<id>', (Request request, String id) async {
      final success = accountDao.delete(id);
      return Response.ok(
        jsonEncode({'success': success}),
        headers: {'Content-Type': 'application/json'},
      );
    });

    return router;
  }
}
