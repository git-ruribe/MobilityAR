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
    @Published var isDrawingActive = false // Tracks if user is touching screen for drawing

    // Drawing data storage
    var drawingPoints: [DrawingPoint] = []
    var drawingAnchors: [AnchorEntity] = []
    var lastDrawingPosition: simd_float3 = simd_float3(0, 0, 0)
    
    //Footprints
    var leftFootprintEntity: ModelEntity?
    var rightFootprintEntity: ModelEntity?
    var leftFootprintAnchor: AnchorEntity?
    var rightFootprintAnchor: AnchorEntity?

    
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
    
    // Create footprint models
    func createFootprintModels() {
        // Create left footprint
        let leftFootprint = createFootprint(isLeft: true)
        self.leftFootprintEntity = leftFootprint
        
        // Create right footprint
        let rightFootprint = createFootprint(isLeft: false)
        self.rightFootprintEntity = rightFootprint
    }

    // Helper to create a single footprint
    func createFootprint(isLeft: Bool) -> ModelEntity {
        // Main sole of the foot
        let soleLength: Float = 0.25  // 25cm long
        let soleWidth: Float = 0.09   // 9cm wide
        let soleMesh = MeshResource.generateBox(
            size: [soleWidth, 0.005, soleLength],
            cornerRadius: 0.02
        )
        
        // Heel part (slightly wider)
        let heelWidth: Float = 0.07
        let heelLength: Float = 0.07
        let heelMesh = MeshResource.generateBox(
            size: [heelWidth, 0.007, heelLength],
            cornerRadius: 0.02
        )
        
        // Create the foot sole entity with translucent color
        let color = isLeft ? UIColor.blue.withAlphaComponent(0.7) : UIColor.green.withAlphaComponent(0.7)
        let soleMaterial = SimpleMaterial(color: color, roughness: 0.4, isMetallic: false)
        let footEntity = ModelEntity(mesh: soleMesh, materials: [soleMaterial])
        
        // Create heel with same material
        let heelEntity = ModelEntity(mesh: heelMesh, materials: [soleMaterial])
        
        // Position heel at back of sole
        heelEntity.position = [0, 0.001, soleLength/2 - heelLength/2]
        footEntity.addChild(heelEntity)
        
        // Add text label (L or R)
        let textMesh = MeshResource.generateText(
            isLeft ? "L" : "R",
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.1),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        let textMaterial = SimpleMaterial(color: .white, roughness: 0.1, isMetallic: true)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        
        // Scale and position text
        textEntity.scale = [0.2, 0.2, 0.2]
        textEntity.position = [0, 0.01, -0.05]
        
        // First, rotate text to face up (90 degrees around X axis)
        let faceUpRotation = simd_quatf(angle: Float.pi/2, axis: [1, 0, 0])
        
        // Add 180 degree rotation around Y axis
        let flipRotation = simd_quatf(angle: Float.pi, axis: [0, 1, 0])
        
        // Combine rotations: first face up, then flip
        textEntity.orientation = simd_mul(flipRotation, faceUpRotation)
        
        // Mirror text if needed
        textEntity.transform.scale.x *= -1  // Mirror both for consistent appearance
        
        footEntity.addChild(textEntity)
        
        // No longer mirroring the whole foot
        
        return footEntity
    }

    // Place footprints in world - call this after cube placement is confirmed
    func placeFootprints() {
        guard let arView = arView,
              let cubeEntity = cubeEntity,
              let leftFootprintEntity = leftFootprintEntity,
              let rightFootprintEntity = rightFootprintEntity else { return }
        
        // Get the cube's world position and rotation
        let cubeWorldTransform = cubeEntity.transformMatrix(relativeTo: nil)
        let cubeWorldPosition = simd_make_float3(cubeWorldTransform.columns.3)
        let cubeRotation = cubeEntity.transform.rotation
        
        // Define the local offsets (before rotation is applied)
        let leftLocalOffset = SIMD3<Float>(0.2, -0.04, -0.3)  // Left, up, opposite direction
        let rightLocalOffset = SIMD3<Float>(-0.2, -0.04, -0.3)  // Right, up, opposite direction
        
        // Create rotation matrix from quaternion
        let rotationMatrix = simd_matrix3x3(cubeRotation)
        
        // Apply rotation to the offset vectors
        let rotatedLeftOffset = rotationMatrix * leftLocalOffset
        let rotatedRightOffset = rotationMatrix * rightLocalOffset
        
        // Calculate final world positions
        let leftPosition = cubeWorldPosition + rotatedLeftOffset
        let rightPosition = cubeWorldPosition + rotatedRightOffset
        
        // Create anchors at calculated world positions
        let leftAnchor = AnchorEntity(world: leftPosition)
        let rightAnchor = AnchorEntity(world: rightPosition)
        
        // Add footprints to anchors
        leftAnchor.addChild(leftFootprintEntity)
        rightAnchor.addChild(rightFootprintEntity)
        
        // Store anchor references
        self.leftFootprintAnchor = leftAnchor
        self.rightFootprintAnchor = rightAnchor
        
        // Add anchors to scene
        arView.scene.addAnchor(leftAnchor)
        arView.scene.addAnchor(rightAnchor)
        
        // Create a 180-degree rotation to flip footprints around
        let flipRotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        
        // Create the slight inward angles
        let leftAngle: Float = 0.05 * .pi  // ~9 degrees inward
        let rightAngle: Float = -0.05 * .pi  // ~9 degrees inward
        
        // Create rotations with inward angles
        let leftInwardRotation = simd_quatf(angle: leftAngle, axis: [0, 1, 0])
        let rightInwardRotation = simd_quatf(angle: rightAngle, axis: [0, 1, 0])
        
        // Combine rotations: first flip 180°, then apply cube rotation, then apply inward angle
        // Order matters in quaternion multiplication!
        leftFootprintEntity.orientation = simd_mul(simd_mul(cubeRotation, flipRotation), leftInwardRotation)
        rightFootprintEntity.orientation = simd_mul(simd_mul(cubeRotation, flipRotation), rightInwardRotation)
        
        // Update instruction text
        DispatchQueue.main.async {
            self.instructionText = "Stand on the footprints to interact with the cube"
        }
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

