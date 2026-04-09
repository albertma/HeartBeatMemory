import Foundation
import Combine
/// Skill 管理器 - 使用 Skills 架构执行 AI 任务
@MainActor
class SkillManager: ObservableObject {
    static let shared = SkillManager()
    
    @Published private(set) var skills: [any Skill] = []
    @Published var executionStatus: [String: SkillStatus] = [:]
    
    enum SkillStatus: Sendable {
        case idle
        case running
        case success
        case failed(String)
    }
    
    private init() {
        registerDefaultSkills()
    }
    
    private func registerDefaultSkills() {
        skills = [
            AnalyzePhotoSkill(),
            GenerateDiarySkill()
        ]
        NSLog("SkillManager: Registered \(skills.count) skills")
    }
    
    func register(_ skill: any Skill) {
        guard !skills.contains(where: { $0.id == skill.id }) else { return }
        skills.append(skill)
    }
    
    func execute(_ skillId: String, with context: SkillContext) async throws -> SkillResult {
        guard let skill = skills.first(where: { $0.id == skillId }) else {
            throw SkillError.notFound(skillId)
        }
        
        executionStatus[skillId] = .running
        
        do {
            let result = try await skill.execute(with: context)
            executionStatus[skillId] = .success
            return result
        } catch {
            executionStatus[skillId] = .failed(error.localizedDescription)
            throw error
        }
    }
    
    func executeChain(_ skillIds: [String], with context: SkillContext) async throws -> [SkillResult] {
        var results: [SkillResult] = []
        var currentContext = context
        
        for skillId in skillIds {
            let result = try await execute(skillId, with: currentContext)
            results.append(result)
            
            // 将前一个 skill 的结果传递给下一个 skill
            switch result.data {
            case .analysis(let analysis):
                currentContext = SkillContext(
                    date: context.date,
                    events: context.events,
                    photos: context.photos,
                    locations: context.locations,
                    userPreferences: ["keywords": analysis.keywords, "locations": analysis.locations]
                )
            case .diary(let diary):
                // 日记生成后不再传递
                break
            default:
                break
            }
        }
        
        return results
    }
    
    /// 获取所有可用 Skill ID
    func availableSkillIDs() -> [String] {
        skills.map { $0.id }
    }
    
    /// 获取 Skill 信息
    func skillInfo(_ skillId: String) -> (name: String, description: String)? {
        guard let skill = skills.first(where: { $0.id == skillId }) else {
            return nil
        }
        return (skill.name, skill.description)
    }
}
