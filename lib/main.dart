// lib/main.dart

import 'dart:async';
import 'dart:math' as math; // [필수] 거리 계산용 수학 공식
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 햅틱(진동)
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';
import 'package:dio/dio.dart';
import 'api_keys.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterNaverMap().init(
    clientId: naverMapClientId,
    onAuthFailed: (error) {
      print('네이버 지도 인증 실패: $error');
    },
  );

  runApp(const SmartCaneApp());
}

class SmartCaneApp extends StatelessWidget {
  const SmartCaneApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Location _location = Location();
  late final NaverMapApiService _apiService;
  NaverMapController? _mapController;

  // 실시간 위치 추적용 구독 변수
  StreamSubscription<LocationData>? _locationSubscription;

  final TextEditingController _searchController = TextEditingController();
  NLatLng? _currentLocation;
  NLatLng? _destinationLocation;

  // [추가] 현재 경로의 좌표 리스트 (이탈 감지용)
  List<NLatLng> _pathCoords = [];

  // [추가] 재탐색 관련 변수
  bool _isRecalculating = false;
  static const double _deviationThreshold = 30.0; // 30m 이탈 시 재탐색
  DateTime _lastRecalcTime = DateTime.now();

  bool isLidarOn = false;
  bool _isScreenLocked = false;

