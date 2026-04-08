import Foundation

/// Skill 管理器
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
            
            switch result.data {
            case .analysis(let analysis):
                currentContext = SkillContext(
                    date: context.date,
                    events: context.events,
                    photos: context.photos,
                    locations: context.locations,
                    userPreferences: ["keywords": analysis.keywords]
                )
            default:
                break
            }
        }
        return results
    }
}