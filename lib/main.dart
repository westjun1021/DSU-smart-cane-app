// lib/main.dart (Tmap 키워드 검색 기능으로 교체 완료)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';
import 'package:dio/dio.dart';
import 'api_keys.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [키 1: 지도 SDK 인증]
  await FlutterNaverMap().init(
    clientId: naverMapClientId, // (api_keys.dart의 변수)
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

  @override
  void initState() {
    super.initState();
    // [키 2: API Gateway 인증]
    // NaverMapApiService 생성자에 tmapAppKey 전달
    _apiService = NaverMapApiService(
      clientId: apiGwClientId,
      clientSecret: apiGwClientSecret,
      tmapAppKey: tmapAppKey, // api_keys.dart에 추가한 Tmap 키
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // 사용자에게 피드백을 주기 위한 SnackBar 함수
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return; // context가 유효한지 확인
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // NaverMap이 준비되면 호출될 콜백
  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    print("네이버 지도 로딩 완료! (onMapReady)");
    _initializeLocation(); // 지도가 준비된 후 위치 초기화 시작
  }

  // 위치 권한 요청 및 초기 위치 설정
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
      print("위치 권한 승인됨. 추적 모드 활성화.");
      _mapController?.setLocationTrackingMode(NLocationTrackingMode.follow);
      await _updateCurrentLocation(); // 현재 위치 업데이트
    }
  }

  // 현재 위치를 업데이트하는 별도 함수
  Future<void> _updateCurrentLocation() async {
    try {
      final locationData = await _location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _currentLocation =
            NLatLng(locationData.latitude!, locationData.longitude!);
        print("현재 위치 업데이트: $_currentLocation");
      }
    } catch (e) {
      print("현재 위치를 가져오는 데 실패: $e");
      _showSnackBar("현재 위치를 가져오는 데 실패했습니다.", isError: true);
    }
  }

  // 검색함수 (API 서비스 사용)
  Future<void> _searchDestination() async {
    final String query = _searchController.text;
    if (query.isEmpty) {
      _showSnackBar("검색어를 입력하세요.", isError: true);
      return;
    }

    // 키보드 숨기기
    FocusScope.of(context).unfocus();

    try {
      // ▼▼▼ Tmap POI API가 (좌표, 장소명)을 반환합니다 ▼▼▼
      final (destination, placeName) = await _apiService.searchGeocode(query);

      _destinationLocation = destination;
      print("목적지 검색 성공: $placeName ($destination)");
      _showSnackBar("목적지 검색 성공: $placeName"); // 도로명 대신 장소명 표시

      _mapController?.clearOverlays(); // 기존 오버레이(경로, 마커) 삭제
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
    } catch (e) {
      print("Tmap POI API 호출 오류: $e");
      _showSnackBar("검색 실패: $e", isError: true);
    }
  }

  // 길찾기함수 (API 서비스 사용)
  Future<void> _findPath() async {
    // 길찾기 전 항상 현재 위치를 최신화
    await _updateCurrentLocation();

    if (_currentLocation == null) {
      _showSnackBar("현재 위치를 찾을 수 없습니다. GPS를 확인하세요.", isError: true);
      return;
    }
    if (_destinationLocation == null) {
      _showSnackBar("목적지가 설정되지 않았습니다. 먼저 검색하세요.", isError: true);
      return;
    }

    try {
      final pathPoints = await _apiService.findWalkingRoute(
        _currentLocation!,
        _destinationLocation!,
      );

      _mapController?.clearOverlays(
          type: NOverlayType.polylineOverlay); // 기존 경로 삭제

      final polyline = NPolylineOverlay(
        id: 'path',
        coords: pathPoints,
        color: Colors.red,
        width: 5,
      );
      _mapController?.addOverlay(polyline);
      // 경로가 잘 보이도록 카메라 범위를 조절
      _mapController?.updateCamera(
          NCameraUpdate.fitBounds(NLatLngBounds.from(pathPoints)));

      print("보행자 경로 탐색 성공!");
      _showSnackBar("보행자 경로 탐색에 성공했습니다.");
    } catch (e) {
      print("API 호출 오류: $e");
      _showSnackBar("경로 탐색 실패: $e", isError: true);
    }
  }

  // '경로 취소' 함수
  Future<void> _cancelPath() async {
    _mapController?.clearOverlays(); // 모든 오버레이 (마커, 경로) 삭제
    _destinationLocation = null;
    _searchController.clear();

    print("경로 및 마커가 삭제되었습니다.");
    _showSnackBar("경로가 취소되었습니다.");

    // 카메라를 현재 위치로 이동
    if (_currentLocation != null) {
      _mapController?.updateCamera(
          NCameraUpdate.scrollAndZoomTo(target: _currentLocation!, zoom: 15));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            hintText: '목적지를 검색하세요...',
            fillColor: Colors.white,
            filled: true,
            border: InputBorder.none,
          ),
          style: const TextStyle(color: Colors.black),
          onSubmitted: (value) => _searchDestination(), // 엔터키로 검색
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _searchDestination,
          ),
          IconButton(
            icon: const Icon(Icons.directions_walk),
            onPressed: _findPath,
          ),
          IconButton(
            icon: const Icon(Icons.cancel), // 취소 아이콘
            onPressed: _cancelPath, // _cancelPath 함수 호출
          ),
        ],
      ),
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(35.1661, 129.0725), // 부산 어딘가 (초기 위치)
            zoom: 15,
          ),
          locationButtonEnable: true, // 현위치 버튼 표시
        ),
        onMapReady: _onMapReady, // 맵 준비 완료 시 콜백 지정
      ),
    );
  }
}

