import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/payment_parser.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final databasePath = join(await getDatabasesPath(), 'ririko.db');
    final db = await openDatabase(
      databasePath,
      version: 2,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            '''
            CREATE TABLE IF NOT EXISTS transactions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              fingerprint TEXT NOT NULL UNIQUE,
              amount REAL NOT NULL,
              direction TEXT NOT NULL,
              sourceApp TEXT NOT NULL,
              sourceTitle TEXT NOT NULL,
              sourceContent TEXT NOT NULL,
              counterparty TEXT,
              category TEXT NOT NULL,
              note TEXT,
              happenedAt TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
            ''',
          );
        }
      },
    );

    return AppDatabase._(db);
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute(
      '''
      CREATE TABLE logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        packageName TEXT NOT NULL,
        time TEXT NOT NULL
      )
      ''',
    );
    await db.execute(
      '''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fingerprint TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL,
        direction TEXT NOT NULL,
        sourceApp TEXT NOT NULL,
        sourceTitle TEXT NOT NULL,
        sourceContent TEXT NOT NULL,
        counterparty TEXT,
        category TEXT NOT NULL,
        note TEXT,
        happenedAt TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
      ''',
    );
  }

  Future<void> insertNotificationLog({
    required String title,
    required String content,
    required String packageName,
    required String time,
  }) {
    return _db.insert('logs', {
      'title': title,
      'content': content,
      'packageName': packageName,
      'time': time,
    });
  }

  Future<void> insertTransaction(ParsedTransaction transaction) {
    final now = DateTime.now().toIso8601String();
    return _db.insert(
      'transactions',
      {
        'fingerprint': transaction.fingerprint,
        'amount': transaction.amount,
        'direction': transaction.direction,
        'sourceApp': transaction.sourceApp,
        'sourceTitle': transaction.title,
        'sourceContent': transaction.content,
        'counterparty': transaction.counterparty,
        'category': transaction.category,
        'note': transaction.note,
        'happenedAt': transaction.happenedAt.toIso8601String(),
        'createdAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> insertManualTransaction({
    required double amount,
    required String direction,
    required String sourceApp,
    required String title,
    required String category,
    String? counterparty,
    String? content,
    String? note,
    DateTime? happenedAt,
  }) {
    final occurredAt = happenedAt ?? DateTime.now();
    final normalizedContent = (content ?? note ?? '').trim();
    final normalizedNote = note?.trim();
    final fingerprint =
        'manual|$direction|$amount|${occurredAt.toIso8601String()}|$title|$normalizedContent';

    return _db.insert(
      'transactions',
      {
        'fingerprint': fingerprint,
        'amount': amount,
        'direction': direction,
        'sourceApp': sourceApp,
        'sourceTitle': title,
        'sourceContent': normalizedContent,
        'counterparty': _emptyToNull(counterparty),
        'category': category,
        'note': _emptyToNull(normalizedNote),
        'happenedAt': occurredAt.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<Map<String, dynamic>>> getRecentLogs({int limit = 50}) {
    return _db.query('logs', orderBy: 'id DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions({int limit = 100}) {
    return _db.query('transactions', orderBy: 'happenedAt DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getAllTransactions() {
    return _db.query('transactions', orderBy: 'happenedAt DESC');
  }

  Future<void> updateTransaction({
    required int id,
    required double amount,
    required String direction,
    required String title,
    required String content,
    required String category,
    required DateTime happenedAt,
    String? counterparty,
    String? note,
  }) {
    return _db.update(
      'transactions',
      {
        'amount': amount,
        'direction': direction,
        'sourceTitle': title,
        'sourceContent': content.trim(),
        'counterparty': _emptyToNull(counterparty),
        'category': category,
        'note': _emptyToNull(note),
        'happenedAt': happenedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, double>> getCurrentMonthSummary() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);

    final incomeRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE direction = ? AND happenedAt >= ? AND happenedAt < ?
      ''',
      [ 'income', start.toIso8601String(), end.toIso8601String() ],
    );
    final expenseRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM transactions
      WHERE direction = ? AND happenedAt >= ? AND happenedAt < ?
      ''',
      [ 'expense', start.toIso8601String(), end.toIso8601String() ],
    );

    return {
      'income': (incomeRows.first['total'] as num?)?.toDouble() ?? 0,
      'expense': (expenseRows.first['total'] as num?)?.toDouble() ?? 0,
    };
  }

  String? _emptyToNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> close() => _db.close();
}
