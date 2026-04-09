import Foundation
import MLXLMCommon
import Photos
import UIKit
import ImageIO
import CoreLocation

/// AI分析服务 - 使用 Skills 架构
class AIService {
    static let shared = AIService()
    
    private let skillManager = SkillManager.shared
    
    // MARK: - 生成每日回忆
    
    func generateDailyMemory(
        date: Date,
        events: [EventData],
        photos: [PhotoData],
        locations: [LocationData]
    ) async throws -> HeartBeatMemory {
        
        let context = SkillContext(
            date: date,
            events: events,
            photos: photos,
            locations: locations
        )
        
        // 使用 Skills 链式执行
        let results = try await skillManager.executeChain(
            ["analyze_photo", "generate_diary"],
            with: context
        )
        
        // 提取日记结果
        guard results.count >= 2,
              case .diary(let diaryContent) = results[1].data else {
            throw SkillError.executionFailed("Failed to generate diary")
        }
        
        // 提取分析结果
        var keywords: [String] = []
        var analysisLocations: [LocationData] = []
        
        if results.count >= 1,
           case .analysis(let analysis) = results[0].data {
            keywords = analysis.keywords
            analysisLocations = analysis.locations
        }
        
        // 构建 HeartBeatMemory
        return HeartBeatMemory(
            date: date,
            title: diaryContent.title,
            summary: diaryContent.summary,
            mood: diaryContent.mood,
            category: diaryContent.category,
            locations: analysisLocations,
            photos: photos,
            events: events,
            aiTags: keywords + diaryContent.tags
        )
    }
    
    // MARK: - 单独分析照片
    
    func analyzePhotos(_ photos: [PhotoData]) async throws -> [String] {
        let context = SkillContext(
            date: Date(),
            photos: photos
        )
        
        let result = try await skillManager.execute("analyze_photo", with: context)
        
        guard case .analysis(let analysis) = result.data else {
            return []
        }
        
        return analysis.keywords
    }
    
    // MARK: - 单独生成日记
    
    func generateDiary(
        date: Date,
        events: [EventData],
        keywords: [String],
        locations: [LocationData]
    ) async throws -> (title: String, summary: String, mood: Mood, category: Category, tags: [String]) {
        
        let context = SkillContext(
            date: date,
            events: events,
            photos: [],
            locations: locations,
            userPreferences: ["keywords": keywords]
        )
        
        let result = try await skillManager.execute("generate_diary", with: context)
        
        guard case .diary(let diary) = result.data else {
            throw SkillError.executionFailed("Failed to generate diary")
        }
        
        return (diary.title, diary.summary, diary.mood, diary.category, diary.tags)
    }
}