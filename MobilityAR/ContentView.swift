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
            
            // Instructions overlay
            if !arViewModel.instructionText.isEmpty {
                VStack {
                    Text(arViewModel.instructionText)
                        .font(.headline)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .padding(.top, 50)
                    
                    Spacer()
                }
            }
                
            // Controls overlay
            VStack {
                Spacer()
                
                // Place button for final placement
                if arViewModel.placementStage == .readyToPlace {
                    Button(action: {
                        arViewModel.placeCube()
                    }) {
                        Text("Place Cube")
                            .fontWeight(.bold)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    }
                    .padding(.bottom, 20)
                }
                
                // Reset button when in interaction mode
                if arViewModel.arReady && !arViewModel.placementMode {
                    Button(action: {
                        arViewModel.enterPlacementMode()
                    }) {
                        Text("Reset Cube")
                            .fontWeight(.bold)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    }
                    .padding(.bottom, 20)
                }
                
                // Debug panel
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mode: \(arViewModel.placementMode ? "Placement" : "Interaction")")
                    Text("Stage: \(arViewModel.placementStageText)")
                    Text("Inside cube: \(arViewModel.isInsideCube ? "Yes" : "No")")
                    Text("Distance to surface: \(arViewModel.distanceToSurface, specifier: "%.3f") m")
                    Text("Rotation: \(Int(arViewModel.currentRotationDegrees))°")
                    Text("Planes detected: \(arViewModel.planesDetected)")
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

// Placement stages for the three-stage process
enum PlacementStage {
    case positionSelection // Initial positioning
    case rotationAdjustment // Adjusting rotation
    case readyToPlace // Ready for final placement
}

// AR View Model with three-stage placement
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
    
    // Computed property for UI display
    var placementStageText: String {
        switch placementStage {
        case .positionSelection:
            return "Positioning"
        case .rotationAdjustment:
            return "Rotating"
        case .readyToPlace:
            return "Ready to Place"
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
    private var mainAnchor: AnchorEntity?
    private var debugAnchor: AnchorEntity?
    private var planeAnchors: [AnchorEntity] = []
    
    private var lastMoveTime: TimeInterval = 0
    private var hapticEngine: CHHapticEngine?
    private var sessionDelegate: ARSessionDelegate?
    private var rotationGestureRecognizer: UIRotationGestureRecognizer?
    
    // Position stabilization
    private var positionHistory: [simd_float3] = []
    private var stablePosition: simd_float3?
    private var positionUpdateCount = 0
    private var lastValidHitPosition: simd_float3?
    
    // Rotation tracking
    private var initialRotation: Float = 0
    private var currentRotation: Float = 0
    
    // Constants
    private let POSITION_HISTORY_SIZE = 10
    private let STABILITY_THRESHOLD: Float = 0.005
    private let MIN_PLACEMENT_DISTANCE: Float = 0.3
    private let MAX_PLACEMENT_DISTANCE: Float = 2.0
    private let CUBE_SIZE: Float = 0.1
    private let ROTATION_SNAP_DEGREES: Float = 45.0
    
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
        
        // Replace rotation gesture with pan gesture for cube rotation
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panRecognizer)
        self.rotationGestureRecognizer = nil // Remove the old rotation recognizer
    }
    
    // Create the actual interactive cube
    private func createInteractionCube() {
        let mesh = MeshResource.generateBox(size: CUBE_SIZE, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .gray, roughness: 0.15, isMetallic: true)
        let cubeEntity = ModelEntity(mesh: mesh, materials: [material])
        
        // Add collision component
        let collisionShape = ShapeResource.generateBox(size: [CUBE_SIZE, CUBE_SIZE, CUBE_SIZE])
        cubeEntity.collision = CollisionComponent(shapes: [collisionShape])
        
        self.cubeEntity = cubeEntity
    }
    
    // Create placement indicator (preview cube)
    private func createPlacementIndicator() {
        let mesh = MeshResource.generateBox(size: CUBE_SIZE, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .blue.withAlphaComponent(0.5), roughness: 0.3, isMetallic: false)
        let previewEntity = ModelEntity(mesh: mesh, materials: [material])
        
        self.placementEntity = previewEntity
    }
    
    // Create debug visual to show exact hit point
    private func createDebugEntity() {
        let mesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: .red, roughness: 0.3, isMetallic: false)
        let debugEntity = ModelEntity(mesh: mesh, materials: [material])
        
        self.debugEntity = debugEntity
    }
    
    // Create rotation ring indicator
    private func createRotationRing() {
        // Create a circular disc as rotation indicator instead of a torus
        // (since MeshResource doesn't have generateTorus)
        let ringMesh = MeshResource.generatePlane(width: CUBE_SIZE * 1.4,
                                                 depth: CUBE_SIZE * 1.4)
        let material = SimpleMaterial(color: .white.withAlphaComponent(0.4),
                                      roughness: 0.3,
                                      isMetallic: true)
        let ringEntity = ModelEntity(mesh: ringMesh, materials: [material])
        
        // Position at bottom of cube
        ringEntity.position.y = -CUBE_SIZE / 2 + 0.003
        
        // Create directional marker (arrow)
        let arrowMesh = MeshResource.generateBox(size: [0.01, 0.003, 0.03])
        let arrowMaterial = SimpleMaterial(color: .red.withAlphaComponent(0.8),
                                           roughness: 0.3,
                                           isMetallic: true)
        let arrowEntity = ModelEntity(mesh: arrowMesh, materials: [arrowMaterial])
        
        // Position arrow at front of ring
        arrowEntity.position = [0, 0, CUBE_SIZE * 0.7]
        
        // Add arrow to ring
        ringEntity.addChild(arrowEntity)
        
        // Hide ring initially
        ringEntity.isEnabled = false
        
        self.rotationRingEntity = ringEntity
    }
    
    // Create visual for detected plane
    fileprivate func createPlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let arView = arView, placementMode else { return }
        
        // Create plane visualization with fixed transparency
        let width = planeAnchor.extent.x
        let length = planeAnchor.extent.z
        
        let gridMesh = MeshResource.generatePlane(width: Float(width), depth: Float(length))
        let material = SimpleMaterial(color: UIColor.blue.withAlphaComponent(0.2), roughness: 1.0, isMetallic: false)
        let gridEntity = ModelEntity(mesh: gridMesh, materials: [material])
        
        // Add to scene
        let anchor = AnchorEntity(anchor: planeAnchor)
        anchor.addChild(gridEntity)
        arView.scene.addAnchor(anchor)
        
        // Store references
        planeAnchors.append(anchor)
        planeOverlays[planeAnchor] = gridEntity
        
        // Update instruction if this is first plane
        if planesDetected == 1 {
            DispatchQueue.main.async {
                self.instructionText = "Point at a surface and hold steady"
            }
        }
    }
    
    // Update plane visualization when ARKit updates plane dimensions
    fileprivate func updatePlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let gridEntity = planeOverlays[planeAnchor] else { return }
        
        // Update mesh based on new plane extent
        let width = planeAnchor.extent.x
        let length = planeAnchor.extent.z
        
        let updatedMesh = MeshResource.generatePlane(width: Float(width), depth: Float(length))
        gridEntity.model?.mesh = updatedMesh
    }
    
    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard placementMode && placementStage == .rotationAdjustment else { return }
        
        switch sender.state {
        case .began:
            // Store initial values
            initialRotation = currentRotation
            
        case .changed:
            // Calculate rotation based on horizontal pan movement
            // Translation in points
            let translation = sender.translation(in: sender.view)
            
            // Convert horizontal movement to rotation (adjust sensitivity as needed)
            // Smaller divisor = more sensitive rotation
            let rotationSensitivity: CGFloat = 50.0
            let rotationAmount = initialRotation + Float(translation.x / rotationSensitivity)
            
            // Apply rotation to preview entity
            if let placementEntity = placementEntity {
                // Create rotation quaternion around Y axis
                let rotation = simd_quatf(angle: rotationAmount, axis: SIMD3<Float>(0, 1, 0))
                placementEntity.transform.rotation = rotation
                
                // Update current rotation value for UI display (convert to degrees)
                currentRotation = rotationAmount
                
                // Update UI
                DispatchQueue.main.async {
                    self.currentRotationDegrees = self.currentRotation * 180 / .pi
                }
            }
            
        case .ended:
            // Snap rotation to nearest increment if desired
            if let placementEntity = placementEntity {
                // Convert to degrees for snapping
                let rotationDegrees = currentRotation * 180 / .pi
                
                // Calculate nearest snap angle
                let snapRotationDegrees = round(rotationDegrees / ROTATION_SNAP_DEGREES) * ROTATION_SNAP_DEGREES
                let snapRotation = snapRotationDegrees * .pi / 180
                
                // Only snap if it's a small adjustment
                let diffDegrees = abs(rotationDegrees - snapRotationDegrees)
                if diffDegrees < 10 {  // Snap if within 10 degrees
                    // Create rotation quaternion for snapped angle
                    let rotation = simd_quatf(angle: snapRotation, axis: SIMD3<Float>(0, 1, 0))
                    
                    // Animate to snapped position
                    var snapTransform = placementEntity.transform
                    snapTransform.rotation = rotation
                    placementEntity.move(to: snapTransform, relativeTo: nil, duration: 0.1)
                    
                    // Update rotation value
                    currentRotation = snapRotation
                    
                    // Provide haptic feedback for snap
                    triggerSnapHapticFeedback()
                    
                    // Update UI
                    DispatchQueue.main.async {
                        self.currentRotationDegrees = snapRotationDegrees
                    }
                } else {
                    // Keep current rotation
                    currentRotation = Float(sender.translation(in: sender.view).x / 50.0) + initialRotation
                }
            }
            
        default:
            break
        }
    }
    
    // Handle tap for stage transition
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard placementMode else { return }
        
        switch placementStage {
        case .positionSelection:
            if positionStable {
                // Transition to rotation adjustment stage
                transitionToRotationStage()
            }
            
        case .rotationAdjustment:
            // Transition to ready-to-place stage
            transitionToReadyStage()
            
        case .readyToPlace:
            // Place the cube
            placeCube()
        }
    }
    
    // Handle rotation gesture
    @objc func handleRotation(_ sender: UIRotationGestureRecognizer) {
        guard placementMode && placementStage == .rotationAdjustment else { return }
        
        switch sender.state {
        case .began:
            // Store initial values
            initialRotation = currentRotation
            
        case .changed:
            // Calculate new rotation around Y axis
            let rotationAmount = initialRotation + Float(sender.rotation)
            
            // Apply rotation to preview entity
            if let placementEntity = placementEntity {
                // Create rotation quaternion around Y axis
                let rotation = simd_quatf(angle: rotationAmount, axis: SIMD3<Float>(0, 1, 0))
                placementEntity.transform.rotation = rotation
                
                // Update current rotation value for UI display (convert to degrees)
                currentRotation = rotationAmount
                
                // Update UI
                DispatchQueue.main.async {
                    self.currentRotationDegrees = self.currentRotation * 180 / .pi
                }
            }
            
        case .ended:
            // Snap rotation to nearest increment if desired
            if let placementEntity = placementEntity {
                // Convert to degrees for snapping
                let rotationDegrees = currentRotation * 180 / .pi
                
                // Calculate nearest snap angle
                let snapRotationDegrees = round(rotationDegrees / ROTATION_SNAP_DEGREES) * ROTATION_SNAP_DEGREES
                let snapRotation = snapRotationDegrees * .pi / 180
                
                // Only snap if it's a small adjustment
                let diffDegrees = abs(rotationDegrees - snapRotationDegrees)
                if diffDegrees < 10 {  // Snap if within 10 degrees
                    // Create rotation quaternion for snapped angle
                    let rotation = simd_quatf(angle: snapRotation, axis: SIMD3<Float>(0, 1, 0))
                    
                    // Animate to snapped position
                    var snapTransform = placementEntity.transform
                    snapTransform.rotation = rotation
                    placementEntity.move(to: snapTransform, relativeTo: nil, duration: 0.1)
                    
                    // Update rotation value
                    currentRotation = snapRotation
                    
                    // Provide haptic feedback for snap
                    triggerSnapHapticFeedback()
                    
                    // Update UI
                    DispatchQueue.main.async {
                        self.currentRotationDegrees = snapRotationDegrees
                    }
                } else {
                    // Keep current rotation if not snapping
                    currentRotation = initialRotation + Float(sender.rotation)
                }
            }
            
        default:
            break
        }
    }
    
    // Transition to rotation adjustment stage
    private func transitionToRotationStage() {
        guard placementStage == .positionSelection, positionStable,
              let placementEntity = placementEntity,
              let rotationRingEntity = rotationRingEntity else { return }
        
        // Lock position and transition to rotation mode
        placementStage = .rotationAdjustment
        
        // Add rotation ring to placement entity
        if !placementEntity.children.contains(where: { $0 == rotationRingEntity }) {
            placementEntity.addChild(rotationRingEntity)
        }
        
        // Show rotation indicator
        rotationRingEntity.isEnabled = true
        
        // Change appearance to indicate rotation mode
        updatePlacementColor(.green)
        
        // Reset rotation tracking
        initialRotation = 0
        currentRotation = 0
        currentRotationDegrees = 0
        
        // Update instruction to reflect single-finger pan
        DispatchQueue.main.async {
            self.instructionText = "Swipe left or right to rotate, tap when done"
        }
        
        // Provide haptic feedback for stage transition
        triggerStageTransitionHaptic()
    }
    
    // Transition to ready-to-place stage
    private func transitionToReadyStage() {
        guard placementStage == .rotationAdjustment else { return }
        
        // Transition to final placement stage
        placementStage = .readyToPlace
        
        // Important: Lock the placement entity's position and rotation
            // by creating a copy of its current transform
        if let placementEntity = placementEntity {
            let lockedTransform = placementEntity.transform
            placementEntity.transform = lockedTransform
        }
        
        // Update appearance for ready state
        updatePlacementColor(UIColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 0.7))
        
        // Add subtle pulsing animation
        addPulseAnimation()
        
        // Update instruction
        DispatchQueue.main.async {
            self.instructionText = "Tap to place cube"
        }
        
        // Provide haptic feedback for stage transition
        triggerStageTransitionHaptic()
    }
    
    // Place cube by directly swapping entities within the same anchor
    func placeCube() {
        guard (placementStage == .readyToPlace || placementStage == .rotationAdjustment),
              let arView = arView,
              let mainAnchor = mainAnchor,
              let placementEntity = placementEntity,
              let cubeEntity = cubeEntity,
              let rotationRingEntity = rotationRingEntity else { return }
        
        // Disable rotation ring if still a child
        rotationRingEntity.isEnabled = false
        
        // Remove the ring from preview entity if it's attached
        if placementEntity.children.contains(where: { $0 == rotationRingEntity }) {
            rotationRingEntity.removeFromParent()
        }
        
        // Remove the preview entity from the anchor
        placementEntity.removeFromParent()
        
        // Add the real cube entity to the exact same anchor
        mainAnchor.addChild(cubeEntity)
        
        // Apply the same rotation to the real cube
        cubeEntity.transform.rotation = placementEntity.transform.rotation
        
        // Scale animation from zero to reinforce placement
        cubeEntity.scale = [0.01, 0.01, 0.01]
        var finalTransform = cubeEntity.transform
        finalTransform.scale = SIMD3<Float>(repeating: 1.0)
        
        // Animate to full size
        cubeEntity.move(to: finalTransform, relativeTo: mainAnchor, duration: 0.3)
        
        // Haptic feedback
        triggerPlacementHapticFeedback()
        
        // Exit placement mode
        exitPlacementMode()
        
        // Update state
        DispatchQueue.main.async {
            self.arReady = true
            self.instructionText = "Walk around the cube to explore"
        }
    }
    
    // Add subtle pulsing animation to indicate ready state
    private func addPulseAnimation() {
        guard let placementEntity = placementEntity else { return }
        
        // Create subtle scale animation
        let originalScale = placementEntity.transform.scale
        let pulseScale = originalScale * 1.05
        
        // Animate scale up
        var pulseUpTransform = placementEntity.transform
        pulseUpTransform.scale = pulseScale
        placementEntity.move(to: pulseUpTransform, relativeTo: nil, duration: 0.5)
        
        // Schedule scale down after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var pulseDownTransform = placementEntity.transform
            pulseDownTransform.scale = originalScale
            placementEntity.move(to: pulseDownTransform, relativeTo: nil, duration: 0.5)
        }
    }
    
    // Enter placement mode
    func enterPlacementMode() {
        guard let arView = arView else { return }
        
        // Clean up any existing entities
        cleanupExistingEntities()
        
        // Recreate all entities to ensure clean state
        createInteractionCube()
        createPlacementIndicator()
        createDebugEntity()
        createRotationRing()
        
        guard let placementEntity = placementEntity,
              let debugEntity = debugEntity else { return }
        
        // Create the main anchor for placement - will remain throughout the placement process
        let newMainAnchor = AnchorEntity(world: [0, 0, 0])
        arView.scene.addAnchor(newMainAnchor)
        self.mainAnchor = newMainAnchor
        
        // Add placement preview to the main anchor
        newMainAnchor.addChild(placementEntity)
        
        // Create debug anchor and add debug entity
        let newDebugAnchor = AnchorEntity(world: [0, 0, 0])
        arView.scene.addAnchor(newDebugAnchor)
        newDebugAnchor.addChild(debugEntity)
        self.debugAnchor = newDebugAnchor
        
        // Reset tracking for fresh plane detection
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        // Reset state
        resetState()
    }
    
    // Clean up all existing entities
    private func cleanupExistingEntities() {
        guard let arView = arView else { return }
        
        // Remove main anchor if it exists
        if let mainAnchor = mainAnchor {
            arView.scene.anchors.remove(mainAnchor)
            self.mainAnchor = nil
        }
        
        // Remove debug anchor if it exists
        if let debugAnchor = debugAnchor {
            arView.scene.anchors.remove(debugAnchor)
            self.debugAnchor = nil
        }
        
        // Remove all plane anchors
        for anchor in planeAnchors {
            arView.scene.anchors.remove(anchor)
        }
        planeAnchors.removeAll()
        
        // Reset entity references to force recreation
        self.cubeEntity = nil
        self.placementEntity = nil
        self.debugEntity = nil
        self.rotationRingEntity = nil
    }
    
    // Reset all state variables
    private func resetState() {
        DispatchQueue.main.async {
            self.placementMode = true
            self.arReady = false
            self.isInsideCube = false
            self.positionStable = false
            self.planesDetected = 0
            self.instructionText = "Move your device to scan surfaces"
            self.placementStage = .positionSelection
            self.currentRotationDegrees = 0
        }
        
        // Reset position tracking
        positionHistory.removeAll()
        stablePosition = nil
        positionUpdateCount = 0
        lastValidHitPosition = nil
        planeOverlays.removeAll()
        
        // Reset rotation
        initialRotation = 0
        currentRotation = 0
    }
    
    // Exit placement mode
    private func exitPlacementMode() {
        guard let arView = arView else { return }
        
        // Remove debug anchor if it exists
        if let debugAnchor = debugAnchor {
            arView.scene.anchors.remove(debugAnchor)
            self.debugAnchor = nil
        }
        
        // Remove all plane anchors
        for anchor in planeAnchors {
            arView.scene.anchors.remove(anchor)
        }
        planeAnchors.removeAll()
        
        // Note: We keep the main anchor since it now contains the real cube
        
        // Update state
        DispatchQueue.main.async {
            self.placementMode = false
            self.planeOverlays.removeAll()
        }
    }
    
    // Update placement position
    func updatePlacementPosition(frame: ARFrame) {
        // Only update position in position selection stage
        guard placementMode && placementStage == .positionSelection,
              let arView = arView,
              let mainAnchor = mainAnchor,
              let placementEntity = placementEntity,
              let debugAnchor = debugAnchor,
              let debugEntity = debugEntity else { return }
        
        // Get camera transform
        let cameraTransform = frame.camera.transform
        let cameraPosition = simd_make_float3(cameraTransform.columns.3)
        
        // Cast ray from center of screen
        let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        let results = arView.raycast(from: screenCenter,
                                     allowing: .estimatedPlane,
                                     alignment: .any)
        
        if let firstResult = results.first {
            // Get hit position and transform
            let hitPosition = simd_make_float3(firstResult.worldTransform.columns.3)
            
            // Position debug entity exactly at hit point
            debugAnchor.transform.translation = hitPosition
            
            // Calculate distance from camera to hit point
            let distance = simd_distance(cameraPosition, hitPosition)
            
            // Update distance for UI
            DispatchQueue.main.async {
                self.distanceToSurface = distance
            }
            
            // Validate distance
            if distance < MIN_PLACEMENT_DISTANCE {
                // Too close
                updatePlacementStatus(false, "Too close to place - move back")
                updatePlacementColor(.red)
                positionHistory.removeAll()
                return
            } else if distance > MAX_PLACEMENT_DISTANCE {
                // Too far
                updatePlacementStatus(false, "Too far away - move closer")
                updatePlacementColor(.red)
                positionHistory.removeAll()
                return
            }
            
            // Track this position
            lastValidHitPosition = hitPosition
            
            // Add to position history for stabilization
            positionHistory.append(hitPosition)
            if positionHistory.count > POSITION_HISTORY_SIZE {
                positionHistory.removeFirst()
            }
            
            // Check if position is stable
            if positionHistory.count == POSITION_HISTORY_SIZE {
                // Calculate average position
                var avgPosition = simd_float3(0, 0, 0)
                for pos in positionHistory {
                    avgPosition += pos
                }
                avgPosition /= Float(positionHistory.count)
                
                // Calculate max variance
                var maxVariance: Float = 0
                for pos in positionHistory {
                    let distance = simd_distance(pos, avgPosition)
                    maxVariance = max(maxVariance, distance)
                }
                
                // Update stability status
                let isStable = maxVariance < STABILITY_THRESHOLD
                if isStable {
                    stablePosition = avgPosition
                    
                    // Critical part: Update main anchor position directly
                    // This ensures the cube will be placed exactly here
                    var adjustedPosition = avgPosition
                    adjustedPosition.y += CUBE_SIZE / 2 // Adjust for cube height
                    
                    // CRITICAL: We're directly updating the main anchor that will eventually hold the real cube
                    mainAnchor.transform.translation = adjustedPosition
                    
                    // Also set the orientation from the hit result
                    // This ensures proper alignment with surfaces
                    let rotation = simd_quaternion(firstResult.worldTransform)
                    placementEntity.transform.rotation = rotation
                    
                    // Update UI
                    updatePlacementStatus(true, "Tap to adjust rotation")
                    updatePlacementColor(.green)
                } else {
                    // Not yet stable
                    updatePlacementStatus(false, "Hold steady...")
                    updatePlacementColor(.yellow)
                }
            } else {
                // Not enough samples
                updatePlacementStatus(false, "Hold steady...")
                updatePlacementColor(.yellow)
            }
        } else {
            positionUpdateCount += 1
            if positionUpdateCount > 30 { // About 1 second at 30fps
                // Lost tracking for a while
                updatePlacementStatus(false, "Point at a flat surface")
                updatePlacementColor(.blue)
                positionHistory.removeAll()
            }
        }
    }
    
    // Helper to update placement status
    private func updatePlacementStatus(_ stable: Bool, _ message: String) {
        DispatchQueue.main.async {
            self.positionStable = stable
            self.instructionText = message
        }
    }
    
    // Helper to update placement indicator color
    private func updatePlacementColor(_ color: UIColor) {
        guard let placementEntity = placementEntity else { return }
        
        let material = SimpleMaterial(
            color: color.withAlphaComponent(0.5),
            roughness: 0.3,
            isMetallic: false
        )
        
        placementEntity.model?.materials = [material]
    }
    
    // Check if camera is inside the cube
    func checkCameraPosition(frame: ARFrame) {
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
    
    // Called when a new plane is detected
    func planeDetected(_ planeAnchor: ARPlaneAnchor) {
        DispatchQueue.main.async {
            self.planesDetected += 1
        }
        
        // Create visualization for horizontal planes
        if planeAnchor.alignment == .horizontal {
            createPlaneVisualization(for: planeAnchor)
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
        // No updates needed
    }
}

#Preview {
    ContentView()
}
