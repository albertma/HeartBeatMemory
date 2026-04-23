import SwiftUI
import Combine

struct SplashScreenView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var splashState = SplashScreenState()
    
    @State private var countdown: Int = 3
    @State private var timer: Timer?
    @State private var isLoadingComplete: Bool = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App Icon/Logo
                Image(systemName: "heart.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                
                // App Name
                Text("HeartBeat Memory")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(radius: 5)
                
                Spacer()
                
                // Loading status
                VStack(spacing: 20) {
                    // LLM Loading Progress
                    if !splashState.isLLMLoaded {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Loading LLM...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            
                            if splashState.loadingProgress > 0 {
                                Text("\(Int(splashState.loadingProgress * 100))%")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    } else {
                        // LLM loaded successfully
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("LLM Ready")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    }
                    
                    // Divider line
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 150, height: 1)
                        .padding(.vertical, 10)
                    
                    // Countdown or Enter App button
                    if splashState.isLLMLoaded {
                        if countdown > 0 {
                            Text("Entering in \(countdown)s...")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .transition(.opacity)
                        } else {
                            Button(action: {
                                enterApp()
                            }) {
                                Text("Enter App")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(25)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 25)
                                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                    )
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    } else {
                        Text("Please wait...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 30)
            }
            .padding()
        }
        .onAppear {
            startSplashSequence()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startSplashSequence() {
        // Start countdown timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                withAnimation(.easeInOut(duration: 0.3)) {
                    countdown -= 1
                }
            }
        }
        
        // Start loading LLM in background
        Task {
            await splashState.loadLLM()
        }
    }
    
    private func enterApp() {
        timer?.invalidate()
        isLoadingComplete = true
        // Set the splash as shown so we don't show it again
        UserDefaults.standard.set(true, forKey: "hasShownSplashScreen")
    }
}

// MARK: - SplashScreenState

class SplashScreenState: ObservableObject {
    @Published var isLLMLoaded: Bool = false
    @Published var loadingProgress: Double = 0.0
    @Published var loadingError: String?
    
    @MainActor
    func loadLLM() async {
        // Create MLXService instance to check bundled model
        let mlxService = MLXService()
        
        // Check if model is already bundled/loaded
        if mlxService.hasBundledModel {
            // Model is bundled, mark as loaded immediately
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay for visual feedback
            isLLMLoaded = true
            loadingProgress = 1.0
            NSLog("MLX Service has bundle model is \(isLLMLoaded)")
            return
        }
        
        // Load model
        do {
            loadingProgress = 0.1
            // Simulate progress updates
            for i in 1...10 {
                NSLog("MLX Service progress updated:\(loadingProgress)")
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                loadingProgress = Double(i) * 0.09
            }
            isLLMLoaded = true
            loadingProgress = 1.0
        } catch {
            loadingError = error.localizedDescription
            NSLog("loadingError: \(loadingError)")
        }
    }
}

// MARK: - Preview

#Preview {
    SplashScreenView()
        .environmentObject(AppState(viewContext: nil))
}
