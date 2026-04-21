import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .timeline
    @State private var showToast = false
    
    enum Tab {
        case timeline
        case chat
        case search
        case settings
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView()
                .tabItem {
                    Label(LocalizedStringKey("timeline"), systemImage: "clock")
                }
                .tag(Tab.timeline)
            
            ChatView()
                .tabItem {
                    Label(LocalizedStringKey("chat"), systemImage: "message")
                }
                .tag(Tab.chat)
            
            SearchView()
                .tabItem {
                    Label(LocalizedStringKey("search"), systemImage: "magnifyingglass")
                }
                .tag(Tab.search)
            
            
            SettingsView()
                .tabItem {
                    Label(LocalizedStringKey("settings"), systemImage: "gear")
                }
                .tag(Tab.settings)
        }
        .sheet(isPresented: $appState.isFirstLaunch) {
            OnboardingView()
        }
        .onChange(of: appState.toastMessage) { oldValue, newValue in
            if newValue != nil {
                showToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showToast = false
                    appState.toastMessage = nil
                }
            }
        }
        .overlay {
            if showToast, let message = appState.toastMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                        .padding(.bottom, 50)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: showToast)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(viewContext: PersistenceController.preview.container.viewContext))
}
