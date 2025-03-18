//
//  AppDelegate.swift
//  MobilityAR
//
//  Created by Rafael Uribe on 16/03/25.
//

import UIKit
import SwiftUI

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Initialize DataManager
        let dataManager = DataManager.shared
        dataManager.loadSavedData()
        
        // Create the SwiftUI view that provides the window contents.
        let mainTabView = MainTabView()
            .environmentObject(dataManager)

        // Use a UIHostingController as window root view controller.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: mainTabView)
        self.window = window
        window.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state.
        // Save any data if needed
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
            // Save data in background
            DataManager.shared.saveExerciseSessionsToStorage()
            DataManager.shared.savePlannedSessionsToStorage()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Refresh data when returning to foreground
        DataManager.shared.loadSavedData()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Refresh UI if needed
    }
}
