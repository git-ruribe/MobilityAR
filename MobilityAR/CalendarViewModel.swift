//
//  CalendarViewModel.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import Combine

class CalendarViewModel: ObservableObject {
    // Published properties for UI updates
    @Published var currentDate: Date = Date()
    @Published var selectedDate: Date = Date()
    @Published var calendarDays: [CalendarDayData] = []
    @Published var sessionsForSelectedDate: [ExerciseSessionData] = []
    @Published var plannedSessionsForSelectedDate: [PlannedExerciseSession] = []
    
    // Date formatters and calendar
    private let calendar = Calendar.current
    private let monthYearFormatter: DateFormatter
    private var cancellables = Set<AnyCancellable>()
    
    // Weekday symbols
    let weekdaySymbols: [String]
    
    // Computed property for current month/year string
    var currentMonthYearString: String {
        monthYearFormatter.string(from: currentDate)
    }
    
    init() {
        // Setup formatters
        monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM yyyy"
        
        // Get weekday symbols
        let formatter = DateFormatter()
        weekdaySymbols = formatter.shortWeekdaySymbols
        
        // Load data for current month
        refreshCalendarData()
        
        // Setup observers
        DataManager.shared.$exerciseSessions
            .sink { [weak self] _ in
                self?.refreshCalendarData()
                self?.updateSelectedDateData()
            }
            .store(in: &cancellables)
        
        DataManager.shared.$plannedSessions
            .sink { [weak self] _ in
                self?.refreshCalendarData()
                self?.updateSelectedDateData()
            }
            .store(in: &cancellables)
            
        $currentDate
            .sink { [weak self] _ in
                self?.refreshCalendarData()
            }
            .store(in: &cancellables)
            
        $selectedDate
            .sink { [weak self] _ in
                self?.updateSelectedDateData()
            }
            .store(in: &cancellables)
    }
    
    // Refresh all calendar data
    func refreshData() {
        refreshCalendarData()
        updateSelectedDateData()
    }
    
    // Refresh calendar data for current month
    private func refreshCalendarData() {
        let dataManager = DataManager.shared
        
        // Calculate days for the month grid
        var days: [CalendarDayData] = []
        
        // Get first day of the month
        let components = calendar.dateComponents([.year, .month], from: currentDate)
        guard let firstDayOfMonth = calendar.date(from: components) else { return }
        
        // Get the weekday of the first day (0 = Sunday, 1 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        // Calculate offset to show days from previous month
        let offsetDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        // Get start date for our grid (may be in previous month)
        guard let startDate = calendar.date(byAdding: .day, value: -offsetDays, to: firstDayOfMonth) else { return }
        
        // Get number of days in month
        let range = calendar.range(of: .day, in: .month, for: currentDate)
        let numberOfDays = range?.count ?? 30
        
        // Calculate total days to show (including days from previous/next month)
        let totalDays = numberOfDays + offsetDays
        let rowsNeeded = Int(ceil(Double(totalDays) / 7.0))
        let totalCells = rowsNeeded * 7
        
        // Generate calendar days
        var date = startDate
        for _ in 0..<totalCells {
            // Get sessions for this day
            let daySessions = dataManager.exerciseSessions.filter {
                calendar.isDate($0.date, inSameDayAs: date)
            }
            
            // Check if there's a planned session for this day
            let hasPlannedSession = dataManager.plannedSessions.contains {
                calendar.isDate($0.scheduledDate, inSameDayAs: date)
            }
            
            // Create day data
            let dayData = CalendarDayData(
                date: date,
                sessions: daySessions,
                isPlannedSession: hasPlannedSession
            )
            
            days.append(dayData)
            
            // Move to next day
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }
        
        // Update published property
        calendarDays = days
    }
    
    // Update data for selected date
    private func updateSelectedDateData() {
        let dataManager = DataManager.shared
        
        // Get sessions for selected date
        sessionsForSelectedDate = dataManager.getSessions(for: selectedDate)
        
        // Get planned sessions for selected date
        plannedSessionsForSelectedDate = dataManager.getPlannedSessions(for: selectedDate)
    }
    
    // Go to previous month
    func goToPreviousMonth() {
        if let newDate = calendar.date(byAdding: .month, value: -1, to: currentDate) {
            currentDate = newDate
        }
    }
    
    // Go to next month
    func goToNextMonth() {
        if let newDate = calendar.date(byAdding: .month, value: 1, to: currentDate) {
            currentDate = newDate
        }
    }
    
    // Go to today
    func goToToday() {
        currentDate = Date()
        selectedDate = Date()
    }
    
    // Select a date
    func selectDate(_ date: Date) {
        selectedDate = date
        
        // If selected date is not in current month, update current month
        let selectedMonth = calendar.component(.month, from: date)
        let currentMonth = calendar.component(.month, from: currentDate)
        
        if selectedMonth != currentMonth {
            currentDate = date
        }
    }
    
    // Check if a date is selected
    func isDateSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }
}
