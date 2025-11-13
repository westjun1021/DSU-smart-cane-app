import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterNaverMap().init(
    clientId: '2o202x2rls',
    onAuthFailed: (error) {
      print('네이버 지도 인증 실패: $error');
    },
  );

  runApp(const NaverMapTestApp());
}

class NaverMapTestApp extends StatelessWidget {
  const NaverMapTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapPage(),
    );
  }
}

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('네이버 지도'),
        backgroundColor: Colors.green,
      ),
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: NLatLng(35.1661, 129.0725), // 동서대학교

            zoom: 15,
          ),
        ),
        onMapReady: (controller) {
          print("네이버 지도 로딩 완료! (onMapReady)");
        },
      ),
    );
  }
}
