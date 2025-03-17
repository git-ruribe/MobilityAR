//
//  DrawingMode.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import RealityKit
import ARKit
import CoreHaptics

// Drawing colors enum
enum DrawingColor: Int, CaseIterable {
    case red, green, blue, yellow, purple
    
    var uiColor: UIColor {
        switch self {
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
        case .purple: return .purple
        }
    }
    
    var name: String {
        switch self {
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .purple: return "Purple"
        }
    }
}

// Structure to store drawing point data
struct DrawingPoint {
    let position: SIMD3<Float>
    let color: DrawingColor
}

// Extension to ARViewModel for drawing mode functionality
extension ARViewModel {
    // Draw a sphere at the current camera position
    func drawSphereAtCameraPosition() {
        guard let arView = arView,
              let cameraTransform = arView.session.currentFrame?.camera.transform else { return }
        
        // Extract camera position
        let cameraPosition = simd_make_float3(cameraTransform.columns.3)
        
        // Create and place drawing sphere
        createDrawingSphere(at: cameraPosition, color: selectedDrawingColor)
        
        // Trigger haptic feedback
        triggerDrawingHapticFeedback()
        
        // Store point data for persistence
        let newPoint = DrawingPoint(position: cameraPosition, color: selectedDrawingColor)
        drawingPoints.append(newPoint)
        
        // Update last drawing position
        lastDrawingPosition = cameraPosition
    }
    
    // Create a drawing sphere entity
    func createDrawingSphere(at position: SIMD3<Float>, color: DrawingColor) {
        guard let arView = arView else { return }
        
        // Create sphere mesh
        let sphereMesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: color.uiColor, roughness: 0.2, isMetallic: true)
        let sphereEntity = ModelEntity(mesh: sphereMesh, materials: [material])
        
        // Create anchor at world position
        let sphereAnchor = AnchorEntity(world: position)
        sphereAnchor.addChild(sphereEntity)
        
        // Add to scene
        arView.scene.addAnchor(sphereAnchor)
        
