//
//  PlacementMode.swift
//  MobilityAR
//

import SwiftUI
import RealityKit
import ARKit
import CoreHaptics

// Modified to include footprints in placement stage
enum PlacementStage {
    case positionSelection // Initial positioning
    case rotationAdjustment // Adjusting rotation and ready for placement
}

// Extension to ARViewModel for placement mode functionality
extension ARViewModel {
    
    // Create placement indicator (preview cube)
    func createPlacementIndicator() {
        let mesh = MeshResource.generateBox(size: CUBE_SIZE, cornerRadius: 0.005)
        let material = SimpleMaterial(color: .blue.withAlphaComponent(0.5), roughness: 0.3, isMetallic: false)
        let previewEntity = ModelEntity(mesh: mesh, materials: [material])
        
        self.placementEntity = previewEntity
    }
    
    // Create rotation ring indicator
    func createRotationRing() {
        // Create a circular disc as rotation indicator
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
    func createPlaneVisualization(for planeAnchor: ARPlaneAnchor) {
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
    func updatePlaneVisualization(for planeAnchor: ARPlaneAnchor) {
        guard let gridEntity = planeOverlays[planeAnchor] else { return }
        
        // Update mesh based on new plane extent
        let width = planeAnchor.extent.x
        let length = planeAnchor.extent.z
        
        let updatedMesh = MeshResource.generatePlane(width: Float(width), depth: Float(length))
        gridEntity.model?.mesh = updatedMesh
    }
    
    // Handle pan for cube rotation
    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard placementMode && placementStage == .rotationAdjustment else { return }
        
        switch sender.state {
        case .began:
            // Store initial values
            initialRotation = currentRotation
            
        case .changed:
            // Calculate rotation based on horizontal pan movement
            let translation = sender.translation(in: sender.view)
            
            // Convert horizontal movement to rotation
            let rotationSensitivity: CGFloat = 50.0
            let rotationAmount = initialRotation + Float(translation.x / rotationSensitivity)
            
            // Apply rotation to preview entity
            if let placementEntity = placementEntity {
                // Create rotation quaternion around Y axis
                let rotation = simd_quatf(angle: rotationAmount, axis: SIMD3<Float>(0, 1, 0))
                placementEntity.transform.rotation = rotation
                
                // Maintain position relative to parent
                placementEntity.transform.translation = .zero
                
                // Update current rotation value for UI display (convert to degrees)
                currentRotation = rotationAmount
                
                // Update UI
                DispatchQueue.main.async {
                    self.currentRotationDegrees = self.currentRotation * 180 / .pi
                }
                
                // Update preview footprints position and rotation
                updatePreviewFootprints(rotation: rotation)
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
                    
                    // FIXED: Use parent-relative positioning
                    placementEntity.move(to: snapTransform, relativeTo: placementEntity.parent, duration: 0.1)
                    
                    // Update rotation value
                    currentRotation = snapRotation
                    
                    // Provide haptic feedback for snap
                    triggerSnapHapticFeedback()
                    
                    // Update UI
                    DispatchQueue.main.async {
                        self.currentRotationDegrees = snapRotationDegrees
                    }
                    
                    // Update preview footprints after snap
                    updatePreviewFootprints(rotation: rotation)
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
        
        if placementStage == .positionSelection && positionStable {
            // Transition to rotation adjustment stage
            transitionToRotationStage()
            
            // Provide haptic feedback for successful tap
            triggerPlacementHapticFeedback()
            
            // Print debug message to console
            print("PlacementMode: Tap handled, transitioning to rotation stage")
        } else if placementStage == .positionSelection && !positionStable {
            // Provide feedback that we're not ready yet
            DispatchQueue.main.async {
                self.instructionText = "Keep holding steady until position stabilizes"
            }
            print("PlacementMode: Tap received but position not stable yet")
        }
    }
    
    // Transition to rotation adjustment stage
    func transitionToRotationStage() {
        guard placementStage == .positionSelection, positionStable,
                  let placementEntity = placementEntity,
                  let rotationRingEntity = rotationRingEntity,
                  let arView = arView else { return }
            
            // Get current camera orientation to set initial cube rotation
            if let frame = arView.session.currentFrame {
                let cameraTransform = frame.camera.transform
                
                // Get camera direction vector (ignoring vertical component for level placement)
                let cameraDirection = simd_make_float3(
                    -cameraTransform.columns.2.x,
                    0,
                    -cameraTransform.columns.2.z
                )
                let normalizedDirection = simd_normalize(cameraDirection)

                // Calculate the angle around Y axis (yaw) from the normalized direction
                let rotationAngle = atan2(normalizedDirection.x, normalizedDirection.z)

                // Create quaternion for rotation around Y axis
                let cubeRotation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))
                
                // Apply this rotation to the placement entity
                placementEntity.transform.rotation = cubeRotation
                
                // Convert to degrees for display and tracking
                let rotationAngleY = atan2(normalizedDirection.x, normalizedDirection.z)
                initialRotation = rotationAngleY
                currentRotation = rotationAngleY
                currentRotationDegrees = rotationAngleY * 180 / .pi
            }
        
        placementStage = .rotationAdjustment
        
        // Add rotation ring to placement entity
        if !placementEntity.children.contains(where: { $0 == rotationRingEntity }) {
            placementEntity.addChild(rotationRingEntity)
        }
        
        // Show rotation indicator
        rotationRingEntity.isEnabled = true
        
        // Change appearance to indicate rotation mode
        updatePlacementColor(.green)
        
        // Update footprint appearance for rotation stage
        if leftFootprintEntity != nil && rightFootprintEntity != nil {
            if let leftMaterial = leftFootprintEntity?.model?.materials.first as? SimpleMaterial,
               let rightMaterial = rightFootprintEntity?.model?.materials.first as? SimpleMaterial {
                
                // Make footprints more visible during rotation stage
                let leftColor = UIColor.blue.withAlphaComponent(0.4)
                let rightColor = UIColor.green.withAlphaComponent(0.4)
                
                let newLeftMaterial = SimpleMaterial(color: leftColor, roughness: 0.4, isMetallic: false)
                let newRightMaterial = SimpleMaterial(color: rightColor, roughness: 0.4, isMetallic: false)
                
                leftFootprintEntity?.model?.materials = [newLeftMaterial]
                rightFootprintEntity?.model?.materials = [newRightMaterial]
            }
        } else {
            // If footprints don't exist yet, create them
            showPreviewFootprints()
        }
        
        // Update footprint positions with current rotation
        updatePreviewFootprints(rotation: placementEntity.transform.rotation)
        
        // Update instruction to reflect single-finger pan
        DispatchQueue.main.async {
            self.instructionText = "Swipe left or right to rotate, tap Place Cube when ready"
        }
        
        // Provide haptic feedback for stage transition
        triggerStageTransitionHaptic()
    }
    
    // Show preview footprints during placement stages
    func showPreviewFootprints() {
        // Create footprint models if they don't exist
        if leftFootprintEntity == nil || rightFootprintEntity == nil {
            createFootprintModels()
        }
        
        guard let arView = arView,
              let mainAnchor = mainAnchor,
              let placementEntity = placementEntity,
              let leftFootprintEntity = leftFootprintEntity,
              let rightFootprintEntity = rightFootprintEntity else { return }
        
        // Create placement footprint anchors if they don't exist
        if leftFootprintAnchor == nil {
            leftFootprintAnchor = AnchorEntity()
            leftFootprintAnchor?.addChild(leftFootprintEntity)
            arView.scene.addAnchor(leftFootprintAnchor!)
        }
        
        if rightFootprintAnchor == nil {
            rightFootprintAnchor = AnchorEntity()
            rightFootprintAnchor?.addChild(rightFootprintEntity)
            arView.scene.addAnchor(rightFootprintAnchor!)
        }
        
        // Make footprints even more transparent during positioning stage
        if placementStage == .positionSelection {
            if let leftMaterial = leftFootprintEntity.model?.materials.first as? SimpleMaterial,
               let rightMaterial = rightFootprintEntity.model?.materials.first as? SimpleMaterial {
                
                // Create more transparent versions for positioning stage
                let leftColor = UIColor.blue.withAlphaComponent(0.3)
                let rightColor = UIColor.green.withAlphaComponent(0.3)
                
                let newLeftMaterial = SimpleMaterial(color: leftColor, roughness: 0.4, isMetallic: false)
                let newRightMaterial = SimpleMaterial(color: rightColor, roughness: 0.4, isMetallic: false)
                
                leftFootprintEntity.model?.materials = [newLeftMaterial]
                rightFootprintEntity.model?.materials = [newRightMaterial]
            }
        }
        
        // Set initial position and orientation of footprints
        updatePreviewFootprints(rotation: placementEntity.transform.rotation)
    }
    
    // Update preview footprints position and orientation
    func updatePreviewFootprints(rotation: simd_quatf) {
        guard let arView = arView,
              let placementEntity = placementEntity,
              let leftFootprintAnchor = leftFootprintAnchor,
              let rightFootprintAnchor = rightFootprintAnchor,
              let leftFootprintEntity = leftFootprintEntity,
              let rightFootprintEntity = rightFootprintEntity else { return }
        
        // Get placement entity's world position
        let cubeWorldTransform = placementEntity.transformMatrix(relativeTo: nil)
        let cubeWorldPosition = simd_make_float3(cubeWorldTransform.columns.3)
        
        // Define the local offsets (before rotation is applied)
        let leftLocalOffset = SIMD3<Float>(0.2, -0.04, -0.3)  // Left, down, opposite direction
        let rightLocalOffset = SIMD3<Float>(-0.2, -0.04, -0.3)  // Right, down, opposite direction
        
        // Create rotation matrix from quaternion
        let rotationMatrix = simd_matrix3x3(rotation)
        
        // Apply rotation to the offset vectors
        let rotatedLeftOffset = rotationMatrix * leftLocalOffset
        let rotatedRightOffset = rotationMatrix * rightLocalOffset
        
        // Calculate final world positions
        let leftPosition = cubeWorldPosition + rotatedLeftOffset
        let rightPosition = cubeWorldPosition + rotatedRightOffset
        
        // Update anchor positions
        leftFootprintAnchor.transform.translation = leftPosition
        rightFootprintAnchor.transform.translation = rightPosition
        
        // Create a 180-degree rotation to flip footprints around
        let flipRotation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        
        // Create the slight inward angles
        let leftAngle: Float = 0.05 * .pi  // ~9 degrees inward
        let rightAngle: Float = -0.05 * .pi  // ~9 degrees inward
        
        // Create rotations with inward angles
        let leftInwardRotation = simd_quatf(angle: leftAngle, axis: [0, 1, 0])
        let rightInwardRotation = simd_quatf(angle: rightAngle, axis: [0, 1, 0])
        
        // Combine rotations: first flip 180°, then apply cube rotation, then apply inward angle
        leftFootprintEntity.orientation = simd_mul(simd_mul(rotation, flipRotation), leftInwardRotation)
        rightFootprintEntity.orientation = simd_mul(simd_mul(rotation, flipRotation), rightInwardRotation)
        
        // Make footprints semi-transparent during preview
        if let leftMaterial = leftFootprintEntity.model?.materials.first as? SimpleMaterial,
           let rightMaterial = rightFootprintEntity.model?.materials.first as? SimpleMaterial {
            
            // Create semi-transparent versions of the materials
            let leftColor = UIColor.blue.withAlphaComponent(0.4)
            let rightColor = UIColor.green.withAlphaComponent(0.4)
            
            let newLeftMaterial = SimpleMaterial(color: leftColor, roughness: 0.4, isMetallic: false)
            let newRightMaterial = SimpleMaterial(color: rightColor, roughness: 0.4, isMetallic: false)
            
            leftFootprintEntity.model?.materials = [newLeftMaterial]
            rightFootprintEntity.model?.materials = [newRightMaterial]
        }
    }
    
    // Place cube by directly swapping entities within the same anchor
    func placeCube() {
        guard placementStage == .rotationAdjustment,
              let arView = arView,
              let mainAnchor = mainAnchor,
              let placementEntity = placementEntity,
              let cubeEntity = cubeEntity,
              let rotationRingEntity = rotationRingEntity,
              let leftFootprintEntity = leftFootprintEntity,
              let rightFootprintEntity = rightFootprintEntity else { return }
        
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
        
        // Update footprints to final versions (more opaque)
        finalizeFootprints()
        
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
    
    // Finalize footprints after cube placement
    func finalizeFootprints() {
        guard let leftFootprintEntity = leftFootprintEntity,
              let rightFootprintEntity = rightFootprintEntity else { return }
        
        // Make footprints more opaque for final placement
        if let leftMaterial = leftFootprintEntity.model?.materials.first as? SimpleMaterial,
           let rightMaterial = rightFootprintEntity.model?.materials.first as? SimpleMaterial {
            
            // Create more solid versions of the materials
            let leftColor = UIColor.blue.withAlphaComponent(0.7)
            let rightColor = UIColor.green.withAlphaComponent(0.7)
            
            let newLeftMaterial = SimpleMaterial(color: leftColor, roughness: 0.4, isMetallic: false)
            let newRightMaterial = SimpleMaterial(color: rightColor, roughness: 0.4, isMetallic: false)
            
            leftFootprintEntity.model?.materials = [newLeftMaterial]
            rightFootprintEntity.model?.materials = [newRightMaterial]
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
        
        // Create footprint models
        createFootprintModels()
        
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
        
        // Make sure we clean up any conflicting gesture recognizers
        cleanupRedundantGestureRecognizers()
    }
    
    // Clean up all existing entities
    func cleanupExistingEntities() {
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
        
        // Remove footprint anchors if they exist
        if let leftFootprintAnchor = leftFootprintAnchor {
            arView.scene.anchors.remove(leftFootprintAnchor)
            self.leftFootprintAnchor = nil
        }
        
        if let rightFootprintAnchor = rightFootprintAnchor {
            arView.scene.anchors.remove(rightFootprintAnchor)
            self.rightFootprintAnchor = nil
        }
        
        // Reset entity references
        self.leftFootprintEntity = nil
        self.rightFootprintEntity = nil
    }
    
    // Reset all state variables
    func resetState() {
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
    func exitPlacementMode() {
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
        // Note: We also keep the footprint anchors
        
        // Make sure we clean up any conflicting gesture recognizers
        cleanupRedundantGestureRecognizers()
        
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
                
                // Updated stability threshold to make it easier to achieve stability
                let STABILITY_THRESHOLD: Float = 0.01 // Increased from 0.005
                
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
                    // Get camera position and orientation
                    let cameraDirection = simd_make_float3(
                        -cameraTransform.columns.2.x,
                        0, // Zero out Y component to keep cube level with ground
                        -cameraTransform.columns.2.z
                    )
                    let normalizedDirection = simd_normalize(cameraDirection)

                    // Calculate the angle around Y axis (yaw) from the normalized direction
                    let rotationAngle = atan2(normalizedDirection.x, normalizedDirection.z)

                    // Create quaternion for rotation around Y axis
                    let targetRotation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))

                    placementEntity.transform.rotation = targetRotation
                    
                    // Reset local translation to prevent drift
                    placementEntity.transform.translation = .zero
                    
                    // Show and update footprints with current position and rotation
                    showPreviewFootprints()
                    updatePreviewFootprints(rotation: targetRotation)
                    
                    // Update UI with enhanced visual indicator
                    updatePlacementStatus(true, "Tap to adjust rotation")
                    updatePlacementColor(.green)
                } else {
                    // Not yet stable
                    updatePlacementStatus(false, "Hold steady...")
                    updatePlacementColor(.yellow)
                    
                    // If we have footprints and a valid position rotation, update their position
                    if leftFootprintAnchor != nil && rightFootprintAnchor != nil {
                        updatePreviewFootprints(rotation: placementEntity.transform.rotation)
                    }
                }
            } else {
                // Not enough samples yet, but if we have at least a few valid positions, show preview footprints
                if positionHistory.count >= 3 {
                    // Show preview footprints with current position and rotation
                    if leftFootprintAnchor == nil || rightFootprintAnchor == nil {
                        showPreviewFootprints()
                    }
                    updatePreviewFootprints(rotation: placementEntity.transform.rotation)
                }
                
                // Not enough samples
                updatePlacementStatus(false, "Hold steady...")
                updatePlacementColor(.yellow)
            }
        } else {
            positionUpdateCount += 1
            // Only clear after longer period of no detection (increased from 30 to 60 frames)
            if positionUpdateCount > 60 { // About 2 seconds at 30fps
                // Lost tracking for a while
                updatePlacementStatus(false, "Point at a flat surface")
                updatePlacementColor(.blue)
                positionHistory.removeAll()
            }
        }
    }
    
    // Helper to update placement status with enhanced visual indicator
    func updatePlacementStatus(_ stable: Bool, _ message: String) {
        DispatchQueue.main.async {
            self.positionStable = stable
            
            // Add extra indicator for when it's ready for tapping
            if stable {
                self.instructionText = "✓ " + message + " - Ready!"
            } else {
                self.instructionText = message
            }
        }
    }
    
    // Helper to update placement indicator color
    func updatePlacementColor(_ color: UIColor) {
        guard let placementEntity = placementEntity else { return }
        
        let material = SimpleMaterial(
            color: color.withAlphaComponent(0.5),
            roughness: 0.3,
            isMetallic: false
        )
        
        placementEntity.model?.materials = [material]
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
}
