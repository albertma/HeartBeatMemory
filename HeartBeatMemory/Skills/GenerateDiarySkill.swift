import Foundation
import MLXLMCommon

/// 日记生成 Skill
final class GenerateDiarySkill: Skill {
    let id = "generate_diary"
    let name = "Generate Diary"
    let description = "基于上下文生成温暖的回忆日记"
    
    private let mlxService = MLXService()
    
    func execute(with context: SkillContext) async throws -> SkillResult {
        var photoKeywords: [String] = []
        var allLocations = context.locations
        
        if let prefs = context.userPreferences {
            if let keywords = prefs["keywords"] as? [String] {
                photoKeywords = keywords
            }
            if let locs = prefs["locations"] as? [LocationData] {
                allLocations = locs + allLocations
            }
        }
        
        let (systemMessage, userMessage) = buildPrompt(
            date: context.date,
            events: context.events,
            photoKeywords: photoKeywords,
            locations: allLocations
        )
        
        let response = try await callLLM(messages: [systemMessage, userMessage])
        let diary = try parseDiaryResponse(response, date: context.date)
        
        return SkillResult(
            skillId: id,
            data: .diary(DiaryContent(
                title: diary.title,
                summary: diary.summary,
                mood: diary.mood,
                category: diary.category,
                tags: diary.tags
            )),
            metadata: ["date": context.date, "keywords": photoKeywords, "timestamp": Date()]
        )
    }
    
    private struct PromptMessages {
        let system: Message
        let user: Message
    }
    
    private func buildPrompt(
        date: Date,
        events: [EventData],
        photoKeywords: [String],
        locations: [LocationData]
    ) -> PromptMessages {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        let dateString = formatter.string(from: date)
        
        var context = ""
        
        if !locations.isEmpty {
            let locNames = locations.prefix(3).compactMap { $0.name }.joined(separator: "、")
            context += "📍 位置：\(locNames)\n"
        }
        if !events.isEmpty {
            let eventTitles = events.prefix(3).map { $0.title }.joined(separator: "、")
            context += "📅 日程：\(eventTitles)\n"
        }
        if !photoKeywords.isEmpty {
            let keywords = photoKeywords.prefix(8).joined(separator: "、")
            context += "🏷️ 画面：\(keywords)\n"
        }
        
        let prompt = """
        今天是 \(dateString)。请结合图片和下方信息，写一篇温暖的回忆日记。
        
        ### 信息：
        \(context)
        
        ### 要求：
        1. 视觉优先：第一人称，描述画面中的光影、人物表情、动作或氛围
        2. 自然治愈的语气，60-100 字
        3. 直接返回 JSON，不要 markdown
        
        ### JSON 格式：
        {"title":"标题","summary":"正文","mood":"心情","category":"分类","tags":["标签"]}
        
        可选心情：开心、平静、激动、治愈、怀念、平常
        可选分类：旅行、美食、日常、聚会、工作、其他
        """
        
        let systemMsg = Message(role: .system, content: "你是一个温暖的生活记录助手。")
        let userMsg = Message(role: .user, content: prompt)
        
        return PromptMessages(system: systemMsg, user: userMsg)
    }
    
    private func callLLM(messages: [Message]) async throws -> String {
        let modelName = UserDefaults.standard.string(forKey: "MLXModelName") 
            ?? MLXService.availableModels.first(where: { $0.type == .llm })?.name 
            ?? "qwen3:1.7b"
        
        guard let model = MLXService.availableModels.first(where: { $0.name == modelName }) else {
            throw SkillError.executionFailed("LLM model not found")
        }
        
        var fullResponse = ""
        let stream = try await mlxService.generate(messages: messages, model: model)
        
        for try await token in stream {
            fullResponse += token.chunk ?? ""
        }
        
        return fullResponse
    }
    
    private struct ParsedDiary {
        let title: String
        let summary: String
        let mood: Mood
        let category: Category
        let tags: [String]
    }
    
    private func parseDiaryResponse(_ response: String, date: Date) throws -> ParsedDiary {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            if start < end {
                cleaned = String(cleaned[start...end])
            }
        }
        
        cleaned = cleaned
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillError.executionFailed("无法解析日记")
        }
        
        let title = json["title"] as? String ?? "这一天"
        let summary = json["summary"] as? String ?? response
        let moodStr = json["mood"] as? String ?? "平常"
        let categoryStr = json["category"] as? String ?? "日常"
        let tags = json["tags"] as? [String] ?? []
        
        let mood = Mood.allCases.first { $0.rawValue == moodStr } ?? .neutral
        let category = Category.allCases.first { $0.rawValue == categoryStr } ?? .other
        
        return ParsedDiary(title: title, summary: summary, mood: mood, category: category, tags: tags)
    }
}