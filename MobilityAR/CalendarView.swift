//
//  CalendarView.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var dataManager: DataManager
    @StateObject private var viewModel = CalendarViewModel()
    @State private var showingAddSession = false
    @State private var showingSessionDetail = false
    @State private var selectedSession: ExerciseSessionData?
    @State private var showingDatePicker = false
    
    // For tabs within calendar view
    @State private var selectedCalendarTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Month navigation and selection
                HStack {
                    Button(action: {
                        viewModel.goToPreviousMonth()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .padding()
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        showingDatePicker.toggle()
                    }) {
                        Text(viewModel.currentMonthYearString)
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .sheet(isPresented: $showingDatePicker) {
                        DatePickerView(selectedDate: $viewModel.currentDate)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.goToNextMonth()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .padding()
                    }
                }
                .padding(.horizontal)
                
                // Day of week header
                HStack(spacing: 0) {
                    ForEach(viewModel.weekdaySymbols, id: \.self) { day in
                        Text(day)
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)
                
                // Calendar grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(viewModel.calendarDays) { day in
                        CalendarDayCell(day: day, isSelected: viewModel.isDateSelected(day.date))
                            .onTapGesture {
                                viewModel.selectDate(day.date)
                            }
                    }
                }
                .padding()
                
                // Tab view for selected date content
                VStack {
                    Picker("View", selection: $selectedCalendarTab) {
                        Text("Sessions").tag(0)
                        Text("Planned").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    TabView(selection: $selectedCalendarTab) {
                        // Completed Sessions
                        SessionsListView(date: viewModel.selectedDate, sessions: viewModel.sessionsForSelectedDate)
                            .tag(0)
                        
                        // Planned Sessions
                        PlannedSessionsView(date: viewModel.selectedDate, plannedSessions: viewModel.plannedSessionsForSelectedDate)
                            .tag(1)
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                }
                .background(Color(.systemBackground))
                .cornerRadius(15, corners: [.topLeft, .topRight])
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: -2)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddSession = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        viewModel.goToToday()
                    }) {
                        Text("Today")
                    }
                }
            }
            .sheet(isPresented: $showingAddSession) {
                AddSessionView(date: viewModel.selectedDate)
            }
            .sheet(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .onReceive(NotificationCenter.default.publisher(for: .switchToCalendarTab)) { _ in
                // Auto-select today when coming from exercise completion
                viewModel.goToToday()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exerciseSessionAdded)) { _ in
                // Refresh calendar data when a new session is added
                viewModel.refreshData()
            }
            .onReceive(NotificationCenter.default.publisher(for: .plannedSessionAdded)) { _ in
                // Refresh calendar data when a planned session is added
                viewModel.refreshData()
            }
        }
    }
}

// Calendar day cell
struct CalendarDayCell: View {
    let day: CalendarDayData
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.purple.opacity(0.2) : Color.clear)
                .frame(height: 60)
            
            VStack(spacing: 4) {
                // Day number
                Text("\(day.dayOfMonth)")
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                
                // Exercise indicators
                if !day.sessions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(day.exerciseTypes.prefix(3)), id: \.self) { type in
                            Circle()
                                .fill(exerciseTypeColor(type))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
                
                // Planned session indicator
                if day.isPlannedSession {
                    Rectangle()
                        .fill(Color.blue.opacity(0.7))
                        .frame(width: 20, height: 2)
                }
            }
        }
        .foregroundColor(isToday(day.date) ? .purple : .primary)
        .opacity(isInCurrentMonth(day.date) ? 1.0 : 0.3)
    }
    
    // Helper to check if date is today
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    // Helper to check if date is in the current month
    private func isInCurrentMonth(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let dateMonth = calendar.component(.month, from: date)
        return currentMonth == dateMonth
    }
    
    // Color for exercise type
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

// View for completed sessions list
struct SessionsListView: View {
    let date: Date
    let sessions: [ExerciseSessionData]
    
    var body: some View {
        ScrollView {
            if sessions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No sessions on this day")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Text("Complete an exercise or add a session manually")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 60)
            } else {
                VStack(spacing: 16) {
                    ForEach(sessions) { session in
                        SessionCell(session: session)
                    }
                }
                .padding()
            }
        }
    }
}

// View for planned sessions
struct PlannedSessionsView: View {
    @EnvironmentObject var dataManager: DataManager
    let date: Date
    let plannedSessions: [PlannedExerciseSession]
    @State private var showingAddPlanned = false
    
