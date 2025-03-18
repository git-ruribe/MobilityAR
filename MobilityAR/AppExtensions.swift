//
//  AppExtensions.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI

// Extension for notification names used throughout the app
extension Notification.Name {
    // Switching tabs
    static let switchToTrainTab = Notification.Name("switchToTrainTab")
    static let switchToCalendarTab = Notification.Name("switchToCalendarTab")
    static let switchToProgressTab = Notification.Name("switchToProgressTab")
    static let switchToProfileTab = Notification.Name("switchToProfileTab")
    
    // Data events
    static let exerciseSessionAdded = Notification.Name("exerciseSessionAdded")
    static let exerciseSessionUpdated = Notification.Name("exerciseSessionUpdated")
    static let exerciseSessionDeleted = Notification.Name("exerciseSessionDeleted")
    static let plannedSessionAdded = Notification.Name("plannedSessionAdded")
    static let plannedSessionUpdated = Notification.Name("plannedSessionUpdated")
    static let plannedSessionDeleted = Notification.Name("plannedSessionDeleted")
    static let exerciseCompleted = Notification.Name("exerciseCompleted")
    
    // AR events
    static let arSessionInterrupted = Notification.Name("arSessionInterrupted")
    static let arSessionResumed = Notification.Name("arSessionResumed")
}

// Extension for Color to easily convert between UIColor and SwiftUI Color
extension Color {
    init(uiColor: UIColor) {
        self.init(red: Double(uiColor.rgba.red),
                  green: Double(uiColor.rgba.green),
                  blue: Double(uiColor.rgba.blue),
                  opacity: Double(uiColor.rgba.alpha))
    }
    
    var uiColor: UIColor {
        let components = self.components
        return UIColor(red: components.red,
                       green: components.green,
                       blue: components.blue,
                       alpha: components.opacity)
    }
    
    private var components: (red: CGFloat, green: CGFloat, blue: CGFloat, opacity: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        
        #if os(iOS)
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &opacity)
        #endif
        
        return (red, green, blue, opacity)
    }
}

// Extension for UIColor to get RGBA components
extension UIColor {
    var rgba: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return (red, green, blue, alpha)
    }
}

// Extension to handle tab switching from anywhere in the app
extension MainTabView {
    func switchToTab(_ index: Int) {
        selectedTab = index
    }
}

// Custom modifier for consistent card styling
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// Custom modifier for consistent section header styling
struct SectionHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.bottom, 4)
    }
}

// Custom modifier for consistent button styling
struct PrimaryButtonStyle: ButtonStyle {
    var backgroundColor: Color = .blue
    var foregroundColor: Color = .white
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(backgroundColor.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(foregroundColor)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Extension to add these modifiers as easy-to-use functions
extension View {
    func cardStyle() -> some View {
        self.modifier(CardStyle())
    }
    
    func sectionHeaderStyle() -> some View {
        self.modifier(SectionHeaderStyle())
    }
}

// Helper for accessing environment objects more safely
struct EnvironmentObjectsKey: EnvironmentKey {
    static let defaultValue: [String: Any] = [:]
}

extension EnvironmentValues {
    var objects: [String: Any] {
        get { self[EnvironmentObjectsKey.self] }
        set { self[EnvironmentObjectsKey.self] = newValue }
    }
}

// Date extension for easy formatting
extension Date {
    func formatted(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    var formattedDay: String {
        formatted("d")
    }
    
    var formattedWeekday: String {
        formatted("E")
    }
    
    var formattedMonthYear: String {
        formatted("MMMM yyyy")
    }
    
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay)!
    }
    
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components)!
    }
    
    var endOfMonth: Date {
        var components = DateComponents()
        components.month = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfMonth)!
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }
}

// TimeInterval extension for formatting durations
extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
