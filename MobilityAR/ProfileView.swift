//
//  ProfileView.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showResetConfirmation = false
    @State private var userName: String = UserDefaults.standard.string(forKey: "userName") ?? ""
    @State private var userHeight: Int = UserDefaults.standard.integer(forKey: "userHeight") // in cm
    @State private var reminderEnabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
    @State private var reminderTime = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "reminderTime"))
    @State private var showHeightPicker = false
    
    // AR settings
    @State private var showDebugInfo = UserDefaults.standard.bool(forKey: "showDebugInfo")
    @State private var hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled")
    @State private var audioFeedbackEnabled = UserDefaults.standard.bool(forKey: "audioFeedbackEnabled")
    
    // Exercise settings
    @State private var selectedDifficulty = UserDefaults.standard.integer(forKey: "exerciseDifficulty")
    
    var body: some View {
        NavigationView {
            Form {
                // User profile section
                Section(header: Text("Profile")) {
                    TextField("Your Name", text: $userName)
                        .onChange(of: userName) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "userName")
                        }
                    
                    HStack {
                        Text("Height")
                        Spacer()
                        Button(userHeight > 0 ? "\(userHeight) cm" : "Set Height") {
                            showHeightPicker = true
                        }
                        .foregroundColor(.blue)
                    }
                    .sheet(isPresented: $showHeightPicker) {
                        HeightPickerView(height: $userHeight)
                    }
                }
                
                // Reminder settings
                Section(header: Text("Daily Reminder")) {
                    Toggle("Enable Daily Reminder", isOn: $reminderEnabled)
                        .onChange(of: reminderEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "reminderEnabled")
                            if newValue {
                                scheduleReminder()
                            } else {
                                cancelReminders()
                            }
                        }
                    
                    if reminderEnabled {
                        DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                            .onChange(of: reminderTime) { newValue in
                                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: "reminderTime")
                                scheduleReminder()
                            }
                    }
                }
                
                // AR settings
                Section(header: Text("AR Experience")) {
                    Toggle("Show Debug Information", isOn: $showDebugInfo)
                        .onChange(of: showDebugInfo) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "showDebugInfo")
                        }
                    
                    Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                        .onChange(of: hapticFeedbackEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "hapticFeedbackEnabled")
                        }
                    
                    Toggle("Audio Feedback", isOn: $audioFeedbackEnabled)
                        .onChange(of: audioFeedbackEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "audioFeedbackEnabled")
                        }
                }
                
                // Exercise settings
                Section(header: Text("Exercise Settings")) {
                    Picker("Difficulty", selection: $selectedDifficulty) {
                        Text("Easy").tag(0)
                        Text("Medium").tag(1)
                        Text("Hard").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedDifficulty) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "exerciseDifficulty")
                    }
                }
                
                // App info section
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    NavigationLink(destination: PrivacyPolicyView()) {
                        Text("Privacy Policy")
                    }
                    
                    NavigationLink(destination: HelpView()) {
                        Text("Help & Support")
                    }
                }
                
                // Reset section
                Section {
                    Button(action: {
                        showResetConfirmation = true
                    }) {
                        Text("Reset All Data")
                            .foregroundColor(.red)
                    }
                    .alert(isPresented: $showResetConfirmation) {
                        Alert(
                            title: Text("Reset All Data?"),
                            message: Text("This will permanently delete all your exercise sessions and settings. This action cannot be undone."),
                            primaryButton: .destructive(Text("Reset")) {
                                resetAllData()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onAppear {
            loadSavedSettings()
        }
    }
    
    // Load saved settings
    private func loadSavedSettings() {
        userName = UserDefaults.standard.string(forKey: "userName") ?? ""
        userHeight = UserDefaults.standard.integer(forKey: "userHeight")
        reminderEnabled = UserDefaults.standard.bool(forKey: "reminderEnabled")
        
        let savedTime = UserDefaults.standard.double(forKey: "reminderTime")
        if savedTime > 0 {
            reminderTime = Date(timeIntervalSince1970: savedTime)
        } else {
            // Default to 8:00 AM
            let calendar = Calendar.current
            var components = calendar.dateComponents([.hour, .minute], from: Date())
            components.hour = 8
            components.minute = 0
            reminderTime = calendar.date(from: components) ?? Date()
        }
        
        showDebugInfo = UserDefaults.standard.bool(forKey: "showDebugInfo")
        hapticFeedbackEnabled = UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled")
        audioFeedbackEnabled = UserDefaults.standard.bool(forKey: "audioFeedbackEnabled")
        
        // Load exercise difficulty or set default
        if UserDefaults.standard.object(forKey: "exerciseDifficulty") == nil {
            selectedDifficulty = 1 // Medium as default
            UserDefaults.standard.set(1, forKey: "exerciseDifficulty")
        } else {
            selectedDifficulty = UserDefaults.standard.integer(forKey: "exerciseDifficulty")
        }
    }
    
    // Schedule daily reminder
    private func scheduleReminder() {
        // Remove existing notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // Request permission if needed
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                // Create notification content
                let content = UNMutableNotificationContent()
                content.title = "Time for Mobility Exercise"
                content.body = "Keep up your routine to improve flexibility and mobility."
                content.sound = UNNotificationSound.default
                
                // Extract hour and minute from the date
                let calendar = Calendar.current
                let hour = calendar.component(.hour, from: reminderTime)
                let minute = calendar.component(.minute, from: reminderTime)
                
                // Create a daily trigger
                var dateComponents = DateComponents()
                dateComponents.hour = hour
                dateComponents.minute = minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                
                // Create request
                let request = UNNotificationRequest(identifier: "mobilityReminder", content: content, trigger: trigger)
                
                // Add to notification center
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling notification: \(error)")
                    }
                }
            }
        }
    }
    
    // Cancel all reminders
    private func cancelReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    // Reset all data
    private func resetAllData() {
        // Clear exercise sessions
        dataManager.exerciseSessions.removeAll()
        dataManager.plannedSessions.removeAll()
        
        // Save empty state
        do {
            let encoder = JSONEncoder()
            let emptySessionsData = try encoder.encode([ExerciseSessionData]())
            let emptyPlannedData = try encoder.encode([PlannedExerciseSession]())
            
            UserDefaults.standard.set(emptySessionsData, forKey: "exerciseSessions")
            UserDefaults.standard.set(emptyPlannedData, forKey: "plannedSessions")
        } catch {
            print("Error resetting data: \(error)")
        }
        
        // Reset user preferences (keep name)
        let name = userName
        
        UserDefaults.standard.set(0, forKey: "userHeight")
        UserDefaults.standard.set(false, forKey: "reminderEnabled")
        UserDefaults.standard.set(1, forKey: "exerciseDifficulty")
        
        // Cancel reminders
        cancelReminders()
        
        // Reload settings
        loadSavedSettings()
        userName = name // Keep the name
    }
}

