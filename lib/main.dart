import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'providers/notification_provider.dart';
import 'models/notification_log.dart';
import 'services/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Google Mobile Ads SDK 초기화
  try {
    await MobileAds.instance.initialize();
  } catch (e) {
    debugPrint("Failed to initialize MobileAds SDK: $e");
  }
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Failed to load .env file: $e");
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => NotificationProvider(),
      child: const NotiSaverApp(),
    ),
  );
}

class NotiSaverApp extends StatelessWidget {
  const NotiSaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '알림 보관함',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0A11),
        primaryColor: const Color(0xFF6C63FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF00F2FE),
          surface: Color(0xFF151421),
          error: Color(0xFFFF5252),
        ),
        cardTheme: const CardTheme(
          color: Color(0xFF151421),
          elevation: 4,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
          bodyMedium: TextStyle(color: Color(0xFFD0CFE2)),
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // 앱이 백그라운드에서 다시 활성화될 때 권한 상태 및 알림 목록 리로드
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = context.read<NotificationProvider>();
      provider.checkPermissionStatus();
      provider.loadLogs();      // ← 백그라운드에서 쌓인 알림 목록 갱신
      provider.loadPackages(); // ← 필터 탭 갱신
    }
  }

  // 배너 광고 로딩 함수
  void _loadBannerAd() {
    final adUnitId = dotenv.env['ADMOB_BANNER_UNIT_ID'] ?? 'ca-app-pub-3940256099942544/6300978111';
    
    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (ad, err) {
          debugPrint('Failed to load AdMob banner: ${err.message}');
          ad.dispose();
          _bannerAd = null;
          setState(() {
            _isBannerAdReady = false;
          });
        },
      ),
    )..load();
  }

  // 테스트용 더미 알림 DB 직접 삽입 (디버그 목적: Kotlin 서비스 vs Flutter DB/UI 구분용)
  Future<void> _insertTestNotification(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final provider = context.read<NotificationProvider>();
      await DatabaseService.instance.insertTestLog();
      await provider.loadLogs();
      await provider.loadPackages();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ DB 삽입 성공! 목록에 [테스트] 항목이 나타났는지 확인하세요.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ DB 오류: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  // 프리미엄 구매 다이얼로그 표시 함수 (실제 구글 플레이 인앱결제 연동)
  void _showPremiumDialog(BuildContext context, NotificationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('광고 없는 프리미엄 업그레이드'),
        content: const Text(
          '광고 없는 깔끔한 알림 보관함 서비스를 원하시나요?\n\n'
          '모든 광고가 즉시 영구 제거되며, 백그라운드 실시간 알림 백업 기능을 계속 지원합니다.\n\n'
          '💳 가격: ₩1,200 (1회성 영구 결제)',
        ),
        actions: [
          TextButton(
            onPressed: () {
              provider.restorePurchases();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🔄 기존 구매 내역 복원을 시도합니다...')),
              );
            },
            child: const Text('구매 복원'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('다음에'),
          ),
          TextButton(
            onPressed: () {
              provider.buyAdFree();
              Navigator.pop(context);
            },
            child: const Text('결제 진행', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  // 패키지 명칭을 읽기 쉽게 번역
  String _getAppLabel(String packageName) {
    switch (packageName) {
      case 'com.kakao.talk':
        return '카카오톡';
      case 'com.whatsapp':
        return 'WhatsApp';
      case 'org.telegram.messenger':
        return '텔레그램';
      case 'com.linecorp.line.android':
        return '라인';
      case 'com.android.mms':
      case 'com.google.android.apps.messaging':
        return '기본 메시지';
      default:
        final parts = packageName.split('.');
        if (parts.isNotEmpty) {
          final name = parts.last;
          return name[0].toUpperCase() + name.substring(1);
        }
        return packageName;
    }
  }

  // 패키지별 색상 지정
  Color _getAppColor(String packageName) {
    switch (packageName) {
      case 'com.kakao.talk':
        return const Color(0xFFFFE812); // 카카오 옐로우
      case 'com.whatsapp':
        return const Color(0xFF25D366); // 왓츠앱 초록
      case 'org.telegram.messenger':
        return const Color(0xFF0088CC); // 텔레그램 하늘색
      case 'com.linecorp.line.android':
        return const Color(0xFF06C755); // 라인 연두색
      default:
        return const Color(0xFF6C63FF); // 기본 보라색
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    // 광고 상태에 맞춰 배너 광고 메모리 제어
    if (provider.isAdFree) {
      if (_bannerAd != null) {
        _bannerAd!.dispose();
        _bannerAd = null;
        _isBannerAdReady = false;
      }
    } else {
      if (_bannerAd == null && !_isBannerAdReady) {
        _loadBannerAd();
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0A11),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.security_update_good, color: Color(0xFF00F2FE), size: 28),
            const SizedBox(width: 10),
            Text(
              '알림 보관함',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 22,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          // 프리미엄 결제 (광고 미제거 상태 시 노출)
          if (!provider.isAdFree)
            IconButton(
              icon: const Icon(Icons.workspace_premium, color: Colors.amber),
              tooltip: '광고 제거',
              onPressed: () => _showPremiumDialog(context, provider),
            ),
          // 전체 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.grey),
            tooltip: '전체 삭제',
            onPressed: () {
              if (provider.logs.isEmpty) return;
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('전체 알림 삭제'),
                  content: const Text('보관된 모든 알림 아카이브를 지우시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () {
                        provider.clearAllLogs();
                        Navigator.pop(context);
                      },
                      child: const Text('삭제', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
          // 설정 및 베타 피드백
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.grey),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('베타 검증 안내'),
                  content: const Text(
                    '이 앱은 오프라인 우선 개인 알림 아카이브 시스템입니다.\n\n'
                    '보안 솔루션 우회 테스트 중이며, 수집된 모든 정보는 기기 내부 로컬 DB에만 암호화 보존됩니다.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('확인'),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. 권한 배너 (권한이 없는 경우 활성화)
          if (!provider.hasPermission)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9900), Color(0xFFFF5E62)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5E62).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Text(
                        '알림 접근 권한 비활성화됨',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '삭제된 메시지를 복구하고 알림을 아카이빙하기 위해서는 시스템 알림 접근 설정이 필수적입니다.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => provider.requestPermission(),
                      child: const Text('설정 활성화하러 가기', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),

          // 2. 검색창
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => provider.setSearchTerm(val),
              decoration: InputDecoration(
                hintText: '이름 또는 본문 검색...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          provider.setSearchTerm('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF151421),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // 3. 필터링 칩스 (가로 스크롤)
          Container(
            height: 48,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: provider.packages.length + 1,
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final package = isAll ? 'all' : provider.packages[index - 1];
                final label = isAll ? '전체 보기' : _getAppLabel(package);
                final isSelected = provider.selectedPackage == package;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (bool selected) {
                      provider.selectPackage(package);
                    },
                    selectedColor: const Color(0xFF6C63FF).withOpacity(0.2),
                    checkmarkColor: const Color(0xFF00F2FE),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF6C63FF) : Colors.transparent,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 4. 피드 목록
          Expanded(
            child: provider.logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.archive_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          provider.searchTerm.isNotEmpty
                              ? '검색 결과와 일치하는 알림이 없습니다.'
                              : '아카이빙된 알림이 없습니다.\n메시지가 도착하면 자동으로 이곳에 보관됩니다.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await provider.loadLogs();
                      await provider.loadPackages();
                    },
                    child: ListView.builder(
                    itemCount: provider.logs.length,
                    itemBuilder: (context, index) {
                      final NotificationLog log = provider.logs[index];
                      return Dismissible(
                        key: Key(log.id?.toString() ?? 'log_${log.timestamp}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          if (log.id != null) {
                            provider.deleteLog(log.id!);
                          }
                        },
                        child: Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getAppColor(log.packageName).withOpacity(0.15),
                              child: Text(
                                _getAppLabel(log.packageName)[0],
                                style: TextStyle(
                                  color: _getAppColor(log.packageName),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    log.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  _formatTime(log.timestamp),
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Text(
                                log.content,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  ),
          ),

          // 5. 실제 AdMob 배너 광고 영역
          if (!provider.isAdFree && _isBannerAdReady && _bannerAd != null)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF151421), width: 1.0)),
              ),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'debug_insert',
        backgroundColor: const Color(0xFF2A2940),
        tooltip: 'DB 직접 삽입 테스트',
        onPressed: () => _insertTestNotification(context),
        child: const Icon(Icons.bug_report, color: Colors.grey, size: 18),
      ),
    );
  }



  // 날짜/시간 포맷팅 유틸
  String _formatTime(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24 && date.day == now.day) {
      return '오늘 ${_padZero(date.hour)}:${_padZero(date.minute)}';
    } else {
      return '${date.month}월 ${date.day}일 ${_padZero(date.hour)}:${_padZero(date.minute)}';
    }
  }

  String _padZero(int value) => value.toString().padLeft(2, '0');
}
