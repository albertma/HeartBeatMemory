import Foundation
import CoreLocation

/// 记忆条目
struct HeartBeatMemory: Identifiable, Codable {
    let id: UUID
    let date: Date
    let title: String
    let summary: String
    let mood: Mood
    let category: Category
    let locations: [LocationData]
    let photos: [PhotoData]
    let events: [EventData]
    let aiTags: [String]
    let rawData: [String: String]
    
    init(id: UUID = UUID(),
         date: Date,
         title: String,
         summary: String,
         mood: Mood = .neutral,
         category: Category = .other,
         locations: [LocationData] = [],
         photos: [PhotoData] = [],
         events: [EventData] = [],
         aiTags: [String] = [],
         rawData: [String: String] = [:]) {
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.mood = mood
        self.category = category
        self.locations = locations
        self.photos = photos
        self.events = events
        self.aiTags = aiTags
        self.rawData = rawData
    }
}

/// 心情
enum Mood: String, Codable, CaseIterable {
    case happy = "开心"
    case sad = "难过"
    case excited = "激动"
    case calm = "平静"
    case grateful = "感恩"
    case nostalgic = "怀念"
    case neutral = "平常"
    
    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .sad: return "😢"
        case .excited: return "🎉"
        case .calm: return "😌"
        case .grateful: return "🙏"
        case .nostalgic: return "💭"
        case .neutral: return "😐"
        }
    }
}

/// 分类
enum Category: String, Codable, CaseIterable {
    case travel = "旅行"
    case family = "家庭"
    case work = "工作"
    case friends = "朋友"
    case hobby = "爱好"
    case food = "美食"
    case milestone = "里程碑"
    case daily = "日常"
    case other = "其他"
}

/// 位置数据
struct LocationData: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date?
    
    init(name: String, latitude: Double, longitude: Double, timestamp: Date?) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }
}

/// 照片数据
struct PhotoData: Codable {
    let identifier: String
    let creationDate: Date?
    let location: LocationData?
    
    init(identifier: String, creationDate: Date?, location: LocationData?) {
        self.identifier = identifier
        self.creationDate = creationDate
        self.location = location
    }
}

/// 日历事件
struct EventData: Codable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date?
    let location: String?
    let notes: String?
    
    init(identifier: String, title: String, startDate: Date, endDate: Date?, location: String?, notes: String?) {
        self.identifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
    }
}
