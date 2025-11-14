// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:location/location.dart';
import 'package:dio/dio.dart';
import 'api_keys.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  //최신 초기화 방식
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
  final Location location = Location();
  NaverMapController? _mapController;

  final Dio _dio = Dio();
  final String _clientId = apiGwClientId;
  final String _clientSecret = apiGwClientSecret;

  final TextEditingController _searchController = TextEditingController();
  NLatLng? _currentLocation;
  NLatLng? _destinationLocation;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        print("GPS 서비스가 비활성화되어 있습니다.");
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        print("위치 정보 권한이 거부되었습니다.");
        return;
      }
    }

    if (permissionGranted == PermissionStatus.granted) {
      print("위치 권한 승인됨. 추적 모드 활성화.");
      _mapController?.setLocationTrackingMode(NLocationTrackingMode.follow);
      final locationData = await location.getLocation();
      if (locationData.latitude != null) {
        _currentLocation =
            NLatLng(locationData.latitude!, locationData.longitude!);
      }
    }
  }

  // '검색' 버튼을 누르면 실행될 '지오코딩' 함수
  Future<void> _searchDestination() async {
    final String query = _searchController.text;
    if (query.isEmpty) {
      print("검색어가 없습니다.");
      return;
    }

    // 문제 url
    const String url =
        'https://naveropenapi.apigw.ntruss.com/map-geocode/v2/geocode';
    // [수정필요]

    try {
      final response = await _dio.get(
        url,
        queryParameters: {'query': query},
        options: Options(
          headers: {
            'X-NCP-APIGW-API-KEY-ID': _clientId,
            'X-NCP-APIGW-API-KEY': _clientSecret,
            'Accept': 'application/json', // (이전 단계에서 헤더)
          },
        ),
      );

      if (response.statusCode == 200 &&
          response.data['addresses'] != null &&
          (response.data['addresses'] as List).isNotEmpty) {
        final address = response.data['addresses'][0];
        final double lon = double.parse(address['x']);
        final double lat = double.parse(address['y']);

        _destinationLocation = NLatLng(lat, lon);
        print("목적지 검색 성공: ${address['roadAddress']} ($lat, $lon)");

        _mapController?.clearOverlays();

        // (마커 추가 - assets/marker.png 필요)
        final marker = NMarker(
          id: 'destination',
          position: _destinationLocation!,
          icon: const NOverlayImage.fromAssetImage('assets/marker.png'),
        );
        _mapController?.addOverlay(marker);

        _mapController?.updateCamera(NCameraUpdate.scrollAndZoomTo(
            target: _destinationLocation!, zoom: 15));
      } else {
        print("검색 결과 없음: ${response.data['errorMessage']}");
      }
    } on DioException catch (e) {
      print("지오코딩 API 호출 오류: ${e.response?.data}");
    }
  }

  //길찾기 함수
  Future<void> _findPath() async {
    if (_currentLocation == null) {
      print("현재 위치를 찾을 수 없습니다.");
      return;
    }

    if (_destinationLocation == null) {
      print("목적지가 설정되지 않았습니다. 먼저 검색하세요.");
      return;
    }

    const String url =
        'https://maps.apigw.ntruss.com/map-direction-15/v1/driving';

    try {
      final response = await _dio.get(
        url,
        queryParameters: {
          'start':
              '${_currentLocation!.longitude},${_currentLocation!.latitude}',
          'goal':
              '${_destinationLocation!.longitude},${_destinationLocation!.latitude}',
          'option': 'traavoidcaronly',
        },
        options: Options(
          headers: {
            'X-NCP-APIGW-API-KEY-ID': _clientId,
            'X-NCP-APIGW-API-KEY': _clientSecret,
          },
        ),
      );

      if (response.statusCode == 200 &&
          response.data['route'] != null &&
          response.data['route']['traavoidcaronly'] != null) {
        _mapController?.clearOverlays(type: NOverlayType.polylineOverlay);

        final List<dynamic> path =
            response.data['route']['traavoidcaronly'][0]['path'];
        final List<NLatLng> points =
            path.map((point) => NLatLng(point[1], point[0])).toList();

        final polyline = NPolylineOverlay(
          id: 'path',
          coords: points,
          color: Colors.red,
          width: 5,
        );
        _mapController?.addOverlay(polyline);

        _mapController
            ?.updateCamera(NCameraUpdate.fitBounds(NLatLngBounds.from(points)));
        print("경로 탐색 성공!");
      } else {
        print("경로 탐색 실패: ${response.data['message']}");
      }
    } on DioException catch (e) {
      print("API 호출 오류: ${e.response?.data}");
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
        ],
      ),
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(35.1661, 129.0725),
            zoom: 15,
          ),
          locationButtonEnable: true,
        ),
        onMapReady: (controller) {
          _mapController = controller;
          print("네이버 지도 로딩 완료! (onMapReady)");
        },
      ),
    );
  }
}
