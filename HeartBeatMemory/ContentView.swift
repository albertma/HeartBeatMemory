import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .timeline
    
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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(viewContext: PersistenceController.preview.container.viewContext))
}
