import UIKit
import SceneKit
import ARKit
import AVFoundation
import AudioToolbox

class ViewController: UIViewController, ARSCNViewDelegate {

    /*
     ============================================================
     Smart Cane — Wide Drop-off Integrated (v3.8 Fixed)
     ============================================================
     [수정 사항]
     - String Interpolation 구문 내 불필요한 역슬래시(\) 제거 (컴파일 에러 해결)
     
     [기능 요약]
     - Wide drop-off: 좌/중/우 (y=0.65) 동시 감지
     - Baseline update: 발밑 (y=0.95) 에서만 기준점 학습
     - Distance Guard: 1.5m 이내만 감지
     ============================================================
    */

    // MARK: - UI / AR
    var sceneView: ARSCNView!

    // required hit test points (normalized -> actual in setup)
    var hitTestPoints: [CGPoint] = []
    var debugPoints: [UIView] = []    // visual markers
    var debugLabel: UILabel = UILabel()

    // MARK: - Feedback
    let synthesizer = AVSpeechSynthesizer()
    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
    let notificationFeedback = UINotificationFeedbackGenerator()

    // MARK: - Timing & stabilization
    var lastWarningTime: Date = Date(timeIntervalSince1970: 0)
    var lastScanTime: Date = Date(timeIntervalSince1970: 0)
    var dropOffFrameCount = 0
    var obstacleFrameCount = 0

    // MARK: - Tunables
    let scanInterval: TimeInterval = 0.08
    let emaAlpha: Float = 0.30
    var emaVerticalHeight: Float = 0.0

    let minFramesForDropOff = 2
    let minFramesForObstacle = 2

    // pitch for enabling drop-off behavior (near always on for cane)
    let pitchThresholdForDropOff: Float = -0.05

    // base sensitivity (meters)
    let baseDangerHeight: Float = 0.10

    // distance gating (meters) — detection only within this distance
    let maxDropOffCheckDistance: Float = 1.5

    // obstacle params
    let personHeightThreshold: Float = 1.2
    let personWidthThreshold: Float = 0.35
    let maxObstacleDistance: Float = 1.2
    let depthMatchTolerance: Float = 0.28

    // floor baseline (only updated from baseline probe)
    var knownFloorY: Float? = nil

