//
//  ProgressView.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import Charts

struct ProgressView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var viewModel = ProgressViewModel()
    @State private var selectedTimeRange: TimeRange = .month
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        case threeMonths = "3 Months"
        case year = "Year"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Time range selector
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedTimeRange) { newValue in
                        viewModel.updateTimeRange(newValue)
                    }
                    .padding(.horizontal)
                    
                    // Summary metrics
                    SummaryMetricsView(metrics: viewModel.summaryMetrics)
                    
                    // Exercise frequency chart
                    ChartSection(
                        title: "Exercise Frequency",
                        subtitle: "Number of exercises by type"
                    ) {
                        ExerciseFrequencyChart(data: viewModel.exerciseFrequency)
                    }
                    
                    // Weekly activity chart
                    ChartSection(
                        title: "Weekly Activity",
                        subtitle: "Total exercise minutes per week"
                    ) {
                        WeeklyActivityChart(data: viewModel.weeklyActivity)
                    }
                    
                    // Joint mobility summary
                    JointMobilitySummaryView(data: viewModel.jointMobilityData)
                    
                    // Performance trends
                    ChartSection(
                        title: "Performance Trends",
                        subtitle: "Average score by exercise type"
                    ) {
                        PerformanceTrendsChart(data: viewModel.performanceTrends)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Progress")
            .onAppear {
                viewModel.updateTimeRange(selectedTimeRange)
            }
        }
    }
}

// Section container for charts
struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            content
                .frame(height: 220)
                .padding(.vertical, 8)
        }
        .padding(.horizontal)
    }
}

// Summary metrics grid
struct SummaryMetricsView: View {
    let metrics: ProgressViewModel.SummaryMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SummaryMetricCard(
                    title: "Total Sessions",
                    value: "\(metrics.totalSessions)",
                    icon: "figure.walk",
                    color: .purple
                )
                
                SummaryMetricCard(
                    title: "Total Time",
                    value: metrics.formattedTotalTime,
                    icon: "clock",
                    color: .green
                )
                
                SummaryMetricCard(
                    title: "Avg Score",
                    value: "\(Int(metrics.averageScore))",
                    icon: "star.fill",
                    color: .orange
                )
                
                SummaryMetricCard(
                    title: "Max Depth",
                    value: "\(Int(metrics.maxDepthReached * 100)) cm",
                    icon: "arrow.down",
                    color: .blue
                )
            }
        }
        .padding(.horizontal)
    }
}

// Individual summary metric card
struct SummaryMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Exercise frequency chart
struct ExerciseFrequencyChart: View {
    let data: [ProgressViewModel.ExerciseFrequencyData]
    
    var body: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Exercise", item.type.displayName),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(exerciseTypeColor(item.type))
                    .cornerRadius(6)
                }
            }
        } else {
            // Fallback for iOS 15
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(data) { item in
                    VStack {
                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: 40, height: 150)
                            
                            Rectangle()
                                .fill(exerciseTypeColor(item.type))
                                .frame(width: 40, height: CGFloat(item.count) * 10)
                                .cornerRadius(6, corners: [.topLeft, .topRight])
                        }
                        
                        Text(item.type.displayName)
                            .font(.caption)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // Helper to get color for exercise type
    private func exerciseTypeColor(_ type: ExerciseType) -> Color {
        switch type {
        case .bending:
            return .blue
        case .sideReach:
            return .green
        case .frontReach:
            return .orange
        case .squat:
            return .purple
        }
    }
}

// Weekly activity chart
struct WeeklyActivityChart: View {
    let data: [ProgressViewModel.WeeklyActivityData]
    
    var body: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(data) { item in
                    LineMark(
                        x: .value("Week", item.weekLabel),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(.purple)
                    
                    PointMark(
                        x: .value("Week", item.weekLabel),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(.purple)
                }
            }
        } else {
            // Fallback for iOS 15
            VStack {
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: 0) {
                        // Find max value for scaling
                        let maxValue = data.map { $0.minutes }.max() ?? 1
                        let availableHeight = geometry.size.height - 40 // Leave space for labels
                        
                        ForEach(0..<data.count, id: \.self) { index in
                            let item = data[index]
                            let barHeight = (CGFloat(item.minutes) / CGFloat(maxValue)) * availableHeight
                            
                            VStack {
                                Spacer()
                                
                                // Bar
                                Rectangle()
                                    .fill(Color.purple)
                                    .frame(height: max(barHeight, 1))
                                
                                // Label
                                Text(item.weekLabel)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(height: 40)
                            }
                            .frame(width: geometry.size.width / CGFloat(data.count))
                        }
                    }
                }
            }
        }
    }
}

// Performance trends chart
struct PerformanceTrendsChart: View {
    let data: [ProgressViewModel.PerformanceTrendData]
    
    var body: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(data) { item in
                    BarMark(
                        x: .value("Exercise", item.type.displayName),
                        y: .value("Score", item.score)
                    )
                    .foregroundStyle(exerciseTypeColor(item.type))
                    .cornerRadius(6)
                }
            }
        } else {
            // Fallback for iOS 15
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(data) { item in
                    VStack {
                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(width: 40, height: 150)
                            
                            Rectangle()
                                .fill(exerciseTypeColor(item.type))
                                .frame(width: 40, height: CGFloat(item.score) * 1.5)
                                .cornerRadius(6, corners: [.topLeft, .topRight])
                        }
                        
                        Text(item.type.displayName)
                            .font(.caption)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
    
    // Helper to get color for exercise type
    private func exerciseTypeColor(_ type: ExerciseType) -> Color {
        switch type {
        case .bending:
            return .blue
        case .sideReach:
            return .green
        case .frontReach:
            return .orange
        case .squat:
            return .purple
        }
    }
}

// Joint mobility summary view
struct JointMobilitySummaryView: View {
    let data: [ProgressViewModel.JointMobilityData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Joint Mobility")
                .font(.headline)
            
            Text("Progress by joint focus area")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(data) { item in
                        JointMobilityCard(joint: item)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
    }
}

// Individual joint mobility card
struct JointMobilityCard: View {
    let joint: ProgressViewModel.JointMobilityData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(joint.jointType.displayName)
                .font(.headline)
            
            HStack(alignment: .center) {
                CircularProgressView(progress: joint.mobilityPercentage / 100)
                    .frame(width: 60, height: 60)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mobility")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(joint.mobilityPercentage))%")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                .padding(.leading, 8)
            }
            
            Text("Last 7 days:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(joint.sessionsLastWeek) sessions")
                .font(.subheadline)
        }
        .padding()
        .frame(width: 160, height: 170)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Circular progress view
struct CircularProgressView: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color(.systemGray4),
                    lineWidth: 8
                )
            
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(
                    progress > 0.7 ? Color.green : (progress > 0.4 ? Color.orange : Color.red),
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: progress)
            
            Text("\(Int(progress * 100))")
                .font(.caption)
                .fontWeight(.bold)
        }
    }
}

struct ProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ProgressView()
            .environmentObject(DataManager.shared)
    }
}
