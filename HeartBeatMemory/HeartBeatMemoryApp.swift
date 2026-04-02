import SwiftUI
import Combine

@main
struct HeartBeatMemoryApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

class AppState: ObservableObject {
    @Published var isFirstLaunch: Bool
    @Published var memories: [HeartBeatMemory] = []
    @Published var isProcessing: Bool = false
    
    private let dataService = DataService.shared
    private let aiService = AIService.shared
    
    private let memoriesKey = "HeartBeatMemories"
    
    init() {
        HubApiExtension.configureMirror()
        self.isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        
        // Load saved memories
        loadMemories()
        
    }
    
    // MARK: - Memory Persistence
    
    private func loadMemories() {
        if let data = UserDefaults.standard.data(forKey: memoriesKey),
           let saved = try? JSONDecoder().decode([HeartBeatMemory].self, from: data) {
            memories = saved
        }
    }
    
    private func saveMemories() {
        if let data = try? JSONEncoder().encode(memories) {
            UserDefaults.standard.set(data, forKey: memoriesKey)
        }
    }
    
    // MARK: - Generate Memory
    
    func generateMemory(for date: Date) async {
        await MainActor.run {
            isProcessing = true
        }
        
        do {
            // Fetch data for the day
            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            
            async let eventsFetch = dataService.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            async let photosFetch = dataService.fetchPhotos(from: startOfDay, to: endOfDay)
            
            let (events, photos) = try await (eventsFetch, photosFetch)
            
            NSLog("fetched events number: \(events.count), photos:\(photos.count)")
            // Generate memory using AI
            let memory = try await aiService.generateDailyMemory(
                date: date,
                events: events,
                photos: photos,
                locations: []
            )
            
            // Save to memories
            await MainActor.run {
                memories.insert(memory, at: 0)
                saveMemories()
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            print("Error generating memory: \(error)")
        }
    }
    
    
    
    func deleteMemory(_ memory: HeartBeatMemory) {
        memories.removeAll { $0.id == memory.id }
        saveMemories()
    }
}
