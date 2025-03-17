//
//  ContentView.swift Updates
//  MobilityAR
//

import SwiftUI
import RealityKit

struct ContentView : View {
    @StateObject private var arViewModel = ARViewModel()
    @State private var showDebug = false
    @State private var showColorPalette = false
    
    var body: some View {
        ZStack {
            ARViewContainer(viewModel: arViewModel)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    arViewModel.prepareHaptics()
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
                        showDebug.toggle()
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
                            showColorPalette.toggle()
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
                    if showColorPalette {
                        HStack {
                            ForEach(DrawingColor.allCases, id: \.rawValue) { color in
                                Button(action: {
                                    arViewModel.setDrawingColor(color)
                                    showColorPalette = false
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
                
                // Bottom controls - only shown in interaction mode (not placement and not drawing)
                if arViewModel.arReady && !arViewModel.placementMode && !arViewModel.drawingMode {
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
                    }
                    .padding(.bottom, 20)
                }
                
                // Debug panel - only shown when toggled
                if showDebug {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mode: \(arViewModel.placementMode ? "Placement" : arViewModel.drawingMode ? "Drawing" : "Interaction")")
                        if arViewModel.placementMode {
                            Text("Stage: \(arViewModel.placementStageText)")
                        }
                        if arViewModel.drawingMode {
                            Text("Color: \(arViewModel.selectedDrawingColor.name)")
                            Text("Drawing active: \(arViewModel.isDrawingActive ? "Yes" : "No")")
                            Text("Drawing points: \(arViewModel.drawingPoints.count)")
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
        }
    }
}

// UIViewRepresentable for ARView remains unchanged
struct ARViewContainer: UIViewRepresentable {
    var viewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        viewModel.setupARView(arView)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}
