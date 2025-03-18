//
//  TrainView.swift
//  MobilityAR
//
//  Created on 17/03/25.
//

import SwiftUI
import RealityKit

struct TrainView: View {
    @StateObject private var arViewModel = ARViewModel()
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        // This is basically the original ContentView, just renamed
        ZStack {
            ARViewContainer(viewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    arViewModel.prepareHaptics()
                    arViewModel.setupExerciseAdministration()
                }
            
            // Instructions overlay
            if !arViewModel.instructionText.isEmpty {
                VStack {
                    Text(arViewModel.instructionText)
                        .font(.headline)
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .foregroundColor(.black)
                        .cornerRadius(8)
                        .shadow(radius: 3)
                        .padding(.top, 50)
                    
                    Spacer()
                }
            }
                
            // Controls overlay
            VStack {
                // Top buttons row
                HStack {
                    Spacer()
                    
                    // Debug toggle button
                    
                    Button(action: {
                        arViewModel.showDebug.toggle()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 20))
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    
                    .padding(.trailing, 10)
                }
                .padding(.top, 50)
                .padding(.trailing, 20)
                
                Spacer()
                     
                
                
                // DRAWING CONTROLS - only visible in drawing mode
                if arViewModel.drawingMode {
                    VStack(spacing: 15) {
                        // Drawing status indicator
                        if arViewModel.isDrawingActive {
                            Text("Drawing Active")
                                .foregroundColor(.white)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background(Color.green.opacity(0.8))
                                .cornerRadius(20)
                                .shadow(radius: 2)
                        } else {
                            Text("Touch & Hold to Draw")
                                .foregroundColor(.white)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.8))
                                .cornerRadius(20)
                                .shadow(radius: 2)
                        }
                        
                        // Color palette toggle
                        
                        Button(action: {
                            arViewModel.showColorPalette.toggle()
                        }) {
                            HStack {
                                Circle()
                                    .fill(Color(arViewModel.selectedDrawingColor.uiColor))
                                    .frame(width: 20, height: 20)
                                Text("Change Color")
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                         
                        
                        // Clear drawing button
                        Button(action: {
                            arViewModel.clearDrawing()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Drawing")
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                        
                        // Exit drawing mode button
                        Button(action: {
                            arViewModel.exitDrawingMode()
                        }) {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Exit Drawing")
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.8))
                            .cornerRadius(20)
                            .shadow(radius: 2)
                        }
                    }
                    .padding(.bottom, 20)
                    
                    // Color palette pop-up
                    
                    if arViewModel.showColorPalette {
                        HStack {
                            ForEach(DrawingColor.allCases, id: \.rawValue) { color in
                                Button(action: {
                                    arViewModel.setDrawingColor(color)
                                    arViewModel.showColorPalette = false
                                }) {
                                    Circle()
                                        .fill(Color(color.uiColor))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                                .opacity(arViewModel.selectedDrawingColor == color ? 1 : 0)
                                        )
                                }
                                .padding(5)
                            }
                        }
                        .padding(10)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(15)
                        .padding(.bottom, 15)
                    }
                    
                }
                
                // BENDING EXERCISE OVERLAY - only visible in bending mode
                if arViewModel.bendingMode {
                    VStack {
                        // Exercise status indicator
                        if !arViewModel.exerciseStarted {
                            Text("TAP SCREEN TO START EXERCISE")
                                .font(.headline)
                                .padding()
                                .background(Color.blue.opacity(0.7))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding(.bottom, 10)
                        } else {
                            // Timer indicator - only show when exercise has started
                            if let stats = arViewModel.exerciseStats {
                                Text("Time: \(Int(stats.totalDuration))s")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.green.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .padding(.bottom, 10)
                            }
                        }
                        
                        // Level indicator
                        Text("Level \(arViewModel.currentLevel) of \(arViewModel.maxLevels)")
                            .font(.headline)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        // Current height indicator
                        Text("Height: \(Int(arViewModel.targetSphereHeight * 100))cm")
                            .font(.subheadline)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        
                        Spacer()
                        
                        // Exit exercise button
                        Button(action: {
                            arViewModel.exitBendingMode()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Exit Exercise")
                            }
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                        }
                        .padding(.bottom, 30)
                    }
                }
                
                // Place button for final placement - only in placement mode
                if arViewModel.placementMode && arViewModel.placementStage == .rotationAdjustment {
                    Button(action: {
                        arViewModel.placeCube()
                    }) {
                        Text("Place Cube")
                            .fontWeight(.bold)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    }
                    .padding(.bottom, 20)
                }
                
                // Bottom controls - only shown in interaction mode (not placement, not drawing, not bending)
                if arViewModel.arReady && !arViewModel.placementMode && !arViewModel.drawingMode && !arViewModel.bendingMode {
                    HStack(spacing: 20) {
                        // Enter drawing mode button
                        Button(action: {
                            arViewModel.enterDrawingMode()
                        }) {
                            VStack {
                                Image(systemName: "pencil.tip")
                                    .font(.system(size: 24))
                                Text("Draw")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                        }
                        
                        // Reset cube button
                        Button(action: {
                            arViewModel.enterPlacementMode()
                        }) {
                            VStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 24))
                                Text("Reset Cube")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                        }
                        
                        // Exercise button
                        Button(action: {
                            arViewModel.enterBendingModeWithUserSettings()
                        }) {
                            VStack {
                                Image(systemName: "figure.cooldown")
                                    .font(.system(size: 24))
                                Text("Exercise")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 70)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                        }
                    }
                    .padding(.bottom, 20)
                }
                
