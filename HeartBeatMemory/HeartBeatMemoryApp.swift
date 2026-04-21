import SwiftUI
import Combine
import CoreData

@main
struct HeartBeatMemoryApp: App {
    @StateObject private var appState = AppState(viewContext: PersistenceController.shared.container.viewContext)
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
        }
    }
}

class AppState: ObservableObject {
    @Published var isFirstLaunch: Bool
    @Published var memories: [HeartBeatMemory] = []
    @Published var isProcessing: Bool = false
    @Published var toastMessage: String?
    @Published var pendingPhotoDates: [Date] = []  // 有照片但未生成memory的日期
    
    private let dataService = DataService.shared
    private let aiService = AIService.shared
    private var viewContext: NSManagedObjectContext?
    
    private let memoriesKey = "HeartBeatMemories"
    
    init(viewContext: NSManagedObjectContext? = nil) {
        HubApiExtension.configureMirror()
        self.viewContext = viewContext
        self.isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        
        // Load saved memories
        loadMemories()
    }
    
    // MARK: - Persistence
    
    private func loadMemories() {
        // Try Core Data first if available
        if let context = viewContext {
            loadMemoriesFromCoreData(context)
        }
//        else {
//            loadMemoriesFromUserDefaults()
//        }
    }
    
    private func loadMemoriesFromCoreData(_ context: NSManagedObjectContext) {
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MemoryEntity.date, ascending: false)]
        
        do {
            let entities = try context.fetch(request)
            memories = entities.compactMap { entity in
                HeartBeatMemory(
                    id: entity.id ?? UUID(),
                    date: entity.date ?? Date(),
                    title: entity.title ?? "",
                    summary: entity.summary ?? "",
                    mood: Mood(rawValue: entity.mood ?? "平常") ?? .neutral,
                    category: Category(rawValue: entity.category ?? "其他") ?? .other,
                    locations: decodeData(entity.locationsData) ?? [],
                    photos: decodeData(entity.photosData) ?? [],
                    events: decodeData(entity.eventsData) ?? [],
                    aiTags: decodeData(entity.aiTagsData) ?? [],
                    rawData: [:]
                )
            }
        } catch {
            NSLog("Error loading memories from Core Data: \(error)")
            //loadMemoriesFromUserDefaults()
        }
    }
    
//    private func loadMemoriesFromUserDefaults() {
//        if let data = UserDefaults.standard.data(forKey: memoriesKey),
//           let saved = try? JSONDecoder().decode([HeartBeatMemory].self, from: data) {
//            memories = saved
//        }
//    }
    
    private func saveMemoryToCoreData(_ memory: HeartBeatMemory, context: NSManagedObjectContext) {
        let entity = MemoryEntity(context: context)
        entity.id = memory.id
        entity.date = memory.date
        entity.title = memory.title
        entity.summary = memory.summary
        entity.mood = memory.mood.rawValue
        entity.category = memory.category.rawValue
        entity.aiTagsData = encodeData(memory.aiTags)
        entity.locationsData = encodeData(memory.locations)
        entity.photosData = encodeData(memory.photos)
        entity.eventsData = encodeData(memory.events)
        
        do {
            try context.save()
        } catch {
            NSLog("Error saving memory to Core Data: \(error)")
        }
    }
    
//    private func saveMemoryToUserDefaults(_ memory: HeartBeatMemory) {
//        var currentMemories = memories
//        currentMemories.insert(memory, at: 0)
//        if let data = try? JSONEncoder().encode(currentMemories) {
//            UserDefaults.standard.set(data, forKey: memoriesKey)
//        }
//    }
    
    private func deleteMemoryFromCoreData(_ memory: HeartBeatMemory, context: NSManagedObjectContext) {
        let request: NSFetchRequest<MemoryEntity> = MemoryEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", memory.id as CVarArg)
        
        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            try context.save()
        } catch {
            NSLog("Error deleting memory from Core Data: \(error)")
        }
    }
    
//    private func deleteMemoryFromUserDefaults(_ memory: HeartBeatMemory) {
//        var currentMemories = memories
//        currentMemories.removeAll { $0.id == memory.id }
//        if let data = try? JSONEncoder().encode(currentMemories) {
//            UserDefaults.standard.set(data, forKey: memoriesKey)
//        }
//    }
    
    // MARK: - Codable Helpers
    
    private func encodeData<T: Encodable>(_ value: T?) -> Data? {
        guard let value = value else { return nil }
        return try? JSONEncoder().encode(value)
    }
    
    private func decodeData<T: Decodable>(_ data: Data?) -> T? {
        guard let data = data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Generate Memory
    
    func generateMemory(for date: Date) async {
        await MainActor.run {
            isProcessing = true
        }
        
        do {
            let startOfDay = Calendar.current.startOfDay(for: date)
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
            
            async let eventsFetch = dataService.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            async let photosFetch = dataService.fetchPhotos(from: startOfDay, to: endOfDay)
            
            let (events, photos) = try await (eventsFetch, photosFetch)
            
            NSLog("fetched events number: \(events.count), photos:\(photos.count)")
            
            // 没有照片时不生成日记
            guard !photos.isEmpty else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM月dd日"
                let dateString = dateFormatter.string(from: date)
                NSLog("No photos for date \(date), skip generating diary")
                await MainActor.run {
                    isProcessing = false
                    toastMessage = "\(dateString) 没有照片，无法生成日记"
                }
                return
            }
            
            let memory = try await aiService.generateDailyMemory(
                date: date,
                events: events,
                photos: photos,
                locations: []
            )
            
            await MainActor.run {
                memories.insert(memory, at: 0)
                
                // Save to Core Data or UserDefaults
                if let context = viewContext {
                    saveMemoryToCoreData(memory, context: context)
                }
//                else {
//                    saveMemoryToUserDefaults(memory)
//                }
                
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                isProcessing = false
            }
            NSLog("Error generating memory: \(error)")
        }
    }
    
    func deleteMemory(_ memory: HeartBeatMemory) {
        memories.removeAll { $0.id == memory.id }
        
        if let context = viewContext {
            deleteMemoryFromCoreData(memory, context: context)
        }
//        else {
//            deleteMemoryFromUserDefaults(memory)
//        }
    }
    
    // MARK: - Load Pending Photo Dates
    
    /// 加载近30天有照片但未生成memory的日期列表
    func loadPendingPhotoDates() async {
        let photoDates = await DataService.shared.fetchPhotoDatesInLast30Days()
        let memoryDates = Set(memories.map { Calendar.current.startOfDay(for: $0.date) })
        
        let pending = photoDates.filter { !memoryDates.contains($0) }
        
        await MainActor.run {
            pendingPhotoDates = pending
        }
        
        NSLog("Pending photo dates: \(pending.count)")
    }
    
    /// 生成下一个pending的memory
    func generateNextPendingMemory() async {
        guard !pendingPhotoDates.isEmpty else {
            await MainActor.run {
                toastMessage = "所有有照片的日期都已生成回忆"
            }
            return
        }
        
        guard !isProcessing else { return }
        
        let nextDate = pendingPhotoDates.removeFirst()
        await generateMemory(for: nextDate)
        
        // 重置状态，允许继续加载下一个
        NSLog("generateNextPendingMemory completed, pending count: \(pendingPhotoDates.count)")
    }
}
