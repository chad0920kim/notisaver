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
  // onConfigure에서는 execute() 대신 rawQuery() 사용 필수
  Future _onConfigure(Database db) async {
    await db.rawQuery('PRAGMA journal_mode=WAL;');
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

  // 디버그용 테스트 레코드 직접 삽입 (Flutter DB→UI 체인 검증용)
  Future<void> insertTestLog() async {
    final db = await database;
    await db.insert('notification_logs', {
      'package_name': 'com.debug.test',
      'title': '[테스트] DB 직접 삽입',
      'content': 'Flutter DB→UI 체인이 정상입니다. Kotlin 서비스를 확인하세요.',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