        // Store reference
        drawingAnchors.append(sphereAnchor)
    }
    
    // Enter drawing mode
    func enterDrawingMode() {
        guard let arView = arView else { return }
        
        // Update state
        DispatchQueue.main.async {
            self.drawingMode = true
            self.isDrawingActive = false // Start with drawing inactive
            self.instructionText = "Touch and hold screen to draw - points placed every 5cm"
        }
        
        // Reset tracking for fresh camera movement detection
        lastDrawingPosition = simd_make_float3(arView.session.currentFrame?.camera.transform.columns.3 ?? SIMD4(0, 0, 0, 1))
        
        // Add long press gesture recognizer for drawing
        addDrawingGestureRecognizer()
        
        // Trigger haptic feedback for mode change
        triggerModeChangeHapticFeedback()
    }
    
    // Exit drawing mode
    func exitDrawingMode() {
        // Update state
        DispatchQueue.main.async {
            self.drawingMode = false
            self.isDrawingActive = false
            self.instructionText = "Walk around the cube to explore"
        }
        
        // Remove drawing gesture recognizer
        removeDrawingGestureRecognizer()
        
        // Trigger haptic feedback for mode change
        triggerModeChangeHapticFeedback()
    }
    
    // Recreate all stored drawing points
    func reloadDrawingPoints() {
        // Clear existing anchors first
        clearDrawingAnchors()
        
        // Recreate all points from stored data
        for point in drawingPoints {
            createDrawingSphere(at: point.position, color: point.color)
        }
    }
    
    // Clear all drawing spheres
    func clearDrawing() {
        guard let arView = arView else { return }
        
        // Remove all drawing anchors
        for anchor in drawingAnchors {
            arView.scene.anchors.remove(anchor)
        }
        
        // Clear arrays
        drawingAnchors.removeAll()
        drawingPoints.removeAll()
        
        // Reset last position
        if let currentPosition = arView.session.currentFrame?.camera.transform.columns.3 {
            lastDrawingPosition = simd_make_float3(currentPosition)
        }
        
        // Update UI
        DispatchQueue.main.async {
            self.instructionText = "Drawing cleared"
        }
        
        // Trigger haptic feedback
        triggerClearHapticFeedback()
    }
    
    // Clear only anchors (used when recreating)
    private func clearDrawingAnchors() {
        guard let arView = arView else { return }
        
        // Remove all drawing anchors
        for anchor in drawingAnchors {
            arView.scene.anchors.remove(anchor)
        }
        
        // Clear anchor array only (keep points data)
        drawingAnchors.removeAll()
    }
    
    // Set the current drawing color
    func setDrawingColor(_ color: DrawingColor) {
        DispatchQueue.main.async {
            self.selectedDrawingColor = color
            self.instructionText = "Selected color: \(color.name)"
        }
        
        // Light haptic feedback
        triggerColorSelectHapticFeedback()
    }
    
    // Track camera movement for drawing
    func trackCameraForDrawing(frame: ARFrame) {
        // Only track when in drawing mode AND user is touching screen
        guard drawingMode && isDrawingActive else { return }
        
        // Get current camera position
        let cameraPosition = simd_make_float3(frame.camera.transform.columns.3)
        
        // Calculate distance from last drawing position
        let distance = simd_distance(cameraPosition, lastDrawingPosition)
        
        // Check if we've moved enough to place a new point (5cm threshold)
        if distance >= 0.05 { // 5cm in meters
            drawSphereAtCameraPosition()
        }
    }
    
    // Haptic feedback for drawing
    func triggerDrawingHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Light tap for drawing
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4)
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
    
    // Haptic feedback for mode change
    func triggerModeChangeHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Double tap for mode change
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.1))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Haptic feedback for color selection
    func triggerColorSelectHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Very light tap for color selection
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        
        events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0))
        
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            print("Failed to play haptic pattern: \(error)")
        }
    }
    
    // Haptic feedback for clearing drawing
    func triggerClearHapticFeedback() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }
        
        var events = [CHHapticEvent]()
        
        // Rumble effect for clear
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
        
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensity, sharpness],
            relativeTime: 0,
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
    
    // Drawing touch gesture handlers
    
    // Add long press gesture recognizer for drawing
    private func addDrawingGestureRecognizer() {
        guard let arView = arView else { return }
        
        // Create and store the long press gesture
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleDrawingTouch(_:)))
        longPressGesture.minimumPressDuration = 0.1 // Very short to detect almost immediate touches
        longPressGesture.allowableMovement = 500 // Allow movement while pressed
        longPressGesture.name = "drawingGesture" // Tag for identification
        
        arView.addGestureRecognizer(longPressGesture)
    }
    
    // Remove drawing gesture recognizer
    private func removeDrawingGestureRecognizer() {
        guard let arView = arView else { return }
        
        // Find and remove the drawing gesture
        for gesture in arView.gestureRecognizers ?? [] {
            if let longPress = gesture as? UILongPressGestureRecognizer, longPress.name == "drawingGesture" {
                arView.removeGestureRecognizer(longPress)
            }
        }
    }
    
    // Handle drawing touch events
    @objc func handleDrawingTouch(_ gesture: UILongPressGestureRecognizer) {
        guard drawingMode else { return }
        
        switch gesture.state {
        case .began:
            // Start drawing
            DispatchQueue.main.async {
                self.isDrawingActive = true
                self.instructionText = "Drawing... move camera to create trail"
            }
            
            // Reset position tracking to current position
            if let currentFrame = arView?.session.currentFrame {
                lastDrawingPosition = simd_make_float3(currentFrame.camera.transform.columns.3)
            }
            
            // Haptic feedback when starting to draw
            triggerDrawingHapticFeedback()
            
        case .changed:
            // Keep drawing - nothing to do here as tracking happens in update loop
            break
            
        case .ended, .cancelled, .failed:
            // Stop drawing
            DispatchQueue.main.async {
                self.isDrawingActive = false
                self.instructionText = "Touch and hold screen to draw - points placed every 5cm"
            }
            
        default:
            break
        }
    }
}
