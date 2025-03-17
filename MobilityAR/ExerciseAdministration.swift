//
//  ExerciseAdministration.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import Foundation
import SwiftUI
import RealityKit

// MARK: - Joint Tracking

enum JointType: String, Codable, CaseIterable {
    case hip
    case knee
    case ankle
    case shoulder
    case elbow
    case wrist
    case neck
    case upperBack
    case lowerBack
    
    var displayName: String {
        switch self {
        case .hip: return "Hip"
        case .knee: return "Knee"
        case .ankle: return "Ankle"
        case .shoulder: return "Shoulder"
        case .elbow: return "Elbow"
        case .wrist: return "Wrist"
        case .neck: return "Neck"
        case .upperBack: return "Upper Back"
        case .lowerBack: return "Lower Back"
        }
    }
}

// MARK: - Exercise Types

enum ExerciseType: String, Codable, CaseIterable {
    case bending
    case sideReach
    case frontReach
    case squat
    
    var displayName: String {
        switch self {
        case .bending: return "Forward Bend"
        case .sideReach: return "Side Reach"
        case .frontReach: return "Front Reach"
        case .squat: return "Squat"
        }
    }
    
    // Define which joints are primarily and secondarily worked by each exercise
    var primaryJoints: [JointType] {
        switch self {
        case .bending: return [.hip, .knee]
        case .sideReach: return [.shoulder, .hip]
        case .frontReach: return [.shoulder]
        case .squat: return [.knee, .hip]
        }
    }
    
    var secondaryJoints: [JointType] {
        switch self {
        case .bending: return [.ankle, .lowerBack]
        case .sideReach: return [.upperBack, .elbow]
        case .frontReach: return [.elbow, .wrist]
        case .squat: return [.ankle, .lowerBack]
        }
    }
}

// MARK: - Exercise Configuration

struct ExerciseConfiguration: Codable, Identifiable {
    var id = UUID()
    var type: ExerciseType
    var repetitions: Int = 1
    var startingHeight: Float = 1.0 // meters
    var minimumHeight: Float = 0.1 // meters
    var stepDistance: Float = 0.1 // meters down each successful reach
    var timeLimit: TimeInterval? = nil // Optional time limit for the exercise
}

// MARK: - Exercise Performance Metrics

struct JointMetric: Codable, Identifiable {
    var id = UUID()
    var joint: JointType
    var rangeOfMotion: Float // In degrees or appropriate unit
    var workload: Int // Number of times this joint was exercised
}

struct ExercisePerformance: Codable, Identifiable {
    var id = UUID()
    var exerciseType: ExerciseType
    var dateCompleted: Date
    var repetitionsCompleted: Int
    var maxDepthReached: Float // In meters from floor
    var totalDuration: TimeInterval
    var avgTimePerRep: TimeInterval
    var jointMetrics: [JointMetric]
    
    // Additional metrics
    var stabilityScore: Int? // 0-100 score measuring steadiness
    var movementSmoothnessScore: Int? // 0-100 score for smooth motion
}

// MARK: - Session Tracking

struct ExerciseSession: Codable, Identifiable {
    var id = UUID()
    var name: String
    var dateCreated: Date
    var exercises: [ExerciseConfiguration]
    var performances: [ExercisePerformance] = []
    var notes: String = ""
    var completed: Bool = false
    var dateCompleted: Date?
    
    var totalDuration: TimeInterval {
        performances.reduce(0) { $0 + $1.totalDuration }
    }
    
    var jointsSummary: [JointType: (primary: Int, secondary: Int)] {
        var summary: [JointType: (primary: Int, secondary: Int)] = [:]
        
        // Initialize all joints with zero counts
        for joint in JointType.allCases {
            summary[joint] = (primary: 0, secondary: 0)
        }
        
        // Count exercises for each joint
        for exercise in exercises {
            for joint in exercise.type.primaryJoints {
                let current = summary[joint] ?? (primary: 0, secondary: 0)
                summary[joint] = (primary: current.primary + exercise.repetitions, secondary: current.secondary)
            }
            
            for joint in exercise.type.secondaryJoints {
                let current = summary[joint] ?? (primary: 0, secondary: 0)
                summary[joint] = (primary: current.primary, secondary: current.secondary + exercise.repetitions)
            }
        }
        
        return summary
    }
}

// MARK: - Exercise Admin Class

class ExerciseAdministration: ObservableObject {
    @Published var sessions: [ExerciseSession] = []
    @Published var currentSession: ExerciseSession?
    @Published var currentExerciseIndex: Int = 0
    @Published var currentExercisePerformance: ExercisePerformance?
    
    // Tracking current exercise
    private var exerciseStartTime: Date?
    private var repetitionStartTime: Date?
    private var repetitionsCompleted: Int = 0
    private var maxDepthReached: Float = 0.0
    private var repTimes: [TimeInterval] = []
    private var jointData: [JointType: (range: Float, count: Int)] = [:]
    
    // MARK: - Session Management
    
    func createNewSession(name: String, exercises: [ExerciseConfiguration]) {
        let session = ExerciseSession(
            id: UUID(),
            name: name,
            dateCreated: Date(),
            exercises: exercises
        )
        
        sessions.append(session)
        saveSessionsToStorage()
    }
    
    func startSession(_ session: ExerciseSession) {
        currentSession = session
        currentExerciseIndex = 0
        
        // Begin the first exercise if there is one
        if !session.exercises.isEmpty {
            startCurrentExercise()
        }
    }
    
