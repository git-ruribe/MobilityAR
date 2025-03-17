//
//  InteractionMode.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import RealityKit
import CoreHaptics
import ARKit
import Combine

// Main AR View Model class
class ARViewModel: ObservableObject {
    // UI state properties
    @Published var isInsideCube = false
    @Published var distanceToSurface: Float = 0
    @Published var frameCount: Int = 0
    @Published var arReady = false
    @Published var planesDetected = 0
    @Published var placementMode = true
    @Published var positionStable = false
    @Published var instructionText = "Move your device to scan surfaces"
    @Published var placementStage: PlacementStage = .positionSelection
    @Published var currentRotationDegrees: Float = 0
    
    // Drawing mode properties
    @Published var drawingMode = false
    @Published var selectedDrawingColor: DrawingColor = .red

    // Drawing data storage
    var drawingPoints: [DrawingPoint] = []
    var drawingAnchors: [AnchorEntity] = []
    var lastDrawingPosition: simd_float3 = simd_float3(0, 0, 0)
    
    // Computed property for UI display
    var placementStageText: String {
        switch placementStage {
        case .positionSelection:
            return "Positioning"
        case .rotationAdjustment:
            return "Rotating"
        }
    }
    
    // AR components
    var arView: ARView?
    var cubeEntity: ModelEntity?
    var placementEntity: ModelEntity?
    var debugEntity: ModelEntity?
    var rotationRingEntity: ModelEntity?
    var planeOverlays: [ARPlaneAnchor: ModelEntity] = [:]
    
    // Critical component: the single anchor that will hold both preview and real cube
    var mainAnchor: AnchorEntity?
    var debugAnchor: AnchorEntity?
    var planeAnchors: [AnchorEntity] = []
    
    var lastMoveTime: TimeInterval = 0
    var hapticEngine: CHHapticEngine?
    var sessionDelegate: ARSessionDelegate?
    
    // Position stabilization
    var positionHistory: [simd_float3] = []
    var stablePosition: simd_float3?
    var positionUpdateCount = 0
    var lastValidHitPosition: simd_float3?
    
    // Rotation tracking
    var initialRotation: Float = 0
    var currentRotation: Float = 0
    
    // Constants
    let POSITION_HISTORY_SIZE = 10
    let STABILITY_THRESHOLD: Float = 0.005
    let MIN_PLACEMENT_DISTANCE: Float = 0.3
    let MAX_PLACEMENT_DISTANCE: Float = 2.0
    let CUBE_SIZE: Float = 0.1
    let ROTATION_SNAP_DEGREES: Float = 45.0
    
    // Initialize AR scene
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        // Set up session delegate
        let delegate = SessionDelegate(viewModel: self)
        self.sessionDelegate = delegate
        arView.session.delegate = delegate
        
        // Configure AR session with plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)
        
        // Create entities
        createInteractionCube()
        createPlacementIndicator()
        createDebugEntity()
        createRotationRing()
        
        // Add gesture recognizers
        addGestureRecognizers(to: arView)
        
