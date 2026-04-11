import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "HeartBeatMemory")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // Preview support
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let viewContext = controller.container.viewContext
        
        // Create sample data for preview
        let entity = MemoryEntity(context: viewContext)
        entity.id = UUID()
        entity.date = Date()
        entity.title = "Sample Memory"
        entity.summary = "This is a sample memory for preview"
        entity.mood = "开心"
        entity.category = "日常"
        
        do {
            try viewContext.save()
        } catch {
            fatalError("Error creating preview data: \(error)")
        }
        
        return controller
    }()
}
