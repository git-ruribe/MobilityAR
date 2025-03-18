//
//  BendingExerciseMode.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import RealityKit
import ARKit
import CoreHaptics

// Extension to ARViewModel for bending exercise functionality
extension ARViewModel {
    // MARK: - Bending Exercise Setup
    
    // Initialize exercise administration
    func setupExerciseAdministration() {
        exerciseAdmin = ExerciseAdministration()
    }
    
    // Enter bending exercise mode
    func enterBendingMode(configuration: ExerciseConfiguration? = nil) {
        guard let arView = arView else { return }
        
        // Hide cube during exercise (but we'll use its position)
        cubeEntity?.isEnabled = false
        
        // Configure exercise parameters
        let config = configuration ?? ExerciseAdministration().createDefaultBendingExercise()
        targetSphereHeight = config.startingHeight
        maxLevels = Int((config.startingHeight - config.minimumHeight) / config.stepDistance) + 1
        currentLevel = 1
        
        // Reset state variables
        isAdvancingLevel = false
        
        // Create visual elements
        createTargetSphere()
        createLevelDisplay()
        
        // Set up success particle system
        setupParticleEffect()
        
        // Create guidance elements
        createExerciseGuideElements()
        
        // Update state
        DispatchQueue.main.async {
            self.bendingMode = true
            self.exerciseComplete = false
            self.exerciseStarted = false
            self.instructionText = "Stand upright then tap screen to start the exercise"
        }
        

        
        // Initialize exercise tracking directly instead of calling the private method
        exerciseAdmin?.currentExerciseIndex = 0
        if let admin = exerciseAdmin,
           let session = admin.currentSession {
            admin.currentSession = session
        } else {
            // Create a default session if none exists
            let defaultConfig = ExerciseAdministration().createDefaultBendingExercise()
            let defaultSession = ExerciseSession(
                id: UUID(),
                name: "Quick Bending Exercise",
                dateCreated: Date(),
                exercises: [defaultConfig]
            )
            exerciseAdmin?.currentSession = defaultSession
        }
        
        // Trigger haptic feedback for mode change
        triggerModeChangeHapticFeedback()
    }
    
    // Exit bending mode
    func exitBendingMode(completed: Bool = false) {
        guard let arView = arView else { return }
        
        // Clean up exercise entities
        if let targetSphereAnchor = targetSphereAnchor {
            arView.scene.anchors.remove(targetSphereAnchor)
            self.targetSphereAnchor = nil
        }
        
        if let levelTextAnchor = levelTextAnchor {
            arView.scene.anchors.remove(levelTextAnchor)
            self.levelTextAnchor = nil
        }
        
        // Clean up guidance elements
        if let guideArrowAnchor = guideArrowAnchor {
            arView.scene.anchors.remove(guideArrowAnchor)
            self.guideArrowAnchor = nil
            self.guideArrowEntity = nil
        }
        
        if let progressTrackAnchor = progressTrackAnchor {
            arView.scene.anchors.remove(progressTrackAnchor)
            self.progressTrackAnchor = nil
            self.progressTrackEntity = nil
            self.progressMarkerEntity = nil
        }
        
        // Show cube again
        cubeEntity?.isEnabled = true
        
        // Record exercise completion
        if let stats = exerciseStats {
            // Only update stats if exercise was actually started and stats haven't been finalized
            if exerciseStarted && !exerciseComplete {
                var updatedStats = stats
                updatedStats.endTime = Date()
                updatedStats.reachedLevels = currentLevel - 1
                
                // Calculate max depth from height
                let startHeight = initialTargetHeight()
                let currentHeight = targetSphereHeight
                let depthReached = startHeight - currentHeight
                updatedStats.maxDepthReached = depthReached
                
                self.exerciseStats = updatedStats
                
                print("EXIT EXERCISE: Timer ended at \(Date())")
                print("Exercise duration: \(updatedStats.totalDuration)s")
            } else if !exerciseStarted {
                print("EXIT EXERCISE: Exercise was never started, no stats recorded")
            }
            
            // Record in exercise admin regardless if completed was requested
            if completed {
                exerciseAdmin?.completeCurrentExercise()
            }
        }
        
        // Update state
        DispatchQueue.main.async {
            self.bendingMode = false
            self.exerciseComplete = false
            self.instructionText = "Walk around the cube to explore"
        }
        
        // Trigger haptic feedback for mode change
        triggerModeChangeHapticFeedback()
        
        // Make sure we clean up any conflicting gesture recognizers
        cleanupRedundantGestureRecognizers()
    }
    
