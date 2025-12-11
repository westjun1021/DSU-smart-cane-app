# 🦯 DSU Smart Cane App  
**AR 기반 실내 장애물 감지 및 보행 보조 시스템**

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS-blue?logo=apple" />
  <img src="https://img.shields.io/badge/Language-Swift-orange?logo=swift" />
  <img src="https://img.shields.io/badge/Engine-ARKit%2FSceneKit-lightgrey?logo=apple" />
</p>

---

## 📌 프로젝트 개요  
**DSU Smart Cane App**은 시각장애인의 안전한 실내 보행을 돕기 위해  
카메라 기반 AR 기술을 활용하여 **단차(계단), 낭떠러지, 전방 장애물**을 감지하고  
음성 안내 및 진동 피드백을 제공하는 스마트 보조 시스템입니다.

기존 초음파/라이더 기반 지팡이는 **전면 장애물 감지**에 한정되지만,  
본 프로젝트는 **ARKit의 깊이 인식 + SceneKit 공간 매핑**을 활용하여  
단차나 바닥 변화까지 감지할 수 있다는 점에서 큰 차별성을 가집니다.

---

## 🎯 주요 기능

### ✔ 1. **AR 기반 공간 인식**
- ARKit의 `ARSCNView` + SceneKit 기반 실시간 공간 매핑  
- 바닥 평면 감지(Plane Detection)  
- 특정 영역에서 높이 변화 감지  

### ✔ 2. **단차(낭떠러지) 감지**
- 바닥 깊이가 일정 threshold 이상 변화하면 **낭떠러지로 판정**  
- 시각장애인 보행 시 가장 위험한 요소를 우선 탐지  
- "앞에 단차가 있습니다!" 음성 안내

### ✔ 3. **전방 장애물 감지**
- 카메라 프레임 기반 전방 객체와의 거리 계산  
- 사람은 장애물로 처리하지 않도록 필터 적용  
- 일정 거리 이내 접근 시 진동 + 음성 경고

### ✔ 4. **음성 안내 시스템 (TTS)**
- 방향 및 위험 요소를 실시간 음성 출력  
- Swift AVFoundation 기반 TTS

### ✔ 5. **Haptic(진동) 피드백**
- iPhone haptic feedback API 사용  
- 장애물 근접 시 강도 조절 진동 출력

---

## 🧠 시스템 구조

Camera Input
↓
ARKit Depth / Scene Understanding
↓
Depth Processing & Floor Analysis
↓
Obstacle/Drop-off Detection
↓
Voice Output + Haptic Feedback


---

## 🛠 사용 기술

### **📱 iOS / Swift**
- UIKit  
- SceneKit  
- ARKit (Depth API, Plane Detection)  
- AVFoundation (TTS)  

### **🔍 센서 기반 알고리즘**
- 실시간 깊이 기반 Drop-off 감지  
- 전방 장애물 필터링  
- Raycasting 기반 충돌 거리 계산  

---

## 📸 시연 이미지 (추가 예정)
여기에 아래와 같은 스크린샷 또는 이미지/GIF를 넣으면 포트폴리오 점수 증가

- AR Scene 화면  
- 단차 감지 순간  
- 장애물 감지 알림  
- 앱 구동 화면  

원하시면 제가 **샘플 UI Mockup 이미지**도 만들어드릴 수 있습니다.

---

## 🧩 코드 구조

/DSU-smart-cane-app
├── ViewController.swift # AR Scene + 감지 알고리즘
├── AudioManager.swift # 음성 안내
├── HapticManager.swift # 진동 제어
├── DepthProcessor.swift # 깊이 분석 알고리즘
└── Utils/ # 공용 함수


---

## 🚀 실행 방법

1. iPhone(XR 이상)과 Xcode 필요  
2. 프로젝트 열기  
3. 실기기 연결 후 → **Run**  
4. 카메라를 천천히 이동하며 공간 매핑  
5. 단차 또는 전방 장애물을 향해 이동하면  
   → 음성 + 진동 안내 출력

---

## 📌 향후 개선 목표

- LiDAR 장착 기종에서 더 정밀한 공간 매핑 적용  
- 보행 경로 안내 기능 추가  
- 바닥 패턴(미끄럼/카펫/경사) 분석  
- 실외 GPS 기반 안내 기능 연동

---

- Computer Science Major  
- Vision / AR / Assistive Tech Developer  

---

## 📄 License  
MIT License  
