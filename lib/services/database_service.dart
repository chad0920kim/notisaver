import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/notification_log.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  
  // Async Singleton Race 방지를 위한 Future 캐싱
  Future<Database>? _dbFuture;

  DatabaseService._init();

  Future<Database> get database async {
    _dbFuture ??= _initDB('notisaver.db');
    return _dbFuture!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
      onConfigure: _onConfigure,
    );
  }

  // WAL (Write-Ahead Logging) 모드를 활성화하여 Kotlin 백그라운드 쓰기와 
  // Flutter 다트 읽기 간의 동시성 락(Lock) 충돌 방지
  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA journal_mode=WAL;');
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name TEXT NOT NULL,
        title TEXT,
        content TEXT,
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  // 필터 및 검색 기능 지원 로그 쿼리
  Future<List<NotificationLog>> getLogs({String? search, String? packageName}) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (search != null && search.isNotEmpty) {
      whereClause += '(title LIKE ? OR content LIKE ?)';
      whereArgs.add('%$search%');
      whereArgs.add('%$search%');
    }

    if (packageName != null && packageName.isNotEmpty && packageName != 'all') {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'package_name = ?';
      whereArgs.add(packageName);
    }

    final result = await db.query(
      'notification_logs',
      where: whereClause.isNotEmpty ? whereClause : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
    );

    return result.map((json) => NotificationLog.fromMap(json)).toList();
  }

  // 필터링 탭을 위한 고유 패키지 목록 추출
  Future<List<String>> getUniquePackages() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT package_name FROM notification_logs ORDER BY package_name ASC'
    );
    return result.map((row) => row['package_name'] as String).toList();
  }

  // 개별 로그 삭제
  Future<void> deleteLog(int id) async {
    final db = await database;
    await db.delete(
      'notification_logs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 전체 로그 삭제
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('notification_logs');
  }
}
