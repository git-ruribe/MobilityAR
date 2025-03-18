//
//  ProgressViewModel.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import Combine

class ProgressViewModel: ObservableObject {
    // Data structures for UI
    struct SummaryMetrics {
        var totalSessions: Int = 0
        var totalTime: TimeInterval = 0
        var averageScore: Double = 0
        var maxDepthReached: Float = 0
        
        var formattedTotalTime: String {
            let hours = Int(totalTime) / 3600
            let minutes = (Int(totalTime) % 3600) / 60
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }
    
    struct ExerciseFrequencyData: Identifiable {
        let id = UUID()
        let type: ExerciseType
        let count: Int
    }
    
    struct WeeklyActivityData: Identifiable {
        let id = UUID()
        let weekStart: Date
        let minutes: Double
        let weekLabel: String
    }
    
    struct PerformanceTrendData: Identifiable {
        let id = UUID()
        let type: ExerciseType
        let score: Double
    }
    
    struct JointMobilityData: Identifiable {
        let id = UUID()
        let jointType: JointType
        let mobilityPercentage: Double
        let sessionsLastWeek: Int
    }
    
    // Published properties for UI
    @Published var summaryMetrics = SummaryMetrics()
    @Published var exerciseFrequency: [ExerciseFrequencyData] = []
    @Published var weeklyActivity: [WeeklyActivityData] = []
    @Published var performanceTrends: [PerformanceTrendData] = []
    @Published var jointMobilityData: [JointMobilityData] = []
    
    private var cancellables = Set<AnyCancellable>()
    private let calendar = Calendar.current
    
    // Current date range for data
    private var startDate: Date = Date()
    private var endDate: Date = Date()
    
    init() {
        // Subscribe to data changes
        DataManager.shared.$exerciseSessions
            .sink { [weak self] _ in
                self?.updateAllData()
            }
            .store(in: &cancellables)
        
        // Initial data load
        setDateRangeForTimeRange(.month)
        updateAllData()
    }
    
    // Update data for a different time range
    func updateTimeRange(_ range: ProgressView.TimeRange) {
        setDateRangeForTimeRange(range)
        updateAllData()
    }
    
    // Set date range based on selected time range
    private func setDateRangeForTimeRange(_ range: ProgressView.TimeRange) {
        let now = Date()
        
        switch range {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now) ?? now
        case .year:
            startDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        }
        
        endDate = now
    }
    
    // Update all data sets
    private func updateAllData() {
        updateSummaryMetrics()
        updateExerciseFrequency()
        updateWeeklyActivity()
        updatePerformanceTrends()
        updateJointMobilityData()
    }
    
    // MARK: - Data Update Methods
    
    private func updateSummaryMetrics() {
        let sessions = filteredSessions()
        
        // Calculate total sessions
        let totalSessions = sessions.count
        
        // Calculate total time
        let totalTime = sessions.reduce(0) { $0 + $1.durationInSeconds }
        
        // Calculate average score
        let scores = sessions.compactMap { $0.performanceScore }
        let averageScore = scores.isEmpty ? 0 : Double(scores.reduce(0, +)) / Double(scores.count)
        
        // Find max depth reached
        let maxDepth = sessions.map { $0.maxDepthReached }.max() ?? 0
        
        // Update published property
        summaryMetrics = SummaryMetrics(
            totalSessions: totalSessions,
            totalTime: totalTime,
            averageScore: averageScore,
            maxDepthReached: maxDepth
        )
    }
    
    private func updateExerciseFrequency() {
        var frequency: [ExerciseType: Int] = [:]
        
        // Initialize all exercise types with zero count
        for type in ExerciseType.allCases {
            frequency[type] = 0
        }
        
        // Count occurrences of each exercise type
        for session in filteredSessions() {
            frequency[session.exerciseType, default: 0] += 1
        }
        
        // Convert to array format for chart
        exerciseFrequency = frequency.map { type, count in
            ExerciseFrequencyData(type: type, count: count)
        }.sorted { $0.count > $1.count }
    }
    
