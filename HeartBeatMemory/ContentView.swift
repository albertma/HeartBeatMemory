import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: Tab = .timeline
    
    enum Tab {
        case timeline
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
        .environmentObject(AppState())
}
