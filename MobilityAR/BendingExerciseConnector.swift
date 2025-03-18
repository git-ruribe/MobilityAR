//
//  BendingExerciseConnector.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import Combine

/*
 This file provides the connections between the original BendingExerciseMode
 functionality and the new app architecture. It ensures that when exercises
 are completed, the data is properly stored in our DataManager.
*/

// Extension to ARViewModel to override the completeExercise function
extension ARViewModel {
    // Override the completeExercise function to add data management
    func completeExerciseWithDataManagement() {
        // First, call the original completeExercise method
        completeExercise()
        
        // Then handle data management
        saveExerciseDataToDataManager()
    }
    
    // Save exercise data to DataManager
    private func saveExerciseDataToDataManager() {
        guard let stats = exerciseStats, let endTime = stats.endTime else {
            print("ERROR: No valid exercise stats available")
            return
        }
        
        // Create session data
        let sessionData = ExerciseSessionData(
            date: endTime,
            exerciseType: .bending, // Currently only supporting bending
            durationInSeconds: stats.totalDuration,
            repetitions: stats.reachedLevels,
            maxDepthReached: stats.maxDepthReached,
            performanceScore: stats.performanceScore
        )
        
        // Save to DataManager
        DataManager.shared.saveExerciseSession(sessionData)
        
        print("Exercise data saved to DataManager: \(stats.totalDuration)s, \(stats.reachedLevels) levels")
    }
    
    // Override the existing exitBendingMode to ensure data is saved
    func exitBendingModeWithDataManagement(completed: Bool = false) {
        // If exercise was completed, save data
        if completed && exerciseStarted && !exerciseComplete {
            saveExerciseDataToDataManager()
        }
        
        // Call original implementation
        exitBendingMode(completed: completed)
    }
    
    // This override ensures we save data when the user presses "Continue" in results popup
    // Update the Continue button in TrainView to call this instead
    func completeAndSaveExercise() {
        saveExerciseDataToDataManager()
        exitBendingMode(completed: true)
        
        // Notify to show calendar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(name: .switchToCalendarTab, object: nil)
        }
    }
    func completeAndSaveExerciseContinue() {
        saveExerciseDataToDataManager()
        exitBendingMode(completed: true)
        
    }
}

// MARK: - Instructions for Integration

/*
 To fully integrate the bending exercise with the new data management:
 
 1. In BendingExerciseMode.swift:
    - The completeExercise() function should be modified to call completeExerciseWithDataManagement()
      instead of the direct implementation
 
 2. In TrainView.swift:
    - The "Continue" button in the exercise completion popup should call
      arViewModel.completeAndSaveExercise() instead of arViewModel.exitBendingMode(completed: true)
    
    - The "View in Calendar" button should call:
      ```
      arViewModel.completeAndSaveExercise()
      // This also handles switching to calendar tab
      ```
 
 3. Make sure ARViewModel.enterBendingModeWithUserSettings() is called instead of
    enterBendingMode() throughout the app
 
 These connections ensure that exercise data flows properly from the AR experience
 to the data management system and UI.
*/