    // Start exercise after user is ready
    func startBendingExercise() {
        guard bendingMode, !exerciseStarted else { return }
        
        // Initialize exercise stats - MOVED FROM enterBendingMode
            exerciseStats = ExerciseStats(
                startTime: Date(), // This now happens when exercise actually starts
                endTime: nil,
                reachedLevels: 0,
                maxDepthReached: 0,
                repetitionTimes: []
            )
        
        DispatchQueue.main.async {
            self.exerciseStarted = true
            self.instructionText = "Bend down to reach the blue sphere"
        }
        
        // Start tracking this repetition
        levelStartTime = Date()
        exerciseAdmin?.startRepetition()
        
        // Position sphere at starting height
        positionTargetSphere(height: targetSphereHeight)
        
        // Trigger haptic feedback
        triggerExerciseStartHapticFeedback()
    }
    
    // MARK: - Target Sphere Management
    
    // Create target sphere for exercise
    func createTargetSphere() {
        guard let arView = arView else { return }
        
        // Create glowing sphere
        let sphereRadius: Float = 0.05 // 10cm radius
        let sphereMesh = MeshResource.generateSphere(radius: sphereRadius)
        
        // Create material with emission for glow effect
        var material = SimpleMaterial()
        material.baseColor = MaterialColorParameter.color(UIColor.blue.withAlphaComponent(0.7))
        material.roughness = MaterialScalarParameter(0.3)
        material.metallic = MaterialScalarParameter(0.8)
        
        // Create entity
        let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
        
        // Add light to make it more visible
        let light = PointLightComponent(
            color: .blue,
            intensity: 500,
            attenuationRadius: 0.5
        )
        sphereEntity.components.set(light)
        
        // Create anchor positioned above the cube
        let initialPosition = getInitialSpherePosition()
        let sphereAnchor = AnchorEntity(world: initialPosition)
        sphereAnchor.addChild(sphereEntity)
        
        // Add collision for hit testing
        let collisionShape = ShapeResource.generateSphere(radius: sphereRadius)
        sphereEntity.collision = CollisionComponent(shapes: [collisionShape])
        
        // Add to scene
        arView.scene.addAnchor(sphereAnchor)
        
        // Store references
        self.targetSphereEntity = sphereEntity
        self.targetSphereAnchor = sphereAnchor
        
        // Store the initial X and Z coordinates to keep sphere positioned vertically
        self.initialSpherePositionXYZ = SIMD3<Float>(initialPosition.x, initialPosition.y, initialPosition.z)
    }
    