                // Debug panel - only shown when toggled
                
                if arViewModel.showDebug {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mode: \(arViewModel.placementMode ? "Placement" : arViewModel.drawingMode ? "Drawing" : arViewModel.bendingMode ? "Exercise" : "Interaction")")
                        if arViewModel.placementMode {
                            Text("Stage: \(arViewModel.placementStageText)")
                            Text("Position stable: \(arViewModel.positionStable ? "Yes" : "No")")
                        }
                        if arViewModel.drawingMode {
                            Text("Color: \(arViewModel.selectedDrawingColor.name)")
                            Text("Drawing active: \(arViewModel.isDrawingActive ? "Yes" : "No")")
                            Text("Drawing points: \(arViewModel.drawingPoints.count)")
                        }
                        if arViewModel.bendingMode {
                            Text("Exercise: Bending")
                            Text("Current level: \(arViewModel.currentLevel)")
                            Text("Target height: \(arViewModel.targetSphereHeight, specifier: "%.2f")m")
                        }
                        Text("Inside cube: \(arViewModel.isInsideCube ? "Yes" : "No")")
                        Text("Distance to surface: \(arViewModel.distanceToSurface, specifier: "%.3f") m")
                        Text("Rotation: \(Int(arViewModel.currentRotationDegrees))°")
                        Text("Planes detected: \(arViewModel.planesDetected)")
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding()
                }
                
                
            }
            
            // EXERCISE RESULTS POPUP - shown when exercise is completed
            if arViewModel.exerciseComplete, let stats = arViewModel.exerciseStats {
                ZStack {
                    // Semi-transparent overlay
                    Color.black.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                    
                    // Results card
                    VStack {
                        Text("Exercise Complete!")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Levels completed: \(stats.reachedLevels)")
                            Text("Max depth: \(Int(stats.maxDepthReached * 100))cm")
                            Text("Total time: \(Int(stats.totalDuration))s")
                            Text("Avg rep time: \(String(format: "%.1f", stats.averageRepTime))s")
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Added button to view in calendar
                        Button(action: {
                            // Save exercise data and navigate to calendar
                            /*dataManager.saveExerciseSession(from: arViewModel.exerciseStats, exerciseType: .bending)
                            arViewModel.exitBendingMode(completed: true)
                    
                            // Switch to the calendar tab
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                NotificationCenter.default.post(name: .switchToCalendarTab, object: nil)
                             
                             }
                             */
                            arViewModel.completeAndSaveExercise()
                            
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                Text("View in Calendar")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        
                        Button(action: {
                            //arViewModel.exitBendingMode(completed: true)
                            arViewModel.completeAndSaveExerciseContinue()
                        }) {
                            Text("Continue")
                                .fontWeight(.bold)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(radius: 10)
                    .padding(20)
                    .frame(maxWidth: 350)
                }
            }
        }
        
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if arViewModel.bendingMode && arViewModel.exerciseStarted && !arViewModel.exerciseComplete {
                // Just increment timer trigger to force UI refresh
                arViewModel.timerTrigger += 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exerciseCompleted)) { notification in
            if let exerciseData = notification.object as? ExerciseSessionData {
                dataManager.saveExerciseSession(exerciseData)
            }
        }
         
    }
}

// Keep the ARViewContainer from the original ContentView
struct ARViewContainer: UIViewRepresentable {
    var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupARView(arView)
        
        // Add tap gesture for bending exercise with improved settings
        let bendingTapRecognizer = UITapGestureRecognizer(target: viewModel, action: #selector(ARViewModel.handleBendingTap(_:)))
        // Add these properties to avoid conflicts with other gestures
        bendingTapRecognizer.requiresExclusiveTouchType = true
        bendingTapRecognizer.name = "bendingTapGesture"
        arView.addGestureRecognizer(bendingTapRecognizer)
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed
    }
}

struct TrainView_Previews: PreviewProvider {
    static var previews: some View {
        TrainView()
            .environmentObject(DataManager.shared)
    }
}