    func moveToNextExercise() -> Bool {
        guard let session = currentSession else { return false }
        
        // Ensure current exercise is completed and recorded
        if currentExercisePerformance != nil {
            completeCurrentExercise()
        }
        
        // Move to next exercise
        currentExerciseIndex += 1
        
        // Check if we've completed all exercises
        if currentExerciseIndex >= session.exercises.count {
            completeSession()
            return false
        } else {
            startCurrentExercise()
            return true
        }
    }
    
    private func startCurrentExercise() {
        guard let session = currentSession,
              currentExerciseIndex < session.exercises.count else { return }
        
        // Reset exercise tracking variables
        exerciseStartTime = Date()
        repetitionStartTime = Date()
        repetitionsCompleted = 0
        maxDepthReached = 0.0
        repTimes = []
        jointData = [:]
        
        // Initialize joint data for tracking
        let exerciseConfig = session.exercises[currentExerciseIndex]
        
        for joint in exerciseConfig.type.primaryJoints {
            jointData[joint] = (range: 0.0, count: 0)
        }
        
        for joint in exerciseConfig.type.secondaryJoints {
            jointData[joint] = (range: 0.0, count: 0)
        }
    }
    
    func startRepetition() {
        repetitionStartTime = Date()
    }
    
    func completeRepetition(depthReached: Float) {
        guard let startTime = repetitionStartTime else { return }
        
        // Calculate duration of this rep
        let duration = Date().timeIntervalSince(startTime)
        repTimes.append(duration)
        
        // Update tracking metrics
        repetitionsCompleted += 1
        maxDepthReached = max(maxDepthReached, depthReached)
        
        // Update joint data (simplified version - in a real implementation,
        // this would use actual range of motion calculations)
        let rangeOfMotionEstimate = 90.0 * Float(depthReached / 1.0) // Simplistic calculation
        
        for (joint, data) in jointData {
            let newCount = data.count + 1
            let newRange = max(data.range, rangeOfMotionEstimate)
            jointData[joint] = (range: newRange, count: newCount)
        }
        
        repetitionStartTime = nil
    }
    
    func completeCurrentExercise() {
        guard let session = currentSession,
              currentExerciseIndex < session.exercises.count,
              let startTime = exerciseStartTime else { return }
        
        // Calculate total duration
        let totalDuration = Date().timeIntervalSince(startTime)
        
        // Calculate average time per rep
        let avgTimePerRep = repTimes.isEmpty ? 0 : repTimes.reduce(0, +) / Double(repTimes.count)
        
        // Create joint metrics
        var jointMetrics: [JointMetric] = []
        for (joint, data) in jointData {
            let metric = JointMetric(
                joint: joint,
                rangeOfMotion: data.range,
                workload: data.count
            )
            jointMetrics.append(metric)
        }
        
        // Create performance record
        let performance = ExercisePerformance(
            exerciseType: session.exercises[currentExerciseIndex].type,
            dateCompleted: Date(),
            repetitionsCompleted: repetitionsCompleted,
            maxDepthReached: maxDepthReached,
            totalDuration: totalDuration,
            avgTimePerRep: avgTimePerRep,
            jointMetrics: jointMetrics,
            stabilityScore: nil, // Would be calculated in a more advanced implementation
            movementSmoothnessScore: nil // Would be calculated in a more advanced implementation
        )
        
        // Add to session
        currentSession?.performances.append(performance)
        
        // Reset current performance tracking
        currentExercisePerformance = nil
        exerciseStartTime = nil
        
        // Save updated session data
        saveSessionsToStorage()
    }
    
    func completeSession() {
        guard var session = currentSession else { return }
        
        session.completed = true
        session.dateCompleted = Date()
        
        // Update the session in the sessions array
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        
        currentSession = nil
        currentExerciseIndex = 0
        currentExercisePerformance = nil
        
        saveSessionsToStorage()
    }
    
    func cancelSession() {
        currentSession = nil
        currentExerciseIndex = 0
        currentExercisePerformance = nil
    }
    
    // MARK: - Storage
    
    func saveSessionsToStorage() {
        // In a real implementation, this would save to UserDefaults, CoreData, or a file
        print("Saving \(sessions.count) sessions")
    }
    
    func loadSessionsFromStorage() {
        // In a real implementation, this would load from UserDefaults, CoreData, or a file
        print("Loading sessions from storage")
    }
    
    // MARK: - Exercise Configuration Management
    
    func createDefaultBendingExercise() -> ExerciseConfiguration {
        return ExerciseConfiguration(
            type: .bending,
            repetitions: 5,
            startingHeight: 1.0,
            minimumHeight: 0.1,
            stepDistance: 0.1
        )
    }
    
    func createDefaultSession() -> ExerciseSession {
        return ExerciseSession(
            name: "Basic Mobility Session",
            dateCreated: Date(),
            exercises: [createDefaultBendingExercise()]
        )
    }
    
    // MARK: - Analytics
    
    func getProgressReport(for jointType: JointType, timeframe: TimeInterval = 60*60*24*30) -> [ExercisePerformance] {
        // Filter performances relevant to this joint within the timeframe
        let startDate = Date().addingTimeInterval(-timeframe)
        
        var relevantPerformances: [ExercisePerformance] = []
        
        for session in sessions {
            for performance in session.performances {
                // Check if this exercise works this joint
                let isRelevant = performance.exerciseType.primaryJoints.contains(jointType) ||
                                 performance.exerciseType.secondaryJoints.contains(jointType)
                
                // Check if within timeframe
                let isRecent = performance.dateCompleted > startDate
                
                if isRelevant && isRecent {
                    relevantPerformances.append(performance)
                }
            }
        }
        
        return relevantPerformances.sorted { $0.dateCompleted < $1.dateCompleted }
    }
}