    // Create level text display
    func createLevelDisplay() {
        guard let arView = arView,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        // Create text mesh
        let textMesh = MeshResource.generateText(
            "Level \(currentLevel) of \(maxLevels)",
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        // Create material
        var material = SimpleMaterial()
        material.baseColor = MaterialColorParameter.color(.white)
        material.roughness = MaterialScalarParameter(0.0)
        material.metallic = MaterialScalarParameter(0.0)
        
        // Create entity
        let textEntity = ModelEntity(mesh: textMesh, materials: [material])
        
        // Size and position correctly
        textEntity.scale = [0.5, 0.5, 0.5]
        
        // Create anchor positioned above the sphere
        let textPosition = targetSphereAnchor.transform.translation + SIMD3<Float>(0, 0.2, 0)
        let textAnchor = AnchorEntity(world: textPosition)
        textAnchor.addChild(textEntity)
        
        // Add to scene
        arView.scene.addAnchor(textAnchor)
        
        // Store references
        self.levelTextEntity = textEntity
        self.levelTextAnchor = textAnchor
    }
    
    // Update level text
    func updateLevelDisplay() {
        guard let levelTextEntity = levelTextEntity,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        // Create new text mesh with updated level
        let textMesh = MeshResource.generateText(
            "Level \(currentLevel) of \(maxLevels)",
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: 0.05),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        
        // Update mesh
        levelTextEntity.model?.mesh = textMesh
        
        // Update position to remain above sphere
        if let levelTextAnchor = levelTextAnchor {
            let newPosition = targetSphereAnchor.transform.translation + SIMD3<Float>(0, 0.2, 0)
            levelTextAnchor.transform.translation = newPosition
        }
    }
    
    // Create visual guidance elements for exercise
    func createExerciseGuideElements() {
        createProgressTrack()
        createDirectionalArrow()
    }
    
    // Create progress track indicator
    func createProgressTrack() {
        guard let arView = arView,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        // Calculate track height - distance from min to max height
        let trackHeight = initialTargetHeight() - (initialTargetHeight() - Float(maxLevels - 1) * 0.1)
        
        // Create track entity
        let trackWidth: Float = 0.02
        let trackDepth: Float = 0.02
        let trackMesh = MeshResource.generateBox(size: [trackWidth, trackHeight, trackDepth], cornerRadius: 0.005)
        let trackMaterial = SimpleMaterial(color: UIColor.gray.withAlphaComponent(0.5), roughness: 0.5, isMetallic: false)
        let trackEntity = ModelEntity(mesh: trackMesh, materials: [trackMaterial])
        
        // Create progress marker (sphere)
        let markerRadius: Float = 0.025
        let markerMesh = MeshResource.generateSphere(radius: markerRadius)
        let markerMaterial = SimpleMaterial(color: .yellow.withAlphaComponent(0.9), roughness: 0.3, isMetallic: true)
        let markerEntity = ModelEntity(mesh: markerMesh, materials: [markerMaterial])
        
        // Create light to make marker more visible
        let light = PointLightComponent(
            color: .yellow,
            intensity: 300,
            attenuationRadius: 0.3
        )
        markerEntity.components.set(light)
        
        // Position marker at top of track initially
        markerEntity.position = [0, trackHeight/2 - markerRadius, trackWidth]
        trackEntity.addChild(markerEntity)
        
        // Position track to the side of exercise area
        let spherePos = targetSphereAnchor.transform.translation
        let trackPosition = SIMD3<Float>(
            spherePos.x + 0.4, // 40cm to the side
            spherePos.y - trackHeight/2, // Bottom aligned with floor
            spherePos.z
        )
        
        let trackAnchor = AnchorEntity(world: trackPosition)
        trackAnchor.addChild(trackEntity)
        
        // Add to scene
        arView.scene.addAnchor(trackAnchor)
        
        // Store references
        self.progressTrackEntity = trackEntity
        self.progressMarkerEntity = markerEntity
        self.progressTrackAnchor = trackAnchor
        
        // Update progress marker to starting position
        updateProgressMarker()
    }
    
    // Create directional arrow for exercise guidance
    func createDirectionalArrow() {
        guard let arView = arView,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        // Create arrow shaft
        let shaftWidth: Float = 0.02
        let shaftHeight: Float = 0.12
        let shaftDepth: Float = 0.02
        let shaftMesh = MeshResource.generateBox(size: [shaftWidth, shaftHeight, shaftDepth])
        let arrowMaterial = SimpleMaterial(color: UIColor.white.withAlphaComponent(0.7), roughness: 0.3, isMetallic: true)
        let arrowEntity = ModelEntity(mesh: shaftMesh, materials: [arrowMaterial])
        
        // Create arrow head
        let headWidth: Float = 0.06
        let headHeight: Float = 0.04
        let headDepth: Float = 0.02
        let headMesh = MeshResource.generateBox(size: [headWidth, headHeight, headDepth])
        let headEntity = ModelEntity(mesh: headMesh, materials: [arrowMaterial])
        
        // Position head at bottom of shaft
        headEntity.position = [0, -shaftHeight/2 - headHeight/2, 0]
        arrowEntity.addChild(headEntity)
        
        // Position arrow above the target sphere
        let spherePos = targetSphereAnchor.transform.translation
        let arrowPosition = SIMD3<Float>(
            spherePos.x,
            spherePos.y + 0.3, // 30cm above sphere
            spherePos.z
        )
        
        let arrowAnchor = AnchorEntity(world: arrowPosition)
        arrowAnchor.addChild(arrowEntity)
        
        // Add to scene
        arView.scene.addAnchor(arrowAnchor)
        
        // Store references
        self.guideArrowEntity = arrowEntity
        self.guideArrowAnchor = arrowAnchor
        
        // Animate arrow continuously
        animateDirectionalArrow()
    }
    
    // Animate directional arrow up and down
    func animateDirectionalArrow() {
        guard let arrowEntity = guideArrowEntity,
              let arrowAnchor = guideArrowAnchor,
              bendingMode else { return }
        
        // Define animation parameters
        let moveUp = Transform(translation: [0, 0.05, 0])
        let moveDown = Transform(translation: [0, -0.05, 0])
        let animationDuration: TimeInterval = 1.0
        
        // Animate down
        arrowEntity.move(to: moveDown, relativeTo: arrowAnchor, duration: animationDuration)
        
        // Then animate up and repeat
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            arrowEntity.move(to: moveUp, relativeTo: arrowAnchor, duration: animationDuration)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                if self.bendingMode && !self.exerciseComplete {
                    self.animateDirectionalArrow()
                }
            }
        }
    }
    
    // Update progress marker position based on current level
    func updateProgressMarker() {
        guard let progressMarkerEntity = progressMarkerEntity,
              let progressTrackEntity = progressTrackEntity else { return }
        
        // Calculate progress percentage
        let levelProgress = Float(currentLevel - 1) / Float(maxLevels - 1)
        
        // Get track height from entity bounds
        let trackHeight = progressTrackEntity.visualBounds(relativeTo: progressTrackEntity).extents.y
        
        // Calculate new position - move from top to bottom as progress increases
        let startY = trackHeight/2 - 0.025 // Offset by marker radius
        let endY = -trackHeight/2 + 0.025 // Offset by marker radius
        let newY = startY - levelProgress * (startY - endY)
        
        // Only update if significant change
        if abs(progressMarkerEntity.position.y - newY) > 0.01 {
            var newTransform = progressMarkerEntity.transform
            newTransform.translation.y = newY
            
            // Animate marker movement
            progressMarkerEntity.move(to: newTransform, relativeTo: progressTrackEntity, duration: 0.3)
        }
    }
    
    // Move target sphere down to next level
    func advanceToNextLevel() {
        guard bendingMode, exerciseStarted, !exerciseComplete, currentLevel < maxLevels, !isAdvancingLevel else {
            if currentLevel >= maxLevels {
                completeExercise()
            }
            return
        }
        
        // Set advancing flag to prevent multiple triggers
        isAdvancingLevel = true
        
        // Record time for current level
        if let startTime = levelStartTime {
            let duration = Date().timeIntervalSince(startTime)
            exerciseStats?.repetitionTimes.append(duration)
            
            // Report to exercise admin
            exerciseAdmin?.completeRepetition(depthReached: targetSphereHeight)
        }
        
        // Increment level
        currentLevel += 1
        
        // Update UI first with countdown indicator
        DispatchQueue.main.async {
            self.instructionText = "Level \(self.currentLevel): Get Ready..."
        }
        
        // Animate countdown before dropping sphere
        animateCountdown(from: 3) {
            // Lower sphere by step distance
            self.targetSphereHeight -= 0.1 // 10cm per level
            
            // Update target position
            self.positionTargetSphere(height: self.targetSphereHeight)
            
            // Update level display
            self.updateLevelDisplay()
            
            // Update progress marker
            self.updateProgressMarker()
            
            // Reset level timer
            self.levelStartTime = Date()
            self.exerciseAdmin?.startRepetition()
            
            // Update instruction
            DispatchQueue.main.async {
                self.instructionText = "Level \(self.currentLevel): Bend down to reach the sphere"
            }
            
            // Trigger success haptic feedback
            self.triggerSuccessHapticFeedback()
            
            // Reset advancing flag after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isAdvancingLevel = false
            }
        }
    }
    
    // Animate countdown between levels
    func animateCountdown(from count: Int, completion: @escaping () -> Void) {
        guard count > 0 else {
            completion()
            return
        }
        
        // Show count on screen
        DispatchQueue.main.async {
            self.instructionText = "Next level in \(count)..."
        }
        
        // Trigger light haptic
        triggerLightHapticFeedback()
        
        // Recursively countdown
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.animateCountdown(from: count - 1, completion: completion)
        }
    }
    
    // Light haptic for countdown
    func triggerLightHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
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
    
    // Complete the exercise
    func completeExercise() {
        // Record final level time
        if let startTime = levelStartTime {
            let duration = Date().timeIntervalSince(startTime)
            exerciseStats?.repetitionTimes.append(duration)
            
            // Report to exercise admin
            let finalDepth = initialTargetHeight() - targetSphereHeight
            exerciseAdmin?.completeRepetition(depthReached: finalDepth)
        }
        
        // Calculate performance score
        let levelScore = Float(currentLevel) / Float(maxLevels) * 50.0  // Up to 50 points for levels
        
        // Time score
        var timeScore: Float = 0
        if let stats = exerciseStats, !stats.repetitionTimes.isEmpty {
            let avgTime = Float(stats.averageRepTime)
            // Optimal time is 2-4 seconds per rep
            if avgTime < 2.0 {
                timeScore = 20 * (avgTime / 2.0)  // Reduced score if too fast
            } else if avgTime > 6.0 {
                timeScore = 20 * (6.0 / avgTime)  // Reduced score if too slow
            } else {
                timeScore = 20 * (1.0 - (avgTime - 2.0) / 4.0)  // Full score for optimal time
            }
        }
        
        // Consistency score
        var consistencyScore: Float = 30.0
        if let stats = exerciseStats, stats.repetitionTimes.count > 1 {
            let times = stats.repetitionTimes
            let avgTime = times.reduce(0, +) / Double(times.count)
            
            // Calculate standard deviation
            let sumSquaredDiff = times.reduce(0) { $0 + pow($1 - avgTime, 2) }
            let stdDev = sqrt(sumSquaredDiff / Double(times.count))
            
            // Convert to a score - lower stdDev is better
            let normalizedStdDev = min(Float(stdDev / avgTime), 1.0)  // Relative to average
            consistencyScore = 30.0 * (1.0 - normalizedStdDev)
        }
        
        // Calculate total score
        let totalScore = Int(levelScore + timeScore + consistencyScore)
        
        // IMPORTANT: Update the stats with final values
        // This section needs to be more comprehensive
        if var stats = exerciseStats {
            // Set the end time to now
            stats.endTime = Date()
            
            // Update reached levels (current level minus 1 since we're ending)
            stats.reachedLevels = currentLevel - 1
            
            // Calculate max depth from height
            let startHeight = initialTargetHeight()
            let currentHeight = targetSphereHeight
            let depthReached = startHeight - currentHeight
            stats.maxDepthReached = depthReached
            
            // Store the performance score
            stats.performanceScore = totalScore
            
            // Update the stats in the view model
            self.exerciseStats = stats
        }

        DispatchQueue.main.async {
            self.exerciseComplete = true
            self.instructionText = "Exercise complete! Great job!"
        }
        
        // Trigger completion haptic feedback
        triggerCompletionHapticFeedback()
        
        // Add completion animation to sphere
        animateSphereCompletion()
        
        // No longer automatically exit - let user press Continue
    }
    
    // MARK: - Position Calculations
    
    // Get initial sphere position - centered above the cube
    func getInitialSpherePosition() -> SIMD3<Float> {
        if let cubeEntity = cubeEntity {
            // Position above cube at starting height
            let cubeWorldPosition = cubeEntity.transformMatrix(relativeTo: nil).columns.3
            return SIMD3<Float>(
                cubeWorldPosition.x,
                cubeWorldPosition.y, //+ targetSphereHeight, // Use the specified height from floor
                cubeWorldPosition.z
            )
        } else {
            // Fallback - in front of camera
            guard let frame = arView?.session.currentFrame else {
                return SIMD3<Float>(0, targetSphereHeight, 0)
            }
            
            let cameraPosition = frame.camera.transform.columns.3
            let cameraForward = -simd_normalize(simd_make_float3(frame.camera.transform.columns.2))
            
            // Position in front of user but at specified height
            var position = simd_make_float3(cameraPosition) + cameraForward * 1.0
            position.y = targetSphereHeight
            
            return position
        }
    }
    
    // Position the target sphere at specific height while maintaining XZ position
    func positionTargetSphere(height: Float) {
        guard let targetSphereAnchor = targetSphereAnchor else { return }
        
        // Calculate new position - maintain XZ coordinates, only change height
        var newPosition: SIMD3<Float>
        
        if let xyz = initialSpherePositionXYZ {
            // Keep original XZ coordinates, only change Y
            newPosition = SIMD3<Float>(xyz.x, xyz.y + height, xyz.z)
        } else {
            // Fallback - get current XZ, change Y
            let current = targetSphereAnchor.transform.translation
            newPosition = SIMD3<Float>(current.x, height, current.z)
        }
        
        // Update position with animation
        var transform = targetSphereAnchor.transform
        transform.translation = newPosition
        
        // Animate the change
        targetSphereAnchor.move(to: transform, relativeTo: nil, duration: 0.3)
        
        // Update level text position
        updateLevelTextPosition()
        
        // Update arrow position
        updateArrowPosition()
    }
    
    // Update level text position to stay above sphere
    func updateLevelTextPosition() {
        guard let levelTextAnchor = levelTextAnchor,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        let spherePosition = targetSphereAnchor.transform.translation
        let textPosition = SIMD3<Float>(
            spherePosition.x,
            spherePosition.y + 0.2, // 20cm above sphere
            spherePosition.z
        )
        
        var transform = levelTextAnchor.transform
        transform.translation = textPosition
        
        levelTextAnchor.move(to: transform, relativeTo: nil, duration: 0.3)
    }
    
    // Update directional arrow position
    func updateArrowPosition() {
        guard let guideArrowAnchor = guideArrowAnchor,
              let targetSphereAnchor = targetSphereAnchor else { return }
        
        let spherePosition = targetSphereAnchor.transform.translation
        let arrowPosition = SIMD3<Float>(
            spherePosition.x,
            spherePosition.y + 0.3, // 30cm above sphere
            spherePosition.z
        )
        
        var transform = guideArrowAnchor.transform
        transform.translation = arrowPosition
        
        guideArrowAnchor.move(to: transform, relativeTo: nil, duration: 0.3)
    }
    
    // Get initial height for analytics
    func initialTargetHeight() -> Float {
        return exerciseAdmin?.currentSession?.exercises[exerciseAdmin?.currentExerciseIndex ?? 0].startingHeight ?? 1.0
    }
    
    // MARK: - Interaction Detection
    
    // Check if camera has reached the target sphere
    func checkSphereInteraction(frame: ARFrame) {
        guard bendingMode, exerciseStarted, !exerciseComplete, !isAdvancingLevel else { return }
        
        // Get camera position
        let cameraPosition = simd_make_float3(frame.camera.transform.columns.3)
        
        // Get sphere position
        guard let spherePosition = targetSphereEntity?.position(relativeTo: nil) else { return }
        
        // Calculate distance
        let distance = simd_distance(cameraPosition, spherePosition)
        
        // Track approach progress for visual feedback
        let maxApproachDistance: Float = 0.65 // Start feedback at 65cm
        let minApproachDistance: Float = 0.15 // Target is reached at 15cm
        
        let approachProgress = 1.0 - max(0, min(1, (distance - minApproachDistance) / (maxApproachDistance - minApproachDistance)))
        updateSphereApproachFeedback(progress: approachProgress)
        
        // If within 15cm of sphere center (sphere radius + margin), count as reached
        if distance < 0.05 {
            highlightSphereReached()
            advanceToNextLevel()
        }
    }
    
    // Update visual feedback as user approaches target
    func updateSphereApproachFeedback(progress: Float) {
        guard let targetSphereEntity = targetSphereEntity, progress > 0 else { return }
        
        // Change sphere color intensity based on proximity
        if var material = targetSphereEntity.model?.materials.first as? SimpleMaterial {
            // Only update if significant change to avoid constant material updates
            if progress > 0.2 {
                // Calculate color based on progress
                let r = 0.3 * progress
                let g = 0.3 + (0.5 * progress)
                let b = 1.0
                let a = 0.7 + (0.3 * progress)
                
                let highlightColor = UIColor(
                    red: CGFloat(r),
                    green: CGFloat(g),
                    blue: CGFloat(b),
                    alpha: CGFloat(a)
                )
                
                material.baseColor = MaterialColorParameter.color(highlightColor)
                targetSphereEntity.model?.materials = [material]
                
                // Update light intensity too
                if var light = targetSphereEntity.components[PointLightComponent.self] {
                    light.intensity = 500 + (500 * progress)
                    targetSphereEntity.components[PointLightComponent.self] = light
                }
            }
        }
        
        // Scale increase as you get closer
        if progress > 0.5 {
            let scaleIncrease = 1.0 + (0.1 * progress)
            let newScale = SIMD3<Float>(repeating: scaleIncrease)
            
            // Only update if significant change to avoid constant animations
            if abs(targetSphereEntity.scale.x - newScale.x) > 0.01 {
                var newTransform = targetSphereEntity.transform
                newTransform.scale = newScale
                targetSphereEntity.transform = newTransform
            }
        }
    }
    
    // Visual feedback when sphere is successfully reached
    func highlightSphereReached() {
        guard let targetSphereEntity = targetSphereEntity, !isAdvancingLevel else { return }
        
        // Pulse animation
        let originalScale = targetSphereEntity.transform.scale
        let pulseUp = Transform(scale: originalScale * 1.3)
        let pulseDown = Transform(scale: originalScale)
        
        // Quick pulse animation
        targetSphereEntity.move(to: pulseUp, relativeTo: targetSphereEntity.parent, duration: 0.1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            targetSphereEntity.move(to: pulseDown, relativeTo: targetSphereEntity.parent, duration: 0.1)
        }
        
        // Briefly change color
        if var material = targetSphereEntity.model?.materials.first as? SimpleMaterial {
            let originalColor = material.baseColor
            
            // Change to bright green for success
            material.baseColor = MaterialColorParameter.color(UIColor.green.withAlphaComponent(0.8))
            targetSphereEntity.model?.materials = [material]
            
            // Also update light color
            if var light = targetSphereEntity.components[PointLightComponent.self] {
                light.color = .green
                targetSphereEntity.components[PointLightComponent.self] = light
            }
            
            // Revert after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if var revertMaterial = targetSphereEntity.model?.materials.first as? SimpleMaterial {
                    revertMaterial.baseColor = originalColor
                    targetSphereEntity.model?.materials = [revertMaterial]
                }
                
                // Revert light color
                if var revertLight = targetSphereEntity.components[PointLightComponent.self] {
                    revertLight.color = .blue
                    targetSphereEntity.components[PointLightComponent.self] = revertLight
                }
            }
        }
    }
    
    // MARK: - Visual Effects
    
    // Setup simplified visual feedback for successful reaches
    func setupParticleEffect() {
        // We'll use color changes and scale animations instead of particles
        // due to compatibility issues with ParticleEmitterComponent
        guard let targetSphereEntity = targetSphereEntity else { return }
        
        // Store reference to use this entity for effects later
        self.successParticleSystem = nil
    }
    
    // Animate sphere on exercise completion
    func animateSphereCompletion() {
        guard let targetSphereEntity = targetSphereEntity else { return }
        
        // Animate scale
        let scaleUp = Transform(scale: [1.5, 1.5, 1.5])
        let scaleDown = Transform(scale: [1.0, 1.0, 1.0])
        
        // Pulse animation
        targetSphereEntity.move(to: scaleUp, relativeTo: targetSphereEntity.parent, duration: 0.3)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            targetSphereEntity.move(to: scaleDown, relativeTo: targetSphereEntity.parent, duration: 0.3)
            
            // Change sphere color to green for completion
            if var material = targetSphereEntity.model?.materials.first as? SimpleMaterial {
                material.baseColor = MaterialColorParameter.color(UIColor.green.withAlphaComponent(0.7))
                targetSphereEntity.model?.materials = [material]
                
                // Update light color too
                if var light = targetSphereEntity.components[PointLightComponent.self] {
                    light.color = .green
                    targetSphereEntity.components[PointLightComponent.self] = light
                }
            }
        }
    }
    
    // MARK: - Haptic Feedback
    
    // Haptic feedback for exercise start
    func triggerExerciseStartHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Double tap pattern
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.2))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Haptic feedback for successful reach
    func triggerSuccessHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Success pattern - sharp tap with a gentle follow-up
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        
        let secondIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
        let secondSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [secondIntensity, secondSharpness], relativeTime: 0.1))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Haptic feedback for exercise completion
    func triggerCompletionHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Completion pattern - celebratory sequence
        let firstIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
        let firstSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [firstIntensity, firstSharpness], relativeTime: 0))
        
        let secondIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8)
        let secondSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [secondIntensity, secondSharpness], relativeTime: 0.15))
        
        let thirdIntensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
        let thirdSharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [thirdIntensity, thirdSharpness], relativeTime: 0.3))
        
        // Add a continuous buzz as finale
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
            ],
            relativeTime: 0.4,
            duration: 0.4
        ))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // MARK: - Additional Integration
    
    // Track exercise in updated session delegate
    func updateBendingExercise(frame: ARFrame) {
        if bendingMode && exerciseStarted && !exerciseComplete {
            checkSphereInteraction(frame: frame)
        }
    }
    
    // Handle tap gesture for starting exercise
    @objc func handleBendingTap(_ gesture: UITapGestureRecognizer) {
        if bendingMode && !exerciseStarted {
            // Handle bending mode tap
            startBendingExercise()
        } else if placementMode && positionStable && placementStage == .positionSelection {
            // Only call placement handler when we're actually expecting it
            // and the position is stable for tap
            handleTap(gesture)
        }
    }
}

// Note: The SessionDelegate class in InteractionMode.swift
// should be updated to call updateBendingExercise in its
// session(_:didUpdate:) method
