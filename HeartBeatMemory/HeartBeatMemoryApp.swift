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
        setenv("HF_ENDPOINT", "https://hf-mirror.com/", 1)
        self.isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        
        // Load saved memories
        loadMemories()
        
        // Add sample data if empty (for demo)
        if memories.isEmpty {
            addSampleMemories()
        }
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
    
    // MARK: - Sample Data (Demo)
    
    private func addSampleMemories() {
        let calendar = Calendar.current
        
        // Sample memory 1 - 3 days ago
        let sample1 = HeartBeatMemory(
            date: calendar.date(byAdding: .day, value: -3, to: Date())!,
            title: "团队聚餐",
            summary: "和团队一起去了外滩的意大利餐厅，氛围很好，大家聊得很开心。讨论了下个季度的产品规划。",
            mood: .happy,
            category: .work,
            aiTags: ["团队", "美食", "外滩", "规划"]
        )
        
        // Sample memory 2 - 5 days ago
        let sample2 = HeartBeatMemory(
            date: calendar.date(byAdding: .day, value: -5, to: Date())!,
            title: "周末晨跑",
            summary: "早上去世纪公园跑步，春天来了，樱花开了。跑了5公里，感觉整个人都轻松了。",
            mood: .calm,
            category: .hobby,
            aiTags: ["运动", "公园", "春天", "跑步"]
        )
        
        // Sample memory 3 - 7 days ago
        let sample3 = HeartBeatMemory(
            date: calendar.date(byAdding: .day, value: -7, to: Date())!,
            title: "朋友生日派对",
            summary: "老朋友的生日派对，在一家爵士酒吧。大家好久没聚了，聊了很多以前的故事。",
            mood: .grateful,
            category: .friends,
            aiTags: ["派对", "朋友", "爵士", "回忆"]
        )
        
        memories = [sample1, sample2, sample3]
        saveMemories()
    }
    
    func deleteMemory(_ memory: HeartBeatMemory) {
        memories.removeAll { $0.id == memory.id }
        saveMemories()
    }
}
