import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_log.dart';
import '../services/database_service.dart';

class NotificationProvider extends ChangeNotifier {
  static const _permissionChannel = MethodChannel('com.chadkim.notisaver/permission');
  static const _eventChannel = EventChannel('com.chadkim.notisaver/events');

  List<NotificationLog> _logs = [];
  List<String> _packages = [];
  String _selectedPackage = 'all';
  String _searchTerm = '';
  bool _hasPermission = false;
  bool _isAdFree = false;
  bool _isDisposed = false;
  
  StreamSubscription? _eventSubscription;
  Timer? _searchDebounce;

  List<NotificationLog> get logs => _logs;
  List<String> get packages => _packages;
  String get selectedPackage => _selectedPackage;
  String get searchTerm => _searchTerm;
  bool get hasPermission => _hasPermission;
  bool get isAdFree => _isAdFree;

  NotificationProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      await checkPermissionStatus();
      await loadLogs();
      await loadPackages();
      await _loadAdFreeStatus();
      _startListeningToEvents();
    } catch (e) {
      if (kDebugMode) {
        print("Initialization error in NotificationProvider: $e");
      }
    }
  }

  // 실시간 네이티브 알림 브로드캐스트 리스너 등록
  void _startListeningToEvents() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (_isDisposed) return;
        // 네이티브가 직접 DB에 기록하므로 Dart는 UI 데이터를 리로딩만 수행
        loadLogs();
        loadPackages();
      },
      onError: (err) {
        if (kDebugMode) {
          print("EventChannel error: $err");
        }
      }
    );
  }

  // 1. 알림 로그 조회
  Future<void> loadLogs() async {
    if (_isDisposed) return;
    try {
      _logs = await DatabaseService.instance.getLogs(
        search: _searchTerm,
        packageName: _selectedPackage,
      );
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Failed to load logs: $e");
      }
    }
  }

  // 2. 고유 패키지 필터 목록 조회
  Future<void> loadPackages() async {
    if (_isDisposed) return;
    try {
      _packages = await DatabaseService.instance.getUniquePackages();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Failed to load packages: $e");
      }
    }
  }

  // 3. 필터 선택 및 실시간 조회
  void selectPackage(String package) {
    _selectedPackage = package;
    loadLogs();
  }

  // 검색창 입력 속도 디바운싱 추가 (연속 쿼리로 인한 오버헤드 및 화면 깜빡임/순서 뒤틀림 방지)
  void setSearchTerm(String term) {
    _searchTerm = term;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!_isDisposed) {
        loadLogs();
      }
    });
  }

  // 4. 알림 접근 권한 관련 네이티브 통신
  Future<void> checkPermissionStatus() async {
    if (_isDisposed) return;
    try {
      final bool status = await _permissionChannel.invokeMethod('checkPermission');
      _hasPermission = status;
      notifyListeners();
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Failed to check permission: ${e.message}");
      }
    }
  }

  Future<void> requestPermission() async {
    try {
      await _permissionChannel.invokeMethod('requestPermission');
      // 권한 활성화 후 앱 복귀 시를 위해 2초 뒤 상태 갱신
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isDisposed) {
          checkPermissionStatus();
        }
      });
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print("Failed to request permission: ${e.message}");
      }
    }
  }

  // 5. 광고 제거 상태 (IAP 시뮬레이션)
  Future<void> _loadAdFreeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    _isAdFree = prefs.getBool('isAdFree') ?? false;
    notifyListeners();
  }

  Future<void> buyAdFree() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAdFree', true);
    _isAdFree = true;
    notifyListeners();
  }

  // 6. 삭제 모듈
  Future<void> deleteLog(int id) async {
    await DatabaseService.instance.deleteLog(id);
    await loadLogs();
    await loadPackages();
  }

  Future<void> clearAllLogs() async {
    await DatabaseService.instance.clearAll();
    await loadLogs();
    await loadPackages();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _eventSubscription?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
