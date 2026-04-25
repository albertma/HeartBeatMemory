import Foundation
import MLXLMCommon

/// 日记生成 Skill - 使用 MLX LLM 生成日记
final class GenerateDiarySkill: Skill, @unchecked Sendable {
    let id = "generate_diary"
    let name = "Generate Diary"
    let description = "基于上下文生成温暖的回忆日记"
    
    private let mlxService = MLXService()
    private let language = UserDefaults.standard.string(forKey: "language") ?? "zh"
    
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
        
// 获取用户设置的 diary prompt 和语言设置
        let userDiaryPrompt = UserDefaults.standard.string(forKey: "diaryPrompt") 
            ?? (language == "en" 
                ? "Write a diary based on the context, first person, visual priority, describe light, atmosphere, actions, within 100 words, and give a title."
                : "根据背景关键词，写一篇日记，第一人称，视觉优先，描写光影、氛围、动作，100字内，并给出标题。")
        
        let (systemPrompt, outputFormat) = language == "en" ? (
            system: "You only output standard JSON. No explanation, no small talk.",
            format: """
            {"title":"Title","summary":"Diary body","mood":"Choose from happy/calm/excited/healing/nostalgic/ordinary","category":"Choose from travel/food/daily/聚会/work/other","tags":["tag1","tag2"]}
            """
        ) : (
            system: "你只输出标准JSON。不写文字，不解释，不闲聊",
            format: """
            {"title":"标题","summary":"日记正文","mood":"从开心/平静/激动/治愈/怀念/平常选一个","category":"从旅行/美食/日常/聚会/工作/其他选一个","tags":["标签1","标签2"]}
            """
        )

        let prompt = """
        Strictly follow the requirements below, output only JSON, nothing else.

        Task: \(userDiaryPrompt)

        Context: \(context)

        Output format:
        \(outputFormat)

        Output JSON only, no extra text.
        """

        let systemMsg = Message(role: .system, content: systemPrompt)
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
        var title = language == "en" ? "This Day" : "这一天"
        var summary = response
        var moodStr = language == "en" ? "ordinary" : "平常"
        var categoryStr = language == "en" ? "daily" : "日常"
        var tags: [String] = []
        
        // Support both Chinese and English prefixes
        let titlePrefixes = language == "en" ? ["Title:", "标题:"] : ["标题:", "Title:"]
        let summaryPrefixes = language == "en" ? ["Content:", "正文:"] : ["正文:", "Content:"]
        let moodPrefixes = language == "en" ? ["Mood:", "心情:"] : ["心情:", "Mood:"]
        let categoryPrefixes = language == "en" ? ["Category:", "分类:"] : ["分类:", "Category:"]
        let tagPrefixes = language == "en" ? ["Tags:", "标签:"] : ["标签:", "Tags:"]
        
        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            
            if key == "Title" || key == "标题" {
                title = value
            } else if key == "Content" || key == "正文" {
                summary = value
            } else if key == "Mood" || key == "心情" {
                moodStr = value
            } else if key == "Category" || key == "分类" {
                categoryStr = value
            } else if key == "Tags" || key == "标签" {
                let separators = language == "en" ? CharacterSet(charactersIn: ",") : CharacterSet(charactersIn: "、")
                tags = value.components(separatedBy: separators).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        let validTitle = language == "en" ? "This Day" : "这一天"
        guard title != validTitle || !summary.isEmpty else {
            throw SkillError.executionFailed("Non-markdown format")
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
        let title = json["title"] as? String ?? (language == "en" ? "This Day" : "这一天")
        let summary = json["summary"] as? String ?? originalResponse
        let moodStr = json["mood"] as? String ?? (language == "en" ? "ordinary" : "平常")
        let categoryStr = json["category"] as? String ?? (language == "en" ? "daily" : "日常")
        let tags = json["tags"] as? [String] ?? []
        
        let moods = moodStr.components(separatedBy: "、").map { $0.trimmingCharacters(in: .whitespaces) }
            + moodStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let mood = Mood.allCases.first { moods.contains($0.rawValue) } ?? .neutral
        
        let category = Category.allCases.first { $0.rawValue == categoryStr } ?? .other
        
        return ParsedDiary(title: title, summary: summary, mood: mood, category: category, tags: tags)
    }
}