        // Enter placement mode initially
        enterPlacementMode()
    }
    
    // Add gesture recognizers for interaction
    private func addGestureRecognizers(to arView: ARView) {
        // Tap gesture for stage transitions
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapRecognizer)
        
        // Pan gesture for cube rotation
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panRecognizer)
    }
    
    // Create the actual interactive cube
    func createInteractionCube() {
        let mesh = MeshResource.generateBox(size: CUBE_SIZE, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let cubeEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Add collision component
        let collisionShape = ShapeResource.generateBox(size: [CUBE_SIZE, CUBE_SIZE, CUBE_SIZE])
        cubeEntity.collision = CollisionComponent(shapes: [collisionShape])
        
        self.cubeEntity = cubeEntity
    }
    
    // Create debug visual to show exact hit point
    func createDebugEntity() {
        let mesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: .red, roughness: 0.3, isMetallic: false)
        let debugEntity = ModelEntity(mesh: mesh, materials: [material])
        
        self.debugEntity = debugEntity
    }
    
    // Check if camera is inside the cube
    func checkCameraPosition(frame: ARFrame) {
        
        // Call tracking for drawing functionality
        trackCameraForDrawing(frame: frame)
        
        if placementMode {
            if placementStage == .positionSelection {
                updatePlacementPosition(frame: frame)
            }
            return
        }
        
        // Only check for cube interaction when in interaction mode
        guard arReady, let cubeEntity = cubeEntity else { return }
        
        // Current time for debouncing
        let currentTime = Date().timeIntervalSince1970
        
        // Camera position
        let cameraPosition = simd_make_float3(frame.camera.transform.columns.3)
        
        // Cube position
        let cubeWorldTransform = cubeEntity.transformMatrix(relativeTo: nil)
        let cubePosition = simd_make_float3(cubeWorldTransform.columns.3)
        
        // Calculate distances
        let distX = abs(cameraPosition.x - cubePosition.x)
        let distY = abs(cameraPosition.y - cubePosition.y)
        let distZ = abs(cameraPosition.z - cubePosition.z)
        
        // Update distance
        DispatchQueue.main.async {
            self.frameCount += 1
            self.distanceToSurface = simd_distance(cameraPosition, cubePosition)
        }
        
        // Check if inside cube
        let newIsInsideCube = distX < CUBE_SIZE/2 + 0.01 &&
                              distY < CUBE_SIZE/2 + 0.01 &&
                              distZ < CUBE_SIZE/2 + 0.01
        
        // Handle state change
        if newIsInsideCube != isInsideCube {
            DispatchQueue.main.async {
                self.isInsideCube = newIsInsideCube
            }
            
            // Move cube when entered and enough time has passed
            if newIsInsideCube && (currentTime - lastMoveTime > 1.0) {
                // Get current world position
                let worldTransform = cubeEntity.transformMatrix(relativeTo: nil)
                let worldPosition = simd_make_float3(worldTransform.columns.3)
                
                // Create a completely new anchor at current position + height offset
                let newPosition = SIMD3<Float>(worldPosition.x, worldPosition.y + 0.3, worldPosition.z)
                
                // Remove cube from current parent
                cubeEntity.removeFromParent()
                
                // Create new anchor at the target position
                if let arView = arView {
                    let newAnchor = AnchorEntity(world: newPosition)
                    arView.scene.addAnchor(newAnchor)
                    
                    // Add cube to new anchor with identity transform
                    newAnchor.addChild(cubeEntity)
                    cubeEntity.transform = .identity
                    
                    // Update our main anchor reference
                    if let mainAnchor = self.mainAnchor {
                        arView.scene.anchors.remove(mainAnchor)
                    }
                    self.mainAnchor = newAnchor
                    
                    // Animate scale for visual feedback
                    cubeEntity.scale = [0.8, 0.8, 0.8]
                    var finalTransform = cubeEntity.transform
                    finalTransform.scale = SIMD3<Float>(repeating: 1.0)
                    cubeEntity.move(to: finalTransform, relativeTo: newAnchor, duration: 0.2)
                    
                    // Haptic feedback
                    triggerHapticFeedback()
                }
                
                // Update timestamp
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
            
            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("Haptic engine stopped: \(reason.rawValue)")
                DispatchQueue.main.async {
                    do {
                        try self?.hapticEngine?.start()
                    } catch {
                        print("Failed to restart haptic engine: \(error)")
                    }
                }
            }
        } catch {
            print("Error creating haptic engine: \(error)")
        }
    }
    
    // Haptic feedback for cube movement
    func triggerHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.1))
        
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0.2,
            duration: 0.3
        ))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Lighter haptic for placement confirmation
    func triggerPlacementHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Medium haptic for stage transition
    func triggerStageTransitionHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Light subtle haptic for rotation snap
    func triggerSnapHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
}

// Session delegate
class SessionDelegate: NSObject, ARSessionDelegate {
    weak var viewModel: ARViewModel?
    
    init(viewModel: ARViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        viewModel?.checkCameraPosition(frame: frame)
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                viewModel?.planeDetected(planeAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                viewModel?.updatePlaneVisualization(for: planeAnchor)
            }
        }
    }
}//
//  InteractionMode.swift
//  MobilityAR
//
//  Created by Rafael Uribe on 17/03/25.
//