// ------------------------------------------------------------------
// [수정] Tmap POI(키워드 검색) + Tmap 보행자 경로 API 서비스
// ------------------------------------------------------------------
class NaverMapApiService {
  final Dio _dio;
  final String _clientId; // Naver (현재 미사용)
  final String _clientSecret; // Naver (현재 미사용)
  final String _tmapAppKey; // Tmap (검색, 경로 둘 다 사용)

  // ▼▼▼ [변경] Tmap POI 검색 API 주소 ▼▼▼
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
        _dio = Dio(BaseOptions(
            // 기본 헤더가 더 이상 필요 없으므로 제거 (각 API 호출 시 개별 설정)
            ));

  // ▼▼▼ [대규모 수정] Naver Geocoding -> Tmap POI 키워드 검색으로 교체 ▼▼▼
  /// [Search] (Tmap POI) 키워드로 장소 검색
  Future<(NLatLng, String)> searchGeocode(String query) async {
    try {
      final response = await _dio.get(
        _tmapPoiSearchUrl,
        queryParameters: {
          'version': '1',
          'searchKeyword': query, // 검색할 키워드
          'count': '1', // 가장 정확한 1개의 결과만 받기
          'resCoordType': 'WGS84GEO', // NLatLng과 호환되는 좌표계
          'format': 'json',
        },
        options: Options(
          headers: {
            'appKey': _tmapAppKey, // Tmap 앱 키
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 &&
          response.data['searchPoiInfo'] != null) {
        final poiInfo = response.data['searchPoiInfo'];

        // ▼▼▼ [수정] totalCount는 String일 수 있으므로 비교 수정 ▼▼▼
        if (poiInfo['totalCount'] == "0") {
          throw Exception("검색 결과가 없습니다.");
        }

        final poi = poiInfo['pois']['poi'][0];

        // Tmap API는 좌표를 String으로 줍니다.
        final double lon = double.parse(poi['noorLon']);
        final double lat = double.parse(poi['noorLat']);

        // Tmap은 'name'(장소명)을 반환합니다. 주소보다 이게 더 직관적입니다.
        final String name = poi['name'] ?? '이름 없는 장소';

        return (NLatLng(lat, lon), name); // (좌표, 장소명) 반환
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

  /// [Directions] (Tmap 보행자) 경로 탐색
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
            'appKey': _tmapAppKey, // Tmap 앱 키
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
                points.add(NLatLng(point[1], point[0])); // Tmap (lng, lat)
              }
            }
          } else if (geometry['type'] == 'Point') {
            if (coords.length >= 2) {
              points.add(NLatLng(coords[1], coords[0])); // Tmap (lng, lat)
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
