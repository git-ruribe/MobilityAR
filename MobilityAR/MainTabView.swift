//
//  MainTabView.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var dataManager: DataManager
    @State var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Train tab - AR Experience (existing functionality)
            TrainView()
                .tabItem {
                    Label("Train", systemImage: "figure.walk")
                }
                .tag(0)
            
            // Calendar tab - Exercise history and planning
            CalendarView()
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(1)
            
            // Progress tab - Analytics and visualizations
            ProgressView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar.fill")
                }
                .tag(2)
            
            // Profile tab - User settings and preferences
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(.purple) // Match current app color scheme
        
        // Listen for tab switching notifications
                .onReceive(NotificationCenter.default.publisher(for: .switchToTrainTab)) { _ in
                    selectedTab = 0
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchToCalendarTab)) { _ in
                    selectedTab = 1
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchToProgressTab)) { _ in
                    selectedTab = 2
                }
                .onReceive(NotificationCenter.default.publisher(for: .switchToProfileTab)) { _ in
                    selectedTab = 3
                }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(DataManager.shared)
    }
}
