import Foundation
import MLXLMCommon

/// 日记生成 Skill - 使用 MLX LLM 生成日记
final class GenerateDiarySkill: Skill, @unchecked Sendable {
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
        
        let messages = buildMessages(
            date: context.date,
            events: context.events,
            photoKeywords: photoKeywords,
            locations: allLocations
        )
        
        let modelName = UserDefaults.standard.string(forKey: "MLXModelName") 
            ?? MLXService.availableModels.first(where: { $0.type == .llm })?.name 
            ?? "qwen2VL:2b"
        
        guard let model = MLXService.availableModels.first(where: { $0.name == modelName }) else {
            throw SkillError.executionFailed("LLM model not found")
        }
        
        var fullResponse = ""
        let stream = try await mlxService.generate(messages: [messages.system, messages.user], model: model)
        
        for try await token in stream {
            fullResponse += token.chunk ?? ""
        }
        
        let diary = try parseDiaryResponse(fullResponse, date: context.date)
        
        return SkillResult(
            skillId: id,
            data: .diary(DiaryContent(
                title: diary.title,
                summary: diary.summary,
                mood: diary.mood,
                category: diary.category,
                tags: diary.tags
            )),
            metadata: ["date": context.date, "keywords": photoKeywords]
        )
    }
    
    private struct Messages {
        let system: Message
        let user: Message
    }
    
    private func buildMessages(
        date: Date,
        events: [EventData],
        photoKeywords: [String],
        locations: [LocationData]
    ) -> Messages {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        let dateString = formatter.string(from: date)
        
        var context = ""
        
        if !photoKeywords.isEmpty {
            let keywords = photoKeywords.prefix(8).joined(separator: "、")
            context += "画面：\(keywords)\n"
        }
        if !locations.isEmpty {
            let locNames = locations.prefix(3).compactMap { $0.name }.joined(separator: "、")
            context += "位置：\(locNames)\n"
        }
        if !events.isEmpty {
            let eventTitles = events.prefix(3).map { $0.title }.joined(separator: "、")
            context += "日程：\(eventTitles)\n"
        }
        
        // 获取用户设置的 diary prompt
        let userDiaryPrompt = UserDefaults.standard.string(forKey: "diaryPrompt") 
            ?? "根据背景关键词，写一篇日记，第一人称，视觉优先，描写光影、氛围、动作，100字内，并给出标题。"
        
        let prompt = """
        严格按照以下要求生成，只输出JSON，不输出任何其他内容。

        任务：\(userDiaryPrompt)

        背景关键词：\(context)

        输出JSON格式：
        {"title":"标题","summary":"日记正文","mood":"从开心/平静/激动/治愈/怀念/平常选一个","category":"从旅行/美食/日常/聚会/工作/其他选一个","tags":["标签1","标签2"]}

        只输出JSON，禁止多余文字
        """
        
        let systemMsg = Message(role: .system, content: "你只输出标准JSON。不写文字，不解释，不闲聊")
        let userMsg = Message(role: .user, content: prompt)
        
        return Messages(system: systemMsg, user: userMsg)
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
        
        if let parsed = try? parseJsonFormat(cleaned) {
            return parsed
        }
        
        if let parsed = try? parseMarkdownFormat(cleaned) {
            return parsed
        }
        
        throw SkillError.executionFailed("无法解析日记")
    }
    
    private func parseJsonFormat(_ response: String) throws -> ParsedDiary {
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
            throw SkillError.executionFailed("非JSON格式")
        }
        
        return extractFields(from: json, originalResponse: cleaned)
    }
    
    private func parseMarkdownFormat(_ response: String) throws -> ParsedDiary {
        var title = "这一天"
        var summary = response
        var moodStr = "平常"
        var categoryStr = "日常"
        var tags: [String] = []
        
        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmed.hasPrefix("标题:") {
                title = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("正文:") {
                summary = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("心情:") {
                moodStr = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("分类:") {
                categoryStr = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("标签:") {
                let tagStr = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                tags = tagStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        
        guard title != "这一天" || !summary.isEmpty else {
            throw SkillError.executionFailed("非Markdown格式")
        }
        
        let json: [String: Any] = [
            "title": title,
            "summary": summary,
            "mood": moodStr,
            "category": categoryStr,
            "tags": tags
        ]
        return extractFields(from: json, originalResponse: response)
    }
    
    private func extractFields(from json: [String: Any], originalResponse: String) -> ParsedDiary {
        let title = json["title"] as? String ?? "这一天"
        let summary = json["summary"] as? String ?? originalResponse
        let moodStr = json["mood"] as? String ?? "平常"
        let categoryStr = json["category"] as? String ?? "日常"
        let tags = json["tags"] as? [String] ?? []
        
        let moods = moodStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
            + moodStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let mood = Mood.allCases.first { moods.contains($0.rawValue) } ?? .neutral
        
        let category = Category.allCases.first { $0.rawValue == categoryStr } ?? .other
        
        return ParsedDiary(title: title, summary: summary, mood: mood, category: category, tags: tags)
    }
}
