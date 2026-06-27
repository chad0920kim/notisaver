import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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
  
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _iapSubscription;
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
      _initializeIAP();
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

  // 5. 실제 인앱 결제(IAP) 수명 주기 초기화
  void _initializeIAP() {
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _iapSubscription = purchaseUpdated.listen(
      (List<PurchaseDetails> purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      },
      onDone: () {
        _iapSubscription?.cancel();
      },
      onError: (Object error) {
        if (kDebugMode) {
          print("IAP purchaseStream error: $error");
        }
      },
    );
  }

  // 결제 업데이트 수신 리스너
  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // 결제 진행 중 (대기 상태 처리 가능)
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        if (kDebugMode) {
          print("IAP Error: ${purchaseDetails.error}");
        }
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                 purchaseDetails.status == PurchaseStatus.restored) {
        // 광고 제거 상품 ID 검증 ('ad_free')
        if (purchaseDetails.productID == 'ad_free') {
          await _setAdFreeStatus(true);
        }

        // 구글 결제 트랜잭션 종결(completePurchase) 필수 처리 (3일 내 환불 방지)
        if (purchaseDetails.pendingCompletePurchase) {
          await _iap.completePurchase(purchaseDetails);
        }
      }
    }
  }

  // 광고 제거 구매 적용 및 로컬 프리퍼런스 저장
  Future<void> _setAdFreeStatus(bool status) async {
    final prefs = await SharedPreferences.getInstance();
    _isAdFree = status;
    await prefs.setBool('isAdFree', status);
    notifyListeners();
  }

  // 광고 제거 상태 로드
  Future<void> _loadAdFreeStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    _isAdFree = prefs.getBool('isAdFree') ?? false;
    notifyListeners();
  }

  // 실제 결제 요청 실행 (Google Play Store)
  Future<void> buyAdFree() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      if (kDebugMode) print("Billing store not available.");
      return;
    }

    const Set<String> kIds = <String>{'ad_free'};
    final ProductDetailsResponse response = await _iap.queryProductDetails(kIds);
    if (response.notFoundIDs.isNotEmpty) {
      if (kDebugMode) {
        print("Product not found: ${response.notFoundIDs}");
      }
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    // 비소모품 결제 요청 (Non-consumable)
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  // 구매 내역 복원 (Restore Purchases - 구글 심사 필수 조건)
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      if (kDebugMode) {
        print("Failed to restore purchases: $e");
      }
    }
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
    _iapSubscription?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }
}