    // Obstacle sample points (normalized screen coords)
    var obstacleSamplePointsNormalized: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.50),
        CGPoint(x: 0.3, y: 0.50),
        CGPoint(x: 0.7, y: 0.50),
        CGPoint(x: 0.35, y: 0.85),
        CGPoint(x: 0.65, y: 0.85)
    ]

    // Drop-off probes normalized
    var dropOffSamplePointsNormalized: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.65), // center
        CGPoint(x: 0.2, y: 0.65), // left wide
        CGPoint(x: 0.8, y: 0.65)  // right wide
    ]

    // MARK: - View lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupSceneView()
        setupAudio()
        impactFeedback.prepare()
        notificationFeedback.prepare()
        setupDebugOverlay()
        setupDebugLabel()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.speak("스마트 지팡이, 광각 단차 모드 시작.")
        }
    }

    func setupSceneView() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.autoenablesDefaultLighting = true
        view.addSubview(sceneView)
    }

    func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("오디오 설정 실패: \(error)")
        }
    }

    func setupDebugOverlay() {
        let w = view.bounds.width
        let h = view.bounds.height

        // Obstacles sample points (0..4)
        hitTestPoints = [
            CGPoint(x: w * 0.5, y: h * 0.5),
            CGPoint(x: w * 0.2, y: h * 0.5),
            CGPoint(x: w * 0.8, y: h * 0.5),
            CGPoint(x: w * 0.35, y: h * 0.85),
            CGPoint(x: w * 0.65, y: h * 0.85)
        ]

        // Baseline point (5)
        hitTestPoints.append(CGPoint(x: w * 0.5, y: h * 0.95))

        // Drop-off probes (6:center, 7:left, 8:right)
        hitTestPoints.append(CGPoint(x: w * 0.5, y: h * 0.65))
        hitTestPoints.append(CGPoint(x: w * 0.2, y: h * 0.65))
        hitTestPoints.append(CGPoint(x: w * 0.8, y: h * 0.65))

        for (i, p) in hitTestPoints.enumerated() {
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
            dot.center = p
            dot.layer.cornerRadius = 7
            dot.layer.borderWidth = 2
            dot.layer.borderColor = UIColor.white.cgColor

            if i == 5 { dot.backgroundColor = .yellow }          // baseline
            else if i >= 6 { dot.backgroundColor = .cyan }       // drop probes
            else { dot.backgroundColor = .gray.withAlphaComponent(0.6) } // obstacles

            view.addSubview(dot)
            debugPoints.append(dot)
        }
    }

    func setupDebugLabel() {
        debugLabel.frame = CGRect(x: 8, y: 40, width: view.bounds.width - 16, height: 180)
        debugLabel.numberOfLines = 0
        debugLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        debugLabel.textColor = .white
        debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        debugLabel.layer.cornerRadius = 8
        debugLabel.layer.masksToBounds = true
        view.addSubview(debugLabel)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.planeDetection = [.horizontal]
        sceneView.session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - Renderer loop
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if Date().timeIntervalSince(lastScanTime) < scanInterval { return }
        lastScanTime = Date()

        guard let currentFrame = sceneView.session.currentFrame else { return }
        let viewportSize = sceneView.bounds.size

        DispatchQueue.global(qos: .userInitiated).async {
            self.scanEnvironment(frame: currentFrame, viewportSize: viewportSize)
        }
    }

    // MARK: - Main detection pipeline (Wide Drop-off)
    func scanEnvironment(frame: ARFrame, viewportSize: CGSize) {
        let pitch = frame.camera.eulerAngles.x
        let isLookingDown = pitch < pitchThresholdForDropOff

        var currentFrameDropOff = false
        var obstacleDetected = false
        var debugText = ""

        if isLookingDown {
            // Baseline probe screen point (y = 0.95)
            let baselineScreen = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.95)

            var baseY: Float? = nil
            var detectedYs: [Float] = []

            // Raycast creations must be on main thread
            DispatchQueue.main.sync {
                // Baseline
                if let qBase = sceneView.raycastQuery(from: baselineScreen, allowing: .existingPlaneGeometry, alignment: .horizontal),
                   let rBase = sceneView.session.raycast(qBase).first {
                    baseY = Float(rBase.worldTransform.columns.3.y)
                }

                // Wide drop-off detection: left/center/right at y=0.65
                for np in dropOffSamplePointsNormalized {
                    let sp = CGPoint(x: np.x * viewportSize.width, y: np.y * viewportSize.height)
                    if let qDet = sceneView.raycastQuery(from: sp, allowing: .existingPlaneGeometry, alignment: .horizontal),
                       let rDet = sceneView.session.raycast(qDet).first {
                        let dist = distance(from: rDet, cameraTransform: frame.camera.transform)
                        if dist < maxDropOffCheckDistance {
                            detectedYs.append(Float(rDet.worldTransform.columns.3.y))
                        }
                    }
                }
            } // end main sync

            // Update baseline ONLY from baseline probe (y = 0.95)
            if let bY = baseY {
                if knownFloorY == nil {
                    knownFloorY = bY
                } else {
                    // gentle EMA to adapt slowly (protect against sudden drop)
                    knownFloorY = (knownFloorY! * (1.0 - emaAlpha)) + (bY * emaAlpha)
                }
            }

            // Determine max drop among detectedYs compared to knownFloorY
            if let curBase = knownFloorY {
                var maxDrop: Float = 0.0

                if !detectedYs.isEmpty {
                    for dY in detectedYs {
                        let drop = curBase - dY
                        if drop > maxDrop { maxDrop = drop }
                    }
                }

                // If raycast didn't produce dangerous drop, check depth fallback
                if detectedYs.isEmpty || maxDrop < baseDangerHeight {
                    if let sceneDepth = frame.sceneDepth {
                        let (isDepthDrop, depthMaxDrop) = checkWideDropOffWithDepth(frame: frame, depthMap: sceneDepth.depthMap, viewportSize: viewportSize)
                        if isDepthDrop {
                            maxDrop = max(maxDrop, depthMaxDrop)
                        }
                    }
                }

                // Apply EMA (fast rise, slow fall)
                if maxDrop > emaVerticalHeight {
                    emaVerticalHeight = (emaVerticalHeight * 0.5) + (maxDrop * 0.5)
                } else {
                    emaVerticalHeight = (emaVerticalHeight * 0.8) + (maxDrop * 0.2)
                }

                if emaVerticalHeight > baseDangerHeight {
                    currentFrameDropOff = true
                } else {
                    currentFrameDropOff = false
                }

                // [수정 완료] 역슬래시 제거
                debugText += "Base:\(String(format: "%.3f", curBase)) MaxDrop:\(String(format: "%.3f", maxDrop)) EMA:\(String(format: "%.3f", emaVerticalHeight))\n"
            } else {
                debugText += "Baseline N/A\n"
            }
        } else {
            debugText += "Pitch high (not looking down)\n"
        }

        // Obstacle detection (unchanged)
        if let sceneDepth = frame.sceneDepth {
            let (detected, dbg) = detectObstaclesWithDepth(frame: frame, depthMap: sceneDepth.depthMap, viewportSize: viewportSize)
            obstacleDetected = detected
            debugText += dbg
        } else {
            obstacleDetected = detectObstaclesFallback(frame: frame, viewportSize: viewportSize)
            debugText += "Fallback Obs\n"
        }

        // UI update on main thread
        DispatchQueue.main.async {
            self.updateUIAndFeedback(isDropOff: currentFrameDropOff, isObstacle: obstacleDetected, debugText: debugText)
        }
    }

    // MARK: - Depth fallback for wide drop-off
    // Returns (isDanger, maxDropInMeters)
    func checkWideDropOffWithDepth(frame: ARFrame, depthMap: CVPixelBuffer, viewportSize: CGSize) -> (Bool, Float) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // Use base at y=0.90 (near foot) for depth baseline
        let basePt = CGPoint(x: viewportSize.width * 0.5, y: viewportSize.height * 0.90)
        guard let dBase = sampleMedianDepth(screenPoint: basePt, depthMap: depthMap, frame: frame, viewportSize: viewportSize, kernel: 1) else {
            return (false, 0.0)
        }

        var maxDepthDiff: Float = 0.0
        var dangerCount = 0

        for np in dropOffSamplePointsNormalized {
            let sp = CGPoint(x: np.x * viewportSize.width, y: np.y * viewportSize.height)
            if let dVal = sampleMedianDepth(screenPoint: sp, depthMap: depthMap, frame: frame, viewportSize: viewportSize, kernel: 1) {
                // Only consider points within distance gating (we approximate depth map value as distance)
                if dVal < maxDropOffCheckDistance {
                    let diff = dBase - dVal
                    // Note: Depth value is distance from camera.
                    // If forward point (dVal) is significantly farther than baseline (dBase) + geometry, it might be a drop.
                    // However, simplified logic: check local depth consistency.
                    // Here we check: if dVal (forward) - dBase (near) > threshold
                    let forwardFar = dVal - dBase
                   
                    if forwardFar > maxDepthDiff { maxDepthDiff = forwardFar }
                   
                    // large forward difference indicates deep drop (threshold 0.6m)
                    if forwardFar > 0.6 {
                        dangerCount += 1
                    }
                }
            }
        }

        return (dangerCount > 0, maxDepthDiff)
    }

    // MARK: - UI & feedback
    func updateUIAndFeedback(isDropOff: Bool, isObstacle: Bool, debugText: String) {
        // Update drop probe colors (6,7,8)
        if debugPoints.count > 8 {
            let color: UIColor = isDropOff ? .red : .cyan
            debugPoints[6].backgroundColor = color
            debugPoints[7].backgroundColor = color
            debugPoints[8].backgroundColor = color
        }

        debugLabel.text = debugText

        if isDropOff { dropOffFrameCount += 1 } else { dropOffFrameCount = 0 }
        if isObstacle { obstacleFrameCount += 1 } else { obstacleFrameCount = 0 }

        let canWarn = Date().timeIntervalSince(lastWarningTime) > 1.5

        if canWarn {
            if dropOffFrameCount >= minFramesForDropOff {
                triggerWarning(type: .dropOff)
                dropOffFrameCount = 0
            } else if obstacleFrameCount >= minFramesForObstacle {
                triggerWarning(type: .obstacle)
                obstacleFrameCount = 0
            }
        }
    }

    // MARK: - Obstacle detection (kept from v3.x)
    func detectObstaclesWithDepth(frame: ARFrame, depthMap: CVPixelBuffer, viewportSize: CGSize) -> (Bool, String) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        var hitVotes = 0
        var debugLines: [String] = []
        var pointColors: [Int: UIColor] = [:]

        for (idx, np) in obstacleSamplePointsNormalized.enumerated() {
            let screenPoint = CGPoint(x: np.x * viewportSize.width, y: np.y * viewportSize.height)

            var rayResult: ARRaycastResult?
            DispatchQueue.main.sync {
                if let q = sceneView.raycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any) {
                    rayResult = sceneView.session.raycast(q).first
                }
            }

            guard let result = rayResult else {
                pointColors[idx] = .lightGray
                continue
            }

            let rayDist = distance(from: result, cameraTransform: frame.camera.transform)
            if rayDist > maxObstacleDistance {
                pointColors[idx] = .lightGray
                continue
            }

            guard let depthAtPoint = depthValueAt(screenPoint: screenPoint, depthMap: depthMap, frame: frame, viewportSize: viewportSize) else {
                pointColors[idx] = .lightGray
                continue
            }

            let depthDiff = fabsf(depthAtPoint - rayDist)
            if depthDiff < depthMatchTolerance {
                let estWidth = estimateWidthAt(screenPoint: screenPoint, depthMap: depthMap, frame: frame, viewportSize: viewportSize, sampleRadiusPx: 12, stride: 2)
                let estHeight = estimateHeightOfHit(result: result, cameraTransform: frame.camera.transform)
                let isPerson = isLikelyPerson(height: estHeight, width: estWidth)

                if !isPerson {
                    hitVotes += 1
                    pointColors[idx] = .red
                } else {
                    pointColors[idx] = .green
                }

                // [수정 완료] 역슬래시 제거
                debugLines.append("pt\(idx) d:\(String(format: "%.2f", depthAtPoint)) r:\(String(format: "%.2f", rayDist)) w:\(String(format: "%.2f", estWidth)) h:\(String(format: "%.2f", estHeight)) P:\(isPerson)")
            } else {
                pointColors[idx] = .blue
            }
        }

        DispatchQueue.main.async {
            for (idx, color) in pointColors {
                if idx < self.debugPoints.count {
                    self.debugPoints[idx].backgroundColor = color
                }
            }
        }

        let dbg = debugLines.joined(separator: "\n")
        return (hitVotes >= 2, dbg)
    }

    func detectObstaclesFallback(frame: ARFrame, viewportSize: CGSize) -> Bool {
        var hitVotes = 0
        var pointColors: [Int: UIColor] = [:]

        for (idx, np) in obstacleSamplePointsNormalized.enumerated() {
            let screenPoint = CGPoint(x: np.x * viewportSize.width, y: np.y * viewportSize.height)

            var rayResult: ARRaycastResult?
            DispatchQueue.main.sync {
                if let q = sceneView.raycastQuery(from: screenPoint, allowing: .estimatedPlane, alignment: .any) {
                    rayResult = sceneView.session.raycast(q).first
                }
            }

            if let r = rayResult {
                let dist = distance(from: r, cameraTransform: frame.camera.transform)
                let estHeight = estimateHeightOfHit(result: r, cameraTransform: frame.camera.transform)
                let isPerson = estHeight > personHeightThreshold
                if !isPerson && dist < maxObstacleDistance {
                    hitVotes += 1
                    pointColors[idx] = .red
                } else {
                    pointColors[idx] = .green
                }
            } else {
                pointColors[idx] = .lightGray
            }
        }

        DispatchQueue.main.async {
            for (idx, color) in pointColors {
                if idx < self.debugPoints.count {
                    self.debugPoints[idx].backgroundColor = color
                }
            }
        }
        return hitVotes >= 2
    }

    // MARK: - Depth helpers (displayTransform aware)
    func sampleMedianDepth(screenPoint: CGPoint, depthMap: CVPixelBuffer, frame: ARFrame, viewportSize: CGSize, kernel: Int = 1) -> Float? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let normalized = CGPoint(x: screenPoint.x / viewportSize.width, y: screenPoint.y / viewportSize.height)
        let inv = frame.displayTransform(for: .portrait, viewportSize: viewportSize).inverted()
        let tex = normalized.applying(inv)
        let cx = Int(tex.x * CGFloat(depthWidth))
        let cy = Int(tex.y * CGFloat(depthHeight))
        if cx < 0 || cy < 0 || cx >= depthWidth || cy >= depthHeight { return nil }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        var vals: [Float] = []

        for dy in -kernel...kernel {
            for dx in -kernel...kernel {
                let px = cx + dx
                let py = cy + dy
                if px < 0 || py < 0 || px >= depthWidth || py >= depthHeight { continue }
                let offset = py * rowBytes + px * MemoryLayout<Float32>.size
                let v = base.advanced(by: offset).bindMemory(to: Float32.self, capacity: 1).pointee
                if v.isFinite && v > 0 { vals.append(Float(v)) }
            }
        }
        if vals.isEmpty { return nil }
        vals.sort()
        return vals[vals.count / 2]
    }

    func depthValueAt(screenPoint: CGPoint, depthMap: CVPixelBuffer, frame: ARFrame, viewportSize: CGSize) -> Float? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let normalized = CGPoint(x: screenPoint.x / viewportSize.width, y: screenPoint.y / viewportSize.height)
        let inv = frame.displayTransform(for: .portrait, viewportSize: viewportSize).inverted()
        let tex = normalized.applying(inv)
        let cx = Int(tex.x * CGFloat(depthWidth))
        let cy = Int(tex.y * CGFloat(depthHeight))
        if cx < 0 || cy < 0 || cx >= depthWidth || cy >= depthHeight { return nil }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let offset = cy * rowBytes + cx * MemoryLayout<Float32>.size
        let v = base.advanced(by: offset).bindMemory(to: Float32.self, capacity: 1).pointee
        return (v.isFinite && v > 0) ? Float(v) : nil
    }

    // MARK: - Width/Height helpers
    func estimateWidthAt(screenPoint: CGPoint, depthMap: CVPixelBuffer, frame: ARFrame, viewportSize: CGSize, sampleRadiusPx: Int = 12, stride: Int = 2) -> Float {
        guard let centerDepth = depthValueAt(screenPoint: screenPoint, depthMap: depthMap, frame: frame, viewportSize: viewportSize) else { return 0.0 }
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let normalized = CGPoint(x: screenPoint.x / viewportSize.width, y: screenPoint.y / viewportSize.height)
        let inv = frame.displayTransform(for: .portrait, viewportSize: viewportSize).inverted()
        let tex = normalized.applying(inv)
        var centerPx = Int(tex.x * CGFloat(depthWidth))
        let centerPy = Int(tex.y * CGFloat(depthHeight))
        if centerPx < 0 { centerPx = 0 }
        if centerPx >= depthWidth { centerPx = depthWidth - 1 }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return 0.0 }
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        let tolerance: Float = 0.20
        var leftPx = centerPx
        var rightPx = centerPx

        var px = centerPx
        while px > max(0, centerPx - sampleRadiusPx) {
            let offset = centerPy * rowBytes + px * MemoryLayout<Float32>.size
            let val = base.advanced(by: offset).bindMemory(to: Float32.self, capacity: 1).pointee
            if !val.isFinite || val <= 0 || fabsf(val - centerDepth) > tolerance { break }
            leftPx = px
            px -= stride
        }

        px = centerPx
        while px < min(depthWidth - 1, centerPx + sampleRadiusPx) {
            let offset = centerPy * rowBytes + px * MemoryLayout<Float32>.size
            let val = base.advanced(by: offset).bindMemory(to: Float32.self, capacity: 1).pointee
            if !val.isFinite || val <= 0 || fabsf(val - centerDepth) > tolerance { break }
            rightPx = px
            px += stride
        }

        let pixelSpan = Float(max(1, rightPx - leftPx))
        let cam = frame.camera
        let imgRes = cam.imageResolution
        let scaleX = CGFloat(depthWidth) / CGFloat(imgRes.width)
        let fx = cam.intrinsics[0][0]
        let fxScaled = Float(fx) * Float(scaleX)
        let widthMeters = centerDepth * (pixelSpan / fxScaled)
        return widthMeters
    }

    func estimateHeightOfHit(result: ARRaycastResult, cameraTransform: simd_float4x4) -> Float {
        let hitY = Float(result.worldTransform.columns.3.y)
        if let floor = knownFloorY {
            return hitY - floor
        } else {
            let camY = Float(cameraTransform.columns.3.y)
            return camY - hitY
        }
    }

    func isLikelyPerson(height: Float, width: Float) -> Bool {
        if height > personHeightThreshold { return true }
        if height > 0.8 && width > personWidthThreshold { return true }
        if width > 0.55 && height > 0.5 { return true }
        return false
    }

    func distance(from result: ARRaycastResult, cameraTransform: simd_float4x4) -> Float {
        let objectPos = simd_make_float3(result.worldTransform.columns.3)
        let cameraPos = simd_make_float3(cameraTransform.columns.3)
        return simd_distance(objectPos, cameraPos)
    }

    // MARK: - Warning & speech
    enum WarningType { case obstacle, dropOff }

    func triggerWarning(type: WarningType) {
        lastWarningTime = Date()
        switch type {
        case .obstacle:
            impactFeedback.impactOccurred()
            speak("전방 장애물")
        case .dropOff:
            notificationFeedback.notificationOccurred(.error)
            AudioServicesPlaySystemSound(1011)
            speak("단차 주의")
        }
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        u.rate = 0.5
        synthesizer.speak(u)
    }
}