  final List<DateTime> _tapTimestamps = [];
  static const int _unlockTapCount = 5;
  static const Duration _unlockTapDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _apiService = NaverMapApiService(
      clientId: apiGwClientId,
      clientSecret: apiGwClientSecret,
      tmapAppKey: tmapAppKey,
    );
  }

  @override
  void dispose() {
    // 앱 종료 시 위치 추적 중단
    _locationSubscription?.cancel();
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showLockSnackbar() {
    _showSnackBar("화면이 잠겨있습니다.", isError: true);
  }

  void toggleLidar() {
    setState(() => isLidarOn = !isLidarOn);
    if (isLidarOn) {
      _showSnackBar("라이다 센서 ON");
      HapticFeedback.lightImpact();
    } else {
      _showSnackBar("라이다 센서 OFF");
    }
  }

  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    if (permissionGranted == PermissionStatus.granted) {
      _mapController?.setLocationTrackingMode(NLocationTrackingMode.follow);

      // [핵심] 실시간 위치 추적 시작 (재탐색을 위해 필수)
      _startLocationListening();
    }
  }

  // [추가] 실시간 위치를 감시하며 경로 이탈을 체크하는 함수
  void _startLocationListening() {
    _location.changeSettings(accuracy: LocationAccuracy.high, interval: 2000, distanceFilter: 2);

    _locationSubscription = _location.onLocationChanged.listen((LocationData locationData) {
      if (locationData.latitude == null || locationData.longitude == null) return;

      final newLocation = NLatLng(locationData.latitude!, locationData.longitude!);

      setState(() {
        _currentLocation = newLocation;
      });

      // 경로 안내 중이고(_pathCoords 있음), 목적지가 있고, 현재 재탐색 중이 아니라면?
      if (_pathCoords.isNotEmpty && _destinationLocation != null && !_isRecalculating) {
        _checkRouteDeviation(newLocation); // -> 이탈 여부 확인!
      }
    });
  }

  // [추가] 경로 이탈 확인 로직
  void _checkRouteDeviation(NLatLng userLoc) {
    double minDistance = double.infinity;

    // 내 위치가 경로선에서 가장 가까운 점과의 거리 계산
    for (var point in _pathCoords) {
      double dist = _calculateDistance(userLoc, point);
      if (dist < minDistance) {
        minDistance = dist;
      }
    }

    // 30m 이상 벗어나면 재탐색 트리거
    if (minDistance > _deviationThreshold) {
      // 너무 잦은 재탐색 방지 (10초 쿨타임)
      if (DateTime.now().difference(_lastRecalcTime).inSeconds > 10) {
        print("🚨 경로 이탈 감지! ($minDistance m) -> 재탐색 시작");
        _handleRecalculation();
      }
    }
  }

  // [추가] 재탐색 실행 함수
  Future<void> _handleRecalculation() async {
    setState(() {
      _isRecalculating = true;
      _lastRecalcTime = DateTime.now();
    });

    HapticFeedback.heavyImpact(); // 강한 진동으로 알림
    _showSnackBar("경로를 이탈했습니다. 새로운 길을 찾습니다.", isError: true);

    // 현재 위치에서 다시 길찾기 실행 (isRecalc: true)
    await _findPath(isRecalc: true);

    setState(() {
      _isRecalculating = false;
    });
  }

  // [추가] 거리 계산 공식 (Haversine)
  double _calculateDistance(NLatLng p1, NLatLng p2) {
    const double earthRadius = 6371000;
    double dLat = (p2.latitude - p1.latitude) * (math.pi / 180.0);
    double dLon = (p2.longitude - p1.longitude) * (math.pi / 180.0);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * (math.pi / 180.0)) *
            math.cos(p2.latitude * (math.pi / 180.0)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  Future<void> _searchDestination() async {
    if (_isScreenLocked) {
      _showLockSnackbar();
      return;
    }

    final String query = _searchController.text;
    if (query.isEmpty) {
      _showSnackBar("검색어를 입력하세요.", isError: true);
      return;
    }

    FocusScope.of(context).unfocus();

    try {
      final (destination, placeName) = await _apiService.searchGeocode(query);
      _destinationLocation = destination;

      _mapController?.clearOverlays();
      final marker = NMarker(
        id: 'destination',
        position: _destinationLocation!,
        icon: const NOverlayImage.fromAssetImage('assets/marker.png'),
      );
      _mapController?.addOverlay(marker);
      _mapController?.updateCamera(NCameraUpdate.scrollAndZoomTo(
        target: _destinationLocation!,
        zoom: 15,
      ));

      // 검색만 했을 때는 아직 잠그지 않음 (길찾기 버튼 눌러야 잠금)
      _showSnackBar("목적지 설정: $placeName");

    } catch (e) {
      _showSnackBar("검색 실패", isError: true);
    }
  }

  // [수정] 길찾기 함수 (재탐색 모드 지원)
  Future<void> _findPath({bool isRecalc = false}) async {
    // 재탐색이 아닐 때만 위치 강제 업데이트
    if (!isRecalc) {
      // 위치가 없으면 잠깐 기다렸다가 가져오기
      if (_currentLocation == null) {
        final loc = await _location.getLocation();
        _currentLocation = NLatLng(loc.latitude!, loc.longitude!);
      }
    }

    if (_currentLocation == null || _destinationLocation == null) {
      if (!isRecalc) _showSnackBar("위치 정보를 확인하세요.", isError: true);
      return;
    }

    try {
      final pathPoints = await _apiService.findWalkingRoute(
        _currentLocation!,
        _destinationLocation!,
      );

      // [중요] 받아온 경로를 저장해야 이탈 감지가 가능함
      _pathCoords = pathPoints;

      _mapController?.clearOverlays(type: NOverlayType.polylineOverlay);

      final polyline = NPolylineOverlay(
        id: 'path',
        coords: pathPoints,
        color: Colors.red,
        width: 5,
      );
      _mapController?.addOverlay(polyline);

      // 재탐색이 아닐 때만(처음 시작할 때만) 화면 잠금 & 카메라 이동
      if (!isRecalc) {
        _mapController?.updateCamera(
            NCameraUpdate.fitBounds(NLatLngBounds.from(pathPoints)));

        setState(() {
          _isScreenLocked = true; // 화면 잠금 시작!
        });

        _showSnackBar("안내 시작. 화면 조작이 잠깁니다.");
        HapticFeedback.mediumImpact();
      } else {
        // 재탐색일 때는 조용히 경로만 바꿈
        print("재탐색 완료");
      }

    } catch (e) {
      _showSnackBar("경로 탐색 실패", isError: true);
    }
  }

  Future<void> _cancelPath() async {
    _mapController?.clearOverlays();
    _destinationLocation = null;
    _searchController.clear();
    _pathCoords.clear(); // 경로 데이터 초기화

    setState(() {
      _isScreenLocked = false; // 잠금 해제
    });

    _showSnackBar("안내 및 잠금이 해제되었습니다.");
  }

  void _handleUnlockTap() {
    if (!_isScreenLocked) return;

    final now = DateTime.now();
    _tapTimestamps
        .removeWhere((tap) => now.difference(tap) > _unlockTapDuration);
    _tapTimestamps.add(now);

    if (_tapTimestamps.length >= _unlockTapCount) {
      _tapTimestamps.clear();
      setState(() {
        _isScreenLocked = false;
      });
      _showSnackBar("화면 잠금이 해제되었습니다.");
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          enabled: !_isScreenLocked,
          decoration: InputDecoration(
            hintText: _isScreenLocked ? '안내 중 (화면 잠김)' : '목적지를 검색하세요...',
            fillColor: Colors.white,
            filled: true,
            border: InputBorder.none,
          ),
          onSubmitted: (value) => _searchDestination(),
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _isScreenLocked ? _showLockSnackbar : _searchDestination,
          ),
          IconButton(
            icon: const Icon(Icons.directions_walk),
            onPressed: _isScreenLocked ? null : () => _findPath(),
          ),
          IconButton(
            icon: const Icon(Icons.cancel),
            onPressed: _cancelPath,
          ),
        ],
      ),
      body: Stack(
        children: [
          NaverMap(
            options: const NaverMapViewOptions(
              locationButtonEnable: true,
            ),
            onMapReady: _onMapReady,
          ),
          Positioned(
            left: 0, right: 0, bottom: 30,
            child: Center(
              child: GestureDetector(
                onTap: toggleLidar,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: isLidarOn ? Colors.green : Colors.grey, shape: BoxShape.circle),
                  child: Icon(isLidarOn ? Icons.sensors_off : Icons.sensors, size: 40, color: Colors.white),
                ),
              ),
            ),
          ),
          if (_isScreenLocked)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showLockSnackbar(),
                onPanUpdate: (_) {},
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(
                    child: Text("화면 잠금", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 24)),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0, right: 0, width: 100, height: 100,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleUnlockTap,
              child: Container(
                color: _isScreenLocked ? Colors.red.withOpacity(0.3) : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NaverMapApiService {
  final Dio _dio;
  final String _clientId;
  final String _clientSecret;
  final String _tmapAppKey;

  static const String _tmapPoiSearchUrl = 'https://apis.openapi.sk.com/tmap/pois';
  static const String _tmapWalkingUrl = 'https://apis.openapi.sk.com/tmap/routes/pedestrian';

  NaverMapApiService({
    required String clientId,
    required String clientSecret,
    required String tmapAppKey,
  })  : _clientId = clientId,
        _clientSecret = clientSecret,
        _tmapAppKey = tmapAppKey,
        _dio = Dio(BaseOptions());

  Future<(NLatLng, String)> searchGeocode(String query) async {
    final response = await _dio.get(
      _tmapPoiSearchUrl,
      queryParameters: {
        'version': '1',
        'searchKeyword': query,
        'count': '1',
        'resCoordType': 'WGS84GEO',
        'format': 'json'
      },
      options: Options(headers: {'appKey': _tmapAppKey}),
    );

    if (response.data['searchPoiInfo']['totalCount'] == "0") {
      throw Exception("검색 결과가 없습니다.");
    }

    final poi = response.data['searchPoiInfo']['pois']['poi'][0];

    // [수정된 부분]
    // poi['name']이 dynamic이라서 오류가 났던 것입니다.
    // toString()을 붙이거나, '??'를 써서 String임을 확실히 명시해야 합니다.
    final String name = poi['name']?.toString() ?? '장소';

    // 이제 name이 확실히 String이므로 오류가 사라집니다.
    return (
    NLatLng(double.parse(poi['noorLat']), double.parse(poi['noorLon'])),
    name
    );
  }

  Future<List<NLatLng>> findWalkingRoute(NLatLng start, NLatLng goal) async {
    final response = await _dio.get(
      _tmapWalkingUrl,
      queryParameters: {
        'version': '1', 'startX': start.longitude, 'startY': start.latitude,
        'endX': goal.longitude, 'endY': goal.latitude, 'startName': '출발', 'endName': '도착',
        'resCoordType': 'WGS84GEO', 'format': 'json'
      },
      options: Options(headers: {'appKey': _tmapAppKey}),
    );

    List<NLatLng> points = [];
    if (response.data['features'] != null) {
      for (var feature in response.data['features']) {
        final geometry = feature['geometry'];
        final coords = geometry['coordinates'] as List;
        if (geometry['type'] == 'LineString') {
          for (var point in coords) {
            points.add(NLatLng(point[1], point[0]));
          }
        } else if (geometry['type'] == 'Point') {
          points.add(NLatLng(coords[1], coords[0]));
        }
      }
    }
    return points;
  }
}