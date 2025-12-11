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