    private func updateWeeklyActivity() {
        // Determine number of weeks to show based on time range
        let numberOfWeeks: Int
        
        switch startDate.distance(to: endDate) {
        case 0...7*24*60*60: // 1 week
            numberOfWeeks = 4
        case 7*24*60*60...30*24*60*60: // 1 month
            numberOfWeeks = 4
        case 30*24*60*60...90*24*60*60: // 3 months
            numberOfWeeks = 12
        default: // 1 year
            numberOfWeeks = 26 // Every other week for readability
        }
        
        // Get weekly data from data manager
        let weeklyData = DataManager.shared.getWeeklyExerciseDuration(weeks: numberOfWeeks)
        
        // Format for chart
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        
        weeklyActivity = weeklyData.map { weekStart, duration in
            WeeklyActivityData(
                weekStart: weekStart,
                minutes: duration / 60, // Convert seconds to minutes
                weekLabel: dateFormatter.string(from: weekStart)
            )
        }
    }
    
    private func updatePerformanceTrends() {
        var trends: [ExerciseType: [Int]] = [:]
        
        // Initialize all exercise types
        for type in ExerciseType.allCases {
            trends[type] = []
        }
        
        // Group scores by exercise type
        for session in filteredSessions() {
            if let score = session.performanceScore {
                trends[session.exerciseType, default: []].append(score)
            }
        }
        
        // Calculate average score for each type
        performanceTrends = trends.compactMap { type, scores in
            if scores.isEmpty {
                return nil
            }
            
            let averageScore = Double(scores.reduce(0, +)) / Double(scores.count)
            return PerformanceTrendData(type: type, score: averageScore)
        }.sorted { $0.score > $1.score }
    }
    
    private func updateJointMobilityData() {
        // Create synthetic joint mobility data based on exercise frequencies
        var jointData: [JointType: (sessions: Int, primary: Int, secondary: Int)] = [:]
        
        // Initialize all joint types
        for joint in JointType.allCases {
            jointData[joint] = (sessions: 0, primary: 0, secondary: 0)
        }
        
        // Process sessions from last 30 days for joint data
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentSessions = DataManager.shared.exerciseSessions.filter { $0.date >= thirtyDaysAgo }
        
        // Count sessions for each joint
        for session in recentSessions {
            // Primary joints for this exercise type
            for joint in session.exerciseType.primaryJoints {
                var data = jointData[joint] ?? (sessions: 0, primary: 0, secondary: 0)
                data.sessions += 1
                data.primary += 1
                jointData[joint] = data
            }
            
            // Secondary joints for this exercise type
            for joint in session.exerciseType.secondaryJoints {
                var data = jointData[joint] ?? (sessions: 0, primary: 0, secondary: 0)
                data.sessions += 1
                data.secondary += 1
                jointData[joint] = data
            }
        }
        
        // Process sessions from last 7 days for recent activity
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let lastWeekSessions = DataManager.shared.exerciseSessions.filter { $0.date >= sevenDaysAgo }
        
        // Count recent sessions for each joint
        var recentJointSessions: [JointType: Int] = [:]
        for joint in JointType.allCases {
            recentJointSessions[joint] = 0
        }
        
        for session in lastWeekSessions {
            for joint in session.exerciseType.primaryJoints + session.exerciseType.secondaryJoints {
                recentJointSessions[joint, default: 0] += 1
            }
        }
        
        // Calculate mobility percentage based on primary and secondary usage
        jointMobilityData = jointData.map { joint, data in
            // Calculate percentage - primary counts more than secondary
            let totalPossible = 50 // Arbitrary maximum value
            let weightedValue = min(data.primary * 2 + data.secondary, totalPossible)
            let percentage = Double(weightedValue) / Double(totalPossible) * 100
            
            return JointMobilityData(
                jointType: joint,
                mobilityPercentage: percentage,
                sessionsLastWeek: recentJointSessions[joint] ?? 0
            )
        }.sorted { $0.mobilityPercentage > $1.mobilityPercentage }
    }
    
    // Helper to get sessions within the selected date range
    private func filteredSessions() -> [ExerciseSessionData] {
        DataManager.shared.exerciseSessions.filter { session in
            session.date >= startDate && session.date <= endDate
        }
    }
}