    var body: some View {
        ScrollView {
            if plannedSessions.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No planned sessions")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        showingAddPlanned = true
                    }) {
                        Text("Add Planned Session")
                            .font(.headline)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.top, 60)
            } else {
                VStack(spacing: 16) {
                    ForEach(plannedSessions) { session in
                        PlannedSessionCell(session: session)
                    }
                    
                    Button(action: {
                        showingAddPlanned = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Another")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingAddPlanned) {
            AddPlannedSessionView(date: date)
        }
    }
}

// Cell for displaying session info
struct SessionCell: View {
    let session: ExerciseSessionData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ExerciseTypeIcon(type: session.exerciseType)
                
                Text(session.exerciseType.displayName)
                    .font(.headline)
                
                Spacer()
                
                Text(timeString(from: session.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Label("\(session.repetitions) reps", systemImage: "repeat")
                    .font(.subheadline)
                
                Spacer()
                
                Label(session.formattedDuration, systemImage: "clock")
                    .font(.subheadline)
            }
            
            if let score = session.performanceScore {
                HStack {
                    Label("Score: \(score)", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(scoreColor(score))
                    
                    Spacer()
                    
                    Text("\(Int(session.maxDepthReached * 100))cm depth")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // Helper to format time
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Helper for score color
    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 {
            return .green
        } else if score >= 60 {
            return .yellow
        } else {
            return .orange
        }
    }
}

// Cell for displaying planned session
struct PlannedSessionCell: View {
    let session: PlannedExerciseSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ExerciseTypeIcon(type: session.exerciseType)
                
                Text(session.exerciseType.displayName)
                    .font(.headline)
                
                Spacer()
                
                if session.isRecurring {
                    Image(systemName: "repeat")
                        .foregroundColor(.blue)
                }
            }
            
            HStack {
                Label("\(session.targetRepetitions) reps", systemImage: "repeat")
                    .font(.subheadline)
                
                Spacer()
                
                // Format planned duration
                Label(formatDuration(session.targetDuration), systemImage: "clock")
                    .font(.subheadline)
            }
            
            if let reminderTime = session.reminderTime {
                Label(timeString(from: reminderTime), systemImage: "bell.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    // Helper to format time
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "Reminder: " + formatter.string(from: date)
    }
    
    // Helper to format duration
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Exercise type icon
struct ExerciseTypeIcon: View {
    let type: ExerciseType
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 36, height: 36)
            
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(.white)
        }
    }
    
    private var backgroundColor: Color {
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
    
    private var iconName: String {
        switch type {
        case .bending:
            return "figure.bend.down"
        case .sideReach:
            return "figure.arms.open"
        case .frontReach:
            return "hand.raised"
        case .squat:
            return "figure.stand"
        }
    }
}

// View for month/year picker
struct DatePickerView: View {
    @Binding var selectedDate: Date
    @Environment(\.presentationMode) var presentationMode
    
    @State private var year: Int
    @State private var month: Int
    
    let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    
    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        
        let calendar = Calendar.current
        _year = State(initialValue: calendar.component(.year, from: selectedDate.wrappedValue))
        _month = State(initialValue: calendar.component(.month, from: selectedDate.wrappedValue) - 1) // 0-indexed
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Month")) {
                    Picker("Month", selection: $month) {
                        ForEach(0..<months.count, id: \.self) { index in
                            Text(months[index]).tag(index)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                }
                
                Section(header: Text("Year")) {
                    Picker("Year", selection: $year) {
                        ForEach((year-5)...(year+5), id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                }
            }
            .navigationTitle("Select Date")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Done") {
                    updateDate()
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    func updateDate() {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year
        components.month = month + 1 // Convert to 1-indexed
        components.day = 1
        
        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
        }
    }
}

// View for adding a planned session
struct AddPlannedSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dataManager: DataManager
    let date: Date
    
    @State private var exerciseType: ExerciseType = .bending
    @State private var targetDuration: TimeInterval = 300 // 5 minutes
    @State private var targetRepetitions: Int = 10
    @State private var notes: String = ""
    @State private var showReminder: Bool = false
    @State private var reminderTime: Date = Date()
    @State private var isRecurring: Bool = false
    @State private var recurrencePattern: PlannedExerciseSession.RecurrencePattern = .weekly
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    Picker("Exercise Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    Stepper("Target Repetitions: \(targetRepetitions)", value: $targetRepetitions, in: 1...50)
                    
                    HStack {
                        Text("Target Duration")
                        Spacer()
                        Text(formatDuration(targetDuration))
                    }
                    
                    Slider(value: $targetDuration, in: 60...1800, step: 30)
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section(header: Text("Reminder")) {
                    Toggle("Set Reminder", isOn: $showReminder)
                    
                    if showReminder {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                
                Section(header: Text("Recurrence")) {
                    Toggle("Recurring Session", isOn: $isRecurring)
                    
                    if isRecurring {
                        Picker("Repeat", selection: $recurrencePattern) {
                            ForEach(PlannedExerciseSession.RecurrencePattern.allCases, id: \.self) { pattern in
                                Text(pattern.rawValue).tag(pattern)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan Session")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    savePlannedSession()
                }
            )
        }
    }
    
    private func savePlannedSession() {
        let session = PlannedExerciseSession(
            scheduledDate: date,
            exerciseType: exerciseType,
            targetDuration: targetDuration,
            targetRepetitions: targetRepetitions,
            notes: notes.isEmpty ? nil : notes,
            reminderTime: showReminder ? reminderTime : nil,
            isRecurring: isRecurring,
            recurrencePattern: isRecurring ? recurrencePattern : nil
        )
        
        dataManager.addPlannedSession(session)
        presentationMode.wrappedValue.dismiss()
    }
    
    // Helper to format duration
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// View for adding a completed session
struct AddSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dataManager: DataManager
    let date: Date
    
    @State private var exerciseType: ExerciseType = .bending
    @State private var durationMinutes: Double = 5
    @State private var repetitions: Int = 10
    @State private var maxDepthReached: Double = 30 // cm
    @State private var performanceScore: Int = 75
    @State private var notes: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    Picker("Exercise Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(Int(durationMinutes)) min")
                    }
                    Slider(value: $durationMinutes, in: 1...60, step: 1)
                    
                    Stepper("Repetitions: \(repetitions)", value: $repetitions, in: 1...50)
                    
                    HStack {
                        Text("Max Depth")
                        Spacer()
                        Text("\(Int(maxDepthReached)) cm")
                    }
                    Slider(value: $maxDepthReached, in: 10...100, step: 1)
                    
                    HStack {
                        Text("Performance Score")
                        Spacer()
                        Text("\(performanceScore)")
                    }
                    Slider(value: $performanceScore.doubleValue, in: 0...100, step: 1)
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Add Session")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    saveSession()
                }
            )
        }
    }
    
    private func saveSession() {
        let session = ExerciseSessionData(
            date: date,
            exerciseType: exerciseType,
            durationInSeconds: durationMinutes * 60,
            repetitions: repetitions,
            maxDepthReached: Float(maxDepthReached / 100), // Convert cm to meters
            performanceScore: performanceScore,
            notes: notes.isEmpty ? nil : notes
        )
        
        dataManager.saveExerciseSession(session)
        presentationMode.wrappedValue.dismiss()
    }
}

// View for session details
struct SessionDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    let session: ExerciseSessionData
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header with exercise type and date
                    HStack {
                        ExerciseTypeIcon(type: session.exerciseType)
                            .frame(width: 60, height: 60)
                        
                        VStack(alignment: .leading) {
                            Text(session.exerciseType.displayName)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text(session.formattedDate)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Performance metrics
                    VStack(spacing: 20) {
                        // Duration and repetitions
                        HStack {
                            MetricCard(
                                title: "Duration",
                                value: session.formattedDuration,
                                icon: "clock.fill"
                            )
                            
                            MetricCard(
                                title: "Repetitions",
                                value: "\(session.repetitions)",
                                icon: "repeat"
                            )
                        }
                        
                        // Depth and score
                        HStack {
                            MetricCard(
                                title: "Max Depth",
                                value: "\(Int(session.maxDepthReached * 100)) cm",
                                icon: "arrow.down"
                            )
                            
                            if let score = session.performanceScore {
                                MetricCard(
                                    title: "Score",
                                    value: "\(score)",
                                    icon: "star.fill"
                                )
                            } else {
                                MetricCard(
                                    title: "Score",
                                    value: "N/A",
                                    icon: "star"
                                )
                            }
                        }
                    }
                    .padding()
                    
                    // Notes if available
                    if let notes = session.notes, !notes.isEmpty {
                        VStack(alignment: .leading) {
                            Text("Notes")
                                .font(.headline)
                                .padding(.bottom, 4)
                            
                            Text(notes)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                        .padding()
                    }
                    
                    Spacer()
                }
            }
            .navigationBarTitle("Session Details", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

// Metric card for session detail view
struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.purple)
                .padding(.bottom, 8)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// Extension to create rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// Extension to allow binding Int to Double for Slider
extension Int {
    var doubleValue: Double {
        get { Double(self) }
        set { self = Int(newValue) }
    }
}

struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CalendarView()
            .environmentObject(DataManager.shared)
    }
}
