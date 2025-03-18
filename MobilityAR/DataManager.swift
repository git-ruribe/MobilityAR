//
//  DataManager.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import Combine
import CoreData

// Data structure for exercise session info
struct ExerciseSessionData: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var exerciseType: ExerciseType
    var durationInSeconds: TimeInterval
    var repetitions: Int
    var maxDepthReached: Float
    var performanceScore: Int?
    var notes: String?
    
    // Computed properties for UI
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        let minutes = Int(durationInSeconds) / 60
        let seconds = Int(durationInSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Struct for calendar day data
struct CalendarDayData: Identifiable {
    var id = UUID()
    var date: Date
    var sessions: [ExerciseSessionData]
    var isPlannedSession: Bool = false
    
    // Computed property to get exercise types for this day
    var exerciseTypes: [ExerciseType] {
        Array(Set(sessions.map { $0.exerciseType }))
    }
    
    // Total duration of all sessions
    var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.durationInSeconds }
    }
    
    // Formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    // Day of month
    var dayOfMonth: Int {
        Calendar.current.component(.day, from: date)
    }
    
    // Day of week
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

// Struct for planned session
struct PlannedExerciseSession: Identifiable, Codable {
    var id = UUID()
    var scheduledDate: Date
    var exerciseType: ExerciseType
    var targetDuration: TimeInterval
    var targetRepetitions: Int
    var notes: String?
    var reminderTime: Date?
    var isRecurring: Bool = false
    var recurrencePattern: RecurrencePattern?
    
    // Recurrence pattern options
    enum RecurrencePattern: String, Codable, CaseIterable {
        case daily = "Daily"
        case weekdays = "Weekdays"
        case weekly = "Weekly"
        case biweekly = "Bi-weekly"
        case monthly = "Monthly"
    }
}

class DataManager: ObservableObject {
    static let shared = DataManager()
    
    // Published properties
    @Published var exerciseSessions: [ExerciseSessionData] = []
    @Published var plannedSessions: [PlannedExerciseSession] = []
    @Published var selectedDate: Date = Date()
    
    // Persistence container
    private let userDefaults = UserDefaults.standard
    
    // Calendar for date calculations
    private let calendar = Calendar.current
    
    private init() {
        // Initialize with saved data
    }
    
    // MARK: - Data Saving
        
        func saveAllData() {
            saveExerciseSessionsToStorage()
            savePlannedSessionsToStorage()
        }
        
