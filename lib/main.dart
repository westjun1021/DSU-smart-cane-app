// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [필수] 내장 진동(HapticFeedback) 사용을 위해 추가
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';
import 'package:dio/dio.dart';
// import 'package:vibration/vibration.dart'; <-- [삭제] 더 이상 필요 없음
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

  final TextEditingController _searchController = TextEditingController();
  NLatLng? _currentLocation;
  NLatLng? _destinationLocation;

  // 라이다 상태 변수
  bool isLidarOn = false;

  // 목적지 잠금 관련 변수
  bool _isDestinationLocked = false;
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
    _showSnackBar(
      "목적지가 잠겨있습니다. 해제하려면 지도 우측 상단을 빠르게 5번 탭하세요.",
      isError: true,
    );
  }

  void toggleLidar() {
    setState(() {
      isLidarOn = !isLidarOn;
    });

    if (isLidarOn) {
      print("라이다 센서 ON");
      _showSnackBar("라이다 센서가 활성화되었습니다.", isError: false);
      // [추가] 버튼 누를 때도 햅틱 반응
      HapticFeedback.lightImpact();
    } else {
      print("라이다 센서 OFF");
      _showSnackBar("라이다 센서가 비활성화되었습니다.", isError: false);
    }
  }

  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    print("네이버 지도 로딩 완료! (onMapReady)");
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        _showSnackBar("GPS 서비스가 비활성화되었습니다.", isError: true);
        return;
      }
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        _showSnackBar("위치 권한이 거부되었습니다.", isError: true);
        return;
      }
    }

    if (permissionGranted == PermissionStatus.granted) {
      _mapController?.setLocationTrackingMode(NLocationTrackingMode.follow);
      await _updateCurrentLocation();
    }
  }

  Future<void> _updateCurrentLocation() async {
    try {
      final locationData = await _location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _currentLocation =
            NLatLng(locationData.latitude!, locationData.longitude!);
      }
    } catch (e) {
      _showSnackBar("현재 위치를 가져오는 데 실패했습니다.", isError: true);
    }
  }

  Future<void> _searchDestination() async {
    if (_isDestinationLocked) {
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

      setState(() {
        _isDestinationLocked = true;
      });
      _showSnackBar("목적지 설정 완료. (수정 잠금됨)");

    } catch (e) {
      _showSnackBar("검색 실패: ${e.toString().split(': ').last}", isError: true);
    }
  }

  Future<void> _findPath() async {
    await _updateCurrentLocation();

    if (_currentLocation == null || _destinationLocation == null) {
      _showSnackBar("위치 정보를 확인하세요.", isError: true);
      return;
    }

    try {
      final pathPoints = await _apiService.findWalkingRoute(
        _currentLocation!,
        _destinationLocation!,
      );

      _mapController?.clearOverlays(type: NOverlayType.polylineOverlay);

      final polyline = NPolylineOverlay(
        id: 'path',
        coords: pathPoints,
        color: Colors.red,
        width: 5,
      );
      _mapController?.addOverlay(polyline);
      _mapController?.updateCamera(
          NCameraUpdate.fitBounds(NLatLngBounds.from(pathPoints)));

      _showSnackBar("보행자 경로 탐색에 성공했습니다.");
    } catch (e) {
      _showSnackBar("경로 탐색 실패: ${e.toString().split(': ').last}", isError: true);
    }
  }

  Future<void> _cancelPath() async {
    _mapController?.clearOverlays();
    _destinationLocation = null;
    _searchController.clear();

    setState(() {
      _isDestinationLocked = false;
    });

    _showSnackBar("경로가 취소되었습니다.");

    if (_currentLocation != null) {
      _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: _currentLocation!, zoom: 15));
    }
  }

  void _handleUnlockTap() {
    if (!_isDestinationLocked) return;

    final now = DateTime.now();
    _tapTimestamps
        .removeWhere((tap) => now.difference(tap) > _unlockTapDuration);
    _tapTimestamps.add(now);

    if (_tapTimestamps.length >= _unlockTapCount) {
      print("잠금 해제 제스처 성공!");
      _unlockDestination();
      _tapTimestamps.clear();
    }
  }

  Future<void> _unlockDestination() async {
    setState(() {
      _isDestinationLocked = false;
    });
    _showSnackBar("목적지 잠금이 해제되었습니다.");

    // [수정] 패키지 대신 내장 기능(HapticFeedback) 사용!
    // heavyImpact: 묵직한 진동 (알림용으로 적합)
    HapticFeedback.heavyImpact();

    // 더 강하게 알리고 싶다면 2번 울리게 할 수도 있습니다.
    // await Future.delayed(const Duration(milliseconds: 200));
    // HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          enabled: !_isDestinationLocked,
          decoration: InputDecoration(
            hintText:
            _isDestinationLocked ? '목적지가 잠겨있습니다' : '목적지를 검색하세요...',
            fillColor: Colors.white,
            filled: true,
            border: InputBorder.none,
          ),
          style: TextStyle(
            color: _isDestinationLocked ? Colors.grey : Colors.black,
          ),
          onSubmitted: (value) => _searchDestination(),
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _isDestinationLocked ? _showLockSnackbar : _searchDestination,
            color: _isDestinationLocked ? Colors.white54 : Colors.white,
          ),
          IconButton(
            icon: const Icon(Icons.directions_walk),
            onPressed: _findPath,
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
              initialCameraPosition: NCameraPosition(
                target: NLatLng(35.1661, 129.0725),
                zoom: 15,
              ),
              locationButtonEnable: true,
            ),
            onMapReady: _onMapReady,
          ),
          // 잠금 해제 제스처 영역 (우측 상단)
          Positioned(
            top: 0,
            right: 0,
            width: 100,
            height: 100,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleUnlockTap,
              child: Container(),
            ),
          ),
          // 라이다 버튼
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Center(
              child: GestureDetector(
                onTap: toggleLidar,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: isLidarOn ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isLidarOn ? Icons.sensors_off : Icons.sensors,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------
// API 서비스 클래스
// ------------------------------------------------------------------
class NaverMapApiService {
  final Dio _dio;
  final String _clientId;
  final String _clientSecret;
  final String _tmapAppKey;

  static const String _tmapPoiSearchUrl =
      'https://apis.openapi.sk.com/tmap/pois';
  static const String _tmapWalkingUrl =
      'https://apis.openapi.sk.com/tmap/routes/pedestrian';

  NaverMapApiService({
    required String clientId,
    required String clientSecret,
    required String tmapAppKey,
  })  : _clientId = clientId,
        _clientSecret = clientSecret,
        _tmapAppKey = tmapAppKey,
        _dio = Dio(BaseOptions());

  Future<(NLatLng, String)> searchGeocode(String query) async {
    try {
      final response = await _dio.get(
        _tmapPoiSearchUrl,
        queryParameters: {
          'version': '1',
          'searchKeyword': query,
          'count': '1',
          'resCoordType': 'WGS84GEO',
          'format': 'json',
        },
        options: Options(
          headers: {
            'appKey': _tmapAppKey,
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 &&
          response.data['searchPoiInfo'] != null) {
        final poiInfo = response.data['searchPoiInfo'];
        if (poiInfo['totalCount'] == "0") {
          throw Exception("검색 결과가 없습니다.");
        }
        final poi = poiInfo['pois']['poi'][0];
        final double lon = double.parse(poi['noorLon']);
        final double lat = double.parse(poi['noorLat']);
        final String name = poi['name'] ?? '이름 없는 장소';
        return (NLatLng(lat, lon), name);
      } else {
        throw Exception("검색 결과가 없습니다.");
      }
    } on DioException catch (e) {
      throw Exception(
          "Tmap POI API 호출 오류: ${e.response?.data?['error']?['message'] ?? e.message}");
    } catch (e) {
      throw Exception("Tmap POI 파싱 오류: ${e.toString()}");
    }
  }

  Future<List<NLatLng>> findWalkingRoute(NLatLng start, NLatLng goal) async {
    try {
      final response = await _dio.get(
        _tmapWalkingUrl,
        queryParameters: {
          'version': '1',
          'startX': start.longitude,
          'startY': start.latitude,
          'endX': goal.longitude,
          'endY': goal.latitude,
          'startName': '출발지',
          'endName': '도착지',
          'resCoordType': 'WGS84GEO',
          'format': 'json',
        },
        options: Options(
          headers: {
            'appKey': _tmapAppKey,
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['features'] != null) {
        final List<NLatLng> points = [];
        final features = response.data['features'] as List;

        for (var feature in features) {
          final geometry = feature['geometry'];
          final coords = geometry['coordinates'] as List;

          if (geometry['type'] == 'LineString') {
            for (var point in coords) {
              if (point is List && point.length >= 2) {
                points.add(NLatLng(point[1], point[0]));
              }
            }
          } else if (geometry['type'] == 'Point') {
            if (coords.length >= 2) {
              points.add(NLatLng(coords[1], coords[0]));
            }
          }
        }
        if (points.isEmpty) {
          throw Exception("경로를 찾았으나 유효한 좌표가 없습니다.");
        }
        return points;
      }
      throw Exception(
          "경로 탐색에 실패했습니다: ${response.data['error']?['message'] ?? '경로를 찾을 수 없습니다.'}");
    } on DioException catch (e) {
      throw Exception(
          "Tmap API 호출 오류: ${e.response?.data?['error']?['message'] ?? e.message}");
    } catch (e) {
      throw Exception("Tmap 데이터 파싱 오류: ${e.toString()}");
    }
  }
}