// View for selecting user height
struct HeightPickerView: View {
    @Binding var height: Int
    @Environment(\.presentationMode) var presentationMode
    
    // For the picker
    @State private var selectedHeight: Int
    
    // Height range (100cm - 220cm)
    let heightRange = Array(100...220)
    
    init(height: Binding<Int>) {
        _height = height
        
        // Initialize with current height or default to 170cm
        let initialHeight = height.wrappedValue > 0 ? height.wrappedValue : 170
        _selectedHeight = State(initialValue: initialHeight)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Height", selection: $selectedHeight) {
                    ForEach(heightRange, id: \.self) { cm in
                        Text("\(cm) cm").tag(cm)
                    }
                }
                .pickerStyle(WheelPickerStyle())
            }
            .navigationTitle("Select Height")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    height = selectedHeight
                    UserDefaults.standard.set(selectedHeight, forKey: "userHeight")
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// Privacy policy view
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                Text("Last updated: March 17, 2025")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
                
                Group {
                    Text("Information Collection and Use")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("MobilityAR stores all your exercise data locally on your device. We do not collect, transmit, or store any of your personal information or exercise data on remote servers.")
                }
                
                Group {
                    Text("Data Storage")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("All exercise sessions, progress data, and user preferences are stored locally using iOS secure storage mechanisms. Your data remains on your device and is not shared with any third parties.")
                }
                
                Group {
                    Text("Camera Access")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("MobilityAR requires camera access to provide augmented reality features. Camera data is processed in real-time on your device and is not recorded, stored, or transmitted.")
                }
                
                Group {
                    Text("Notifications")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("If you enable exercise reminders, the app will schedule local notifications. These notifications are managed entirely by your device and are not transmitted to external services.")
                }
                
                Group {
                    Text("Changes to This Policy")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("We may update our Privacy Policy from time to time. You are advised to review this page periodically for any changes.")
                }
                
                Group {
                    Text("Contact Us")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("If you have any questions about this Privacy Policy, please contact us at support@mobilityar.com.")
                }
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
    }
}

// Help and support view
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    Text("Getting Started")
                        .font(.headline)
                    
                    Text("1. Place the AR cube in your exercise space by tapping on a flat surface.\n2. Follow the on-screen instructions to position the footprints.\n3. Tap the 'Exercise' button to begin a mobility session.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Group {
                    Text("Exercise Modes")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Forward Bend: Bend down to reach the target sphere, which will move lower with each level.\n\nSide Reach: Reach to the side to improve lateral flexibility.\n\nFront Reach: Extend your arms forward to improve shoulder mobility.\n\nSquat: Lower your body into a squat position to target your legs and hips.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Group {
                    Text("Drawing Tool")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Use the drawing tool to mark positions in 3D space. This is helpful for tracking your range of motion over time or for marking exercise positions.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Group {
                    Text("Calendar & Planning")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Use the Calendar tab to view your exercise history and plan future sessions. Completed exercises are automatically recorded with performance statistics.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Group {
                    Text("Troubleshooting")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("AR not working?")
                            .fontWeight(.medium)
                        
                        Text("• Ensure you have sufficient lighting\n• Point your camera at a flat, textured surface\n• Move your device slowly when scanning")
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Exercise not registering?")
                            .fontWeight(.medium)
                            .padding(.top, 4)
                        
                        Text("• Make sure the camera can see your movement\n• Try adjusting the height of the cube\n• Move slowly and deliberately")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Group {
                    Text("Contact Support")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("If you're experiencing issues or have questions, please contact us at support@mobilityar.com")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .navigationTitle("Help & Support")
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(DataManager.shared)
    }
}
