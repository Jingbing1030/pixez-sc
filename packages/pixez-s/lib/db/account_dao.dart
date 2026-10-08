import 'package:sqlite3/sqlite3.dart';

class StoredAccount {
  final String id;
  final String userId;
  final String userName;
  final String userAccount;
  final String mailAddress;
  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final bool isActive;
  final bool isPremium;
  final int xRestrict;

  StoredAccount({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAccount,
    required this.mailAddress,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.isActive,
    required this.isPremium,
    required this.xRestrict,
  });

  factory StoredAccount.fromRow(Row row) {
    return StoredAccount(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
      userName: (row['user_name'] ?? '').toString(),
      userAccount: (row['user_account'] ?? '').toString(),
      mailAddress: (row['mail_address'] ?? '').toString(),
      accessToken: (row['access_token'] ?? '').toString(),
      refreshToken: (row['refresh_token'] ?? '').toString(),
      expiresAt: (row['expires_at'] as int? ?? 0),
      isActive: (row['is_active'] as int? ?? 0) == 1,
      isPremium: (row['is_premium'] as int? ?? 0) == 1,
      xRestrict: (row['x_restrict'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toJson({bool maskTokens = true}) => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'user_account': userAccount,
    'mail_address': mailAddress,
    'is_active': isActive,
    'is_premium': isPremium,
    'x_restrict': xRestrict,
    'expires_at': expiresAt,
    if (!maskTokens) ...{
      'access_token': accessToken,
      'refresh_token': refreshToken,
    },
  };
}

class AccountDao {
  final Database db;

  AccountDao(this.db);

  void upsert(StoredAccount account) {
    final stmt = db.prepare('''
      INSERT INTO accounts (
        id, user_id, user_name, user_account, mail_address,
        access_token, refresh_token, expires_at, is_active, is_premium, x_restrict
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        user_name = excluded.user_name,
        user_account = excluded.user_account,
        mail_address = excluded.mail_address,
        access_token = excluded.access_token,
        refresh_token = excluded.refresh_token,
        expires_at = excluded.expires_at,
        is_active = excluded.is_active,
        is_premium = excluded.is_premium,
        x_restrict = excluded.x_restrict;
    ''');

    stmt.execute([
      account.id,
      account.userId,
      account.userName,
      account.userAccount,
      account.mailAddress,
      account.accessToken,
      account.refreshToken,
      account.expiresAt,
      account.isActive ? 1 : 0,
      account.isPremium ? 1 : 0,
      account.xRestrict,
    ]);
    stmt.dispose();
  }

  StoredAccount? getActiveAccount() {
    final stmt = db.prepare('SELECT * FROM accounts WHERE is_active = 1 LIMIT 1;');
    final result = stmt.select([]);
    StoredAccount? account;
    if (result.isNotEmpty) {
      account = StoredAccount.fromRow(result.first);
    } else {
      // If none marked active, fallback to first available
      final fallbackStmt = db.prepare('SELECT * FROM accounts LIMIT 1;');
      final fallbackResult = fallbackStmt.select([]);
      if (fallbackResult.isNotEmpty) {
        account = StoredAccount.fromRow(fallbackResult.first);
      }
      fallbackStmt.dispose();
    }
    stmt.dispose();
    return account;
  }

  List<StoredAccount> getAllAccounts() {
    final stmt = db.prepare('SELECT * FROM accounts ORDER BY is_active DESC, user_id ASC;');
    final results = stmt.select([]);
    final list = results.map((r) => StoredAccount.fromRow(r)).toList();
    stmt.dispose();
    return list;
  }

  void setActive(String id) {
    db.execute('UPDATE accounts SET is_active = 0;');
    final stmt = db.prepare('UPDATE accounts SET is_active = 1 WHERE id = ?;');
    stmt.execute([id]);
    stmt.dispose();
  }

  void updateTokens(String id, String accessToken, String refreshToken, int expiresAt) {
    final stmt = db.prepare('''
      UPDATE accounts SET
        access_token = ?,
        refresh_token = ?,
        expires_at = ?
      WHERE id = ?;
    ''');
    stmt.execute([accessToken, refreshToken, expiresAt, id]);
    stmt.dispose();
  }

  bool delete(String id) {
    final stmt = db.prepare('DELETE FROM accounts WHERE id = ?;');
    stmt.execute([id]);
    final deleted = db.updatedRows > 0;
    stmt.dispose();
    return deleted;
  }
}
