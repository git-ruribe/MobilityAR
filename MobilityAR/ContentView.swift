//
//  ContentView.swift
//  MobilityAR
//
//  Created by Rafael Uribe on 16/03/25.
//

import SwiftUI
import RealityKit
import CoreHaptics
import ARKit
import Combine

struct ContentView : View {
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    arViewModel.prepareHaptics()
                }
                
            // Debug info overlay
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Inside cube: \(arViewModel.isInsideCube ? "Yes" : "No")")
                    Text("Distance X: \(arViewModel.distanceX, specifier: "%.3f")")
                    Text("Distance Y: \(arViewModel.distanceY, specifier: "%.3f")")
                    Text("Distance Z: \(arViewModel.distanceZ, specifier: "%.3f")")
                    Text("Threshold: 0.060")
                    Text("Frame: \(arViewModel.frameCount)")
                    Text("AR Ready: \(arViewModel.arReady ? "Yes" : "No")")
                    Text("Planes Detected: \(arViewModel.planesDetected)")
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding()
            }
        }
    }
}

// ViewModel to handle AR logic and state
class ARViewModel: ObservableObject {
    @Published var isInsideCube = false
    @Published var distanceX: Float = 0
    @Published var distanceY: Float = 0
    @Published var distanceZ: Float = 0
    @Published var frameCount: Int = 0
    @Published var arReady = false
    @Published var planesDetected = 0
    
    var arView: ARView?
    var cubeEntity: ModelEntity?
    private var lastMoveTime: TimeInterval = 0
    private var hapticEngine: CHHapticEngine?
    private var sessionDelegate: ARSessionDelegate?
    private var anchors: [AnchorEntity] = []
    
    // Setup the AR scene with cube
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        // Set up session delegate
        let delegate = SessionDelegate(viewModel: self)
        self.sessionDelegate = delegate
        arView.session.delegate = delegate
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        // Create the cube but don't add it to the scene yet
        createCube()
    }
    
    // Create cube entity
    private func createCube() {
        let mesh = MeshResource.generateBox(size: 0.1, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let cubeEntity = ModelEntity(mesh: mesh, materials: [material])
        cubeEntity.position = [0, 0.05, 0]
        
        // Add collision component
        let collisionShape = ShapeResource.generateBox(size: [0.1, 0.1, 0.1])
        cubeEntity.collision = CollisionComponent(shapes: [collisionShape])
        
        self.cubeEntity = cubeEntity
    }
    
    // Place cube on detected plane
    func placeFirstCube(on planeAnchor: ARPlaneAnchor) {
        guard !arReady, let arView = arView, let cubeEntity = cubeEntity else { return }
        
        // Create an anchor for the cube
        let anchor = AnchorEntity(anchor: planeAnchor)
        anchor.addChild(cubeEntity)
        arView.scene.anchors.append(anchor)
        anchors.append(anchor)
        
        // Mark AR as ready - now we can start checking for collisions
        DispatchQueue.main.async {
            self.arReady = true
            self.planesDetected += 1
        }
    }
    
    // Called when a new plane is detected
    func planeDetected(_ planeAnchor: ARPlaneAnchor) {
        DispatchQueue.main.async {
            self.planesDetected += 1
        }
        
        // If this is the first horizontal plane, place the cube
        if !arReady && planeAnchor.alignment == .horizontal {
            placeFirstCube(on: planeAnchor)
        }
    }
    
    // Check if camera is inside the cube
    func checkCameraPosition(cameraTransform: simd_float4x4) {
        // Only check for collisions if AR is ready
        guard arReady, let cubeEntity = cubeEntity else { return }
        
        // Get current time for debouncing
        let currentTime = Date().timeIntervalSince1970
        
        // Get camera position from the provided transform
        let cameraPosition = cameraTransform.columns.3
        
        // Get cube position in world space
        let cubeWorldTransform = cubeEntity.transformMatrix(relativeTo: nil)
        let cubePosition = cubeWorldTransform.columns.3
        
        // Calculate distance in each dimension
        let distX = abs(cameraPosition.x - cubePosition.x)
        let distY = abs(cameraPosition.y - cubePosition.y)
        let distZ = abs(cameraPosition.z - cubePosition.z)
        
        // Update frame counter and distances
        DispatchQueue.main.async {
            self.frameCount += 1
            self.distanceX = distX
            self.distanceY = distY
            self.distanceZ = distZ
        }
        
        // Determine if camera is inside cube with some margin
        let newIsInsideCube = distX < 0.06 && distY < 0.06 && distZ < 0.06
        
        // Update state if changed
        if newIsInsideCube != isInsideCube {
            DispatchQueue.main.async {
                self.isInsideCube = newIsInsideCube
            }
            
            // If just entered the cube and enough time has passed since last move
            if newIsInsideCube && (currentTime - lastMoveTime > 1.0) {
                // Move the cube up by 30cm
                DispatchQueue.main.async {
                    self.cubeEntity?.position.y += 0.3
                }
                
                // Trigger haptic feedback
                triggerHapticFeedback()
                
                // Update last move time
                lastMoveTime = currentTime
            }
        }
    }
    
    // Prepare haptic engine
    func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
            
            // Restart haptic engine if it stops
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped for reason: \(reason.rawValue)")
                DispatchQueue.main.async {
                    do {
                        try self?.hapticEngine?.start()
                    } catch {
                        print("Failed to restart haptic engine: \(error)")
                    }
                }
            }
        } catch {
            print("Error creating haptic engine: \(error.localizedDescription)")
        }
    }
    
    // Trigger haptic feedback
    func triggerHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        // Create a pattern of haptic events
        var events = [CHHapticEvent]()
        
        // Create a strong, noticeable vibration
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        
        // Strong initial impact
        let event1 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
        events.append(event1)
        
        // Second pulse
        let event2 = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.1)
        events.append(event2)
        
        // Try using continuous event for more noticeable feedback
        let continuousEvent = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0.2,
            duration: 0.3
        )
        events.append(continuousEvent)
        
        // Play the pattern
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error.localizedDescription)")
        }
    }
}

// Custom ARSession delegate to track camera movement and plane detection
class SessionDelegate: NSObject, ARSessionDelegate {
    weak var viewModel: ARViewModel?
    
    init(viewModel: ARViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // This gets called on every frame update from the AR session
        viewModel?.checkCameraPosition(cameraTransform: frame.camera.transform)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                viewModel?.planeDetected(planeAnchor)
            }
        }
    }
}

// UIViewRepresentable for ARView
struct ARViewContainer: UIViewRepresentable {
    var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupARView(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed here
    }
}

#Preview {
    ContentView()
}