        // Public save methods that can be called from outside
        func saveExerciseSessionsToStorage() {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(exerciseSessions)
                userDefaults.set(data, forKey: "exerciseSessions")
                print("Saved \(exerciseSessions.count) exercise sessions")
            } catch {
                print("Failed to save exercise sessions: \(error)")
            }
        }
        
        func savePlannedSessionsToStorage() {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(plannedSessions)
                userDefaults.set(data, forKey: "plannedSessions")
                print("Saved \(plannedSessions.count) planned sessions")
            } catch {
                print("Failed to save planned sessions: \(error)")
            }
        }
    
    // MARK: - Data Loading
    
    func loadSavedData() {
        loadExerciseSessions()
        loadPlannedSessions()
    }
    
    private func loadExerciseSessions() {
        if let savedData = userDefaults.data(forKey: "exerciseSessions") {
            do {
                let decoder = JSONDecoder()
                exerciseSessions = try decoder.decode([ExerciseSessionData].self, from: savedData)
                print("Loaded \(exerciseSessions.count) exercise sessions")
            } catch {
                print("Failed to decode exercise sessions: \(error)")
                exerciseSessions = []
            }
        }
    }
    
    private func loadPlannedSessions() {
        if let savedData = userDefaults.data(forKey: "plannedSessions") {
            do {
                let decoder = JSONDecoder()
                plannedSessions = try decoder.decode([PlannedExerciseSession].self, from: savedData)
                print("Loaded \(plannedSessions.count) planned sessions")
            } catch {
                print("Failed to decode planned sessions: \(error)")
                plannedSessions = []
            }
        }
    }
    
    // MARK: - Data Saving
    
    private func saveExerciseSessions() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(exerciseSessions)
            userDefaults.set(data, forKey: "exerciseSessions")
            print("Saved \(exerciseSessions.count) exercise sessions")
        } catch {
            print("Failed to save exercise sessions: \(error)")
        }
    }
    
    private func savePlannedSessions() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(plannedSessions)
            userDefaults.set(data, forKey: "plannedSessions")
            print("Saved \(plannedSessions.count) planned sessions")
        } catch {
            print("Failed to save planned sessions: \(error)")
        }
    }
    
    // MARK: - Exercise Session Management
    
    // Save exercise session from ARViewModel stats
    func saveExerciseSession(from stats: ARViewModel.ExerciseStats?, exerciseType: ExerciseType) {
        guard let stats = stats, let endTime = stats.endTime else {
            print("Invalid exercise stats")
            return
        }
        
        let sessionData = ExerciseSessionData(
            date: endTime,
            exerciseType: exerciseType,
            durationInSeconds: stats.totalDuration,
            repetitions: stats.reachedLevels,
            maxDepthReached: stats.maxDepthReached,
            performanceScore: stats.performanceScore
        )
        
        saveExerciseSession(sessionData)
    }
    
    // Save exercise session data
    func saveExerciseSession(_ session: ExerciseSessionData) {
        exerciseSessions.append(session)
        exerciseSessions.sort { $0.date > $1.date } // Sort with newest first
        saveExerciseSessionsToStorage()
        
        // Post notification for UI updates
        NotificationCenter.default.post(name: .exerciseSessionAdded, object: session)
    }
    
    // Update exercise session
    func updateExerciseSession(_ session: ExerciseSessionData) {
        if let index = exerciseSessions.firstIndex(where: { $0.id == session.id }) {
            exerciseSessions[index] = session
            saveExerciseSessionsToStorage()
        }
    }
    
    // Delete exercise session
    func deleteExerciseSession(id: UUID) {
        exerciseSessions.removeAll { $0.id == id }
        saveExerciseSessionsToStorage()
    }
    
    // MARK: - Planned Session Management

    // Add planned session
        func addPlannedSession(_ session: PlannedExerciseSession) {
            plannedSessions.append(session)
            plannedSessions.sort { $0.scheduledDate < $1.scheduledDate }
            savePlannedSessionsToStorage()
            
            // Post notification for UI updates
            NotificationCenter.default.post(name: .plannedSessionAdded, object: session)
        }
        
        // Update planned session
        func updatePlannedSession(_ session: PlannedExerciseSession) {
            if let index = plannedSessions.firstIndex(where: { $0.id == session.id }) {
                plannedSessions[index] = session
                savePlannedSessionsToStorage()
            }
        }
        
        // Delete planned session
        func deletePlannedSession(id: UUID) {
            plannedSessions.removeAll { $0.id == id }
            savePlannedSessionsToStorage()
        }
    
    // MARK: - Calendar Data Management
    
    // Get calendar data for a specific month
    func getCalendarData(for month: Date) -> [CalendarDayData] {
        // Calculate first day of the month
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let firstDayOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDayOfMonth) else {
            return []
        }
        
        var calendarData: [CalendarDayData] = []
        
        // Create data for each day in the month
        for day in range.lowerBound..<range.upperBound {
            let components = DateComponents(year: components.year, month: components.month, day: day)
            guard let date = calendar.date(from: components) else { continue }
            
            // Get sessions for this day
            let daySessions = exerciseSessions.filter { 
                calendar.isDate($0.date, inSameDayAs: date)
            }
            
            // Check if there's a planned session
            let hasPlannedSession = plannedSessions.contains {
                calendar.isDate($0.scheduledDate, inSameDayAs: date)
            }
            
            let dayData = CalendarDayData(
                date: date, 
                sessions: daySessions,
                isPlannedSession: hasPlannedSession
            )
            
            calendarData.append(dayData)
        }
        
        return calendarData
    }
    
    // Get sessions for a specific date
    func getSessions(for date: Date) -> [ExerciseSessionData] {
        exerciseSessions.filter { 
            calendar.isDate($0.date, inSameDayAs: date)
        }
    }
    
    // Get planned sessions for a specific date
    func getPlannedSessions(for date: Date) -> [PlannedExerciseSession] {
        plannedSessions.filter { 
            calendar.isDate($0.scheduledDate, inSameDayAs: date)
        }
    }
    
    // MARK: - Analytics and Insights
    
    // Get exercise frequency by type for a date range
    func getExerciseFrequency(from startDate: Date, to endDate: Date) -> [ExerciseType: Int] {
        var frequency: [ExerciseType: Int] = [:]
        
        for type in ExerciseType.allCases {
            frequency[type] = 0
        }
        
        for session in exerciseSessions {
            if session.date >= startDate && session.date <= endDate {
                frequency[session.exerciseType, default: 0] += 1
            }
        }
        
        return frequency
    }
    
    // Get average performance score by exercise type
    func getAveragePerformanceScore(for exerciseType: ExerciseType, from startDate: Date, to endDate: Date) -> Double {
        let sessions = exerciseSessions.filter { 
            $0.exerciseType == exerciseType && 
            $0.date >= startDate && $0.date <= endDate &&
            $0.performanceScore != nil
        }
        
        let totalScore = sessions.reduce(0) { $0 + ($1.performanceScore ?? 0) }
        return sessions.isEmpty ? 0 : Double(totalScore) / Double(sessions.count)
    }
    
    // Get total exercise duration by week
    func getWeeklyExerciseDuration(weeks: Int) -> [(weekStart: Date, duration: TimeInterval)] {
        var result: [(weekStart: Date, duration: TimeInterval)] = []
        
        // Start from current week and go back
        var currentDate = Date()
        
        for _ in 0..<weeks {
            // Get start of the week
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: currentDate))!
            
            // Get end of the week
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            
            // Calculate total duration for the week
            let weekDuration = exerciseSessions
                .filter { $0.date >= weekStart && $0.date < weekEnd }
                .reduce(0) { $0 + $1.durationInSeconds }
            
            result.append((weekStart: weekStart, duration: weekDuration))
            
            // Move to previous week
            currentDate = calendar.date(byAdding: .day, value: -7, to: currentDate)!
        }
        
        return result.reversed()
    }
}
