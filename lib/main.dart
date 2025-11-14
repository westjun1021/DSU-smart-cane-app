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
    // API 서비스 클래스를 초기화합니다.
    _apiService = NaverMapApiService(
      clientId: apiGwClientId,
      clientSecret: apiGwClientSecret,
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
    if (!mounted) return;
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

  //검색함수 (API 서비스 사용)
  Future<void> _searchDestination() async {
    final String query = _searchController.text;
    if (query.isEmpty) {
      _showSnackBar("검색어를 입력하세요.", isError: true);
      return;
    }

    // 키보드 숨기기
    FocusScope.of(context).unfocus();

    try {
      final (destination, address) = await _apiService.searchGeocode(query);

      _destinationLocation = destination;
      print("목적지 검색 성공: $address ($destination)");
      _showSnackBar("목적지 검색 성공: $address");

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
      print("지오코딩 API 호출 오류: $e");
      _showSnackBar("검색 실패: $e", isError: true);
    }
  }

  // '길찾기' 함수 (API 서비스 사용)
  Future<void> _findPath() async {
    // 길찾기 전 항상 현재 위치를 최신화합니다.
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
      final pathPoints = await _apiService.findDrivingRoute(
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

      print("경로 탐색 성공!");
      _showSnackBar("경로 탐색에 성공했습니다.");
    } catch (e) {
      print("API 호출 오류: $e");
      _showSnackBar("경로 탐색 실패: $e", isError: true);
    }
  }

  //경로 취소
  Future<void> _cancelPath() async {
    _mapController?.clearOverlays(); // 모든 오버레이 (마커, 경로) 삭제
    _destinationLocation = null;
    _searchController.clear();

    print("경로 및 마커가 삭제되었습니다.");
    _showSnackBar("경로가 취소되었습니다.");

    //카메라를 현재 위치로 이동
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
          onSubmitted: (value) => _searchDestination(),
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
            onPressed: _cancelPath,
          ),
        ],
      ),
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(35.1661, 129.0725), //초기 위치
            zoom: 15,
          ),
          locationButtonEnable: true, //현위치 버튼 표시
        ),
        onMapReady: _onMapReady, // 맵 준비 완료 시 콜백 지정
      ),
    );
  }
}

// ------------------------------------------------------------------
// API 통신을 전담하는 서비스 클래스 분리
// ------------------------------------------------------------------
class NaverMapApiService {
  final Dio _dio;
  final String _clientId;
  final String _clientSecret;

  // API 엔드포인트 URL
  static const String _geocodeUrl =
      'https://maps.apigw.ntruss.com/map-geocode/v2/geocode';
  static const String _directionsUrl =
      'https://maps.apigw.ntruss.com/map-direction-15/v1/driving';

  NaverMapApiService({
    required String clientId,
    required String clientSecret,
  })  : _clientId = clientId,
        _clientSecret = clientSecret,
        _dio = Dio(BaseOptions(
          headers: {
            'X-NCP-APIGW-API-KEY-ID': clientId,
            'X-NCP-APIGW-API-KEY': clientSecret,
            'Accept': 'application/json',
          },
        ));

  /// [Geocoding] 주소 검색
  Future<(NLatLng, String)> searchGeocode(String query) async {
    try {
      final response = await _dio.get(
        _geocodeUrl,
        queryParameters: {'query': query},
      );

      if (response.statusCode == 200 &&
          response.data['addresses'] != null &&
          (response.data['addresses'] as List).isNotEmpty) {
        final address = response.data['addresses'][0];
        final double lon = double.parse(address['x']);
        final double lat = double.parse(address['y']);
        final String roadAddress = address['roadAddress'] ?? '주소 정보 없음';

        return (NLatLng(lat, lon), roadAddress);
      } else {
        throw Exception(
            "검색 결과가 없습니다: ${response.data['errorMessage'] ?? '알 수 없는 오류'}");
      }
    } on DioException catch (e) {
      throw Exception(
          "API 호출 오류: ${e.response?.data?['errorMessage'] ?? e.message}");
    }
  }

  /// [Directions] 경로 탐색
  Future<List<NLatLng>> findDrivingRoute(NLatLng start, NLatLng goal) async {
    try {
      final response = await _dio.get(
        _directionsUrl,
        queryParameters: {
          'start': '${start.longitude},${start.latitude}',
          'goal': '${goal.longitude},${goal.latitude}',
          'option': 'traavoidcaronly', // 자동차 회피 경로 (보행자 옵션이 없어 최선)
        },
      );

      if (response.statusCode == 200 &&
          response.data['route'] != null &&
          response.data['route']['traavoidcaronly'] != null) {
        final List<dynamic> path =
            response.data['route']['traavoidcaronly'][0]['path'];
        final List<NLatLng> points =
            path.map((point) => NLatLng(point[1], point[0])).toList();

        return points;
      } else {
        throw Exception(
            "경로 탐색에 실패했습니다: ${response.data['message'] ?? '알 수 없는 오류'}");
      }
    } on DioException catch (e) {
      throw Exception(
          "API 호출 오류: ${e.response?.data?['message'] ?? e.message}");
    }
  }
}
