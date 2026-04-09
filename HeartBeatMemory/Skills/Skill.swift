import Foundation

/// Skill 基础协议
protocol Skill: Identifiable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    
    /// 执行技能
    func execute(with context: SkillContext) async throws -> SkillResult
}

/// Skill 上下文（输入）
struct SkillContext: Sendable {
    let date: Date
    let events: [EventData]
    let photos: [PhotoData]
    let locations: [LocationData]
    let userPreferences: [String: Any]?
    
    init(
        date: Date,
        events: [EventData] = [],
        photos: [PhotoData] = [],
        locations: [LocationData] = [],
        userPreferences: [String: Any]? = nil
    ) {
        self.date = date
        self.events = events
        self.photos = photos
        self.locations = locations
        self.userPreferences = userPreferences
    }
}

/// Skill 结果（输出）
struct SkillResult: Sendable {
    let skillId: String
    let data: SkillData
    let metadata: [String: Sendable?]
    
    enum SkillData: Sendable {
        case keywords([String])
        case diary(DiaryContent)
        case analysis(PhotoAnalysis)
        case custom(String)
    }
}

/// 日记内容
struct DiaryContent: Sendable {
    let title: String
    let summary: String
    let mood: Mood
    let category: Category
    let tags: [String]
}

/// 照片分析结果
struct PhotoAnalysis: Sendable {
    let keywords: [String]
    let locations: [LocationData]
    let elements: [String]
}

/// Skill 错误
enum SkillError: Error, LocalizedError {
    case notFound(String)
    case executionFailed(String)
    case invalidInput(String)
    
    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Skill not found: \(id)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        }
    }
}