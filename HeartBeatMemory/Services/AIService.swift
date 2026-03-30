import Foundation
import MLXLMCommon
/// AI分析服务
class AIService {
    static let shared = AIService()
    
    // MLXService 实例
    private let mlxService = MLXService()
    
    // MARK: - 生成每日回忆
    
    func generateDailyMemory(
        date: Date,
        events: [EventData],
        photos: [PhotoData],
        locations: [LocationData]
    ) async throws -> HeartBeatMemory {
        
        // 检查是否启用本地 LLM
//        if UserDefaults.standard.bool(forKey: "EnableLocalLLM") {
//            NSLog("enable local LLM")
//            return try await LocalLLMService.shared.generateDailyMemory(
//                date: date,
//                events: events,
//                photos: photos,
//                locations: locations
//            )
//        }
       
        let (systemMessage, userMessage) = buildMessages(date: date, events: events, photos: photos, locations: locations)
        let response = try await callMLX(messages: [systemMessage, userMessage])
        
        return parseMemoryResponse(response, date: date, events: events, photos: photos, locations: locations)
    }
    
    // MARK: - 构建消息
    
    private func buildMessages(date: Date, events: [EventData], photos: [PhotoData], locations: [LocationData]) -> (Message, Message) {
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        let dateString = dateFormatter.string(from: date)
        NSLog("Build LLM request mesage for \(dateString)")
        var prompt = """
        请分析以下数据，为 \(dateString) 生成一条温暖的"心跳回忆"。
        
        要求：
        1. 生成一个简短有感的标题（10字内）
        2. 用2-3句话总结当天的美好瞬间
        3. 判断心情类型：开心/难过/激动/平静/感恩/怀念/平常
        4. 分类：旅行/家庭/工作/朋友/爱好/美食/里程碑/日常/其他
        5. 提取3-5个关键词标签
        
        数据：
        """
        
        if !events.isEmpty {
            prompt += "\n📅 日历事件：\n"
            for event in events.prefix(10) {
                prompt += "- \(event.title)"
                if let loc = event.location { prompt += " @\(loc)" }
                if let notes = event.notes, !notes.isEmpty { prompt += ": \(notes)" }
                prompt += "\n"
            }
        }
        
        if !locations.isEmpty {
            prompt += "\n📍 位置：\n"
            for loc in locations.prefix(5) {
                prompt += "- \(loc.name)\n"
            }
        }
        
        if !photos.isEmpty {
            prompt += "\n📷 照片：\(photos.count)张\n"
        }
        
        prompt += """
        
        请用JSON格式返回：
        {
            "title": "标题",
            "summary": "总结",
            "mood": "心情",
            "category": "分类",
            "tags": ["标签1", "标签2", "标签3"]
        }
        """
        
        let systemMessage = Message(
            role: .system,
            content: "你是一个温暖的生活回忆助手，用温柔的语言帮助用户记录生活中的美好瞬间。"
        )
        let userMessage = Message(role: .user, content: prompt)
        
        return (systemMessage, userMessage)
    }
    
    // MARK: - 调用 MLX
    
    private func callMLX(messages: [Message]) async throws -> String {
        // 获取选中的模型，默认使用第一个可用模型
        let selectedModelName = UserDefaults.standard.string(forKey: "MLXModelName") ?? MLXService.availableModels.first?.name ?? "llama3.2:1b"
        NSLog("Selected model name:\(selectedModelName)")
        guard let model = MLXService.availableModels.first(where: { $0.name == selectedModelName }) else {
            throw AIError.modelNotFound
        }
        
        var fullResponse = ""
        let stream = try await mlxService.generate(messages: messages, model: model)
        
        for try await token in stream {
            fullResponse += token.chunk ?? ""
        }
        
        return fullResponse
    }
    
    // MARK: - 解析结果
    
    private func parseMemoryResponse(_ response: String, date: Date, events: [EventData], photos: [PhotoData], locations: [LocationData]) -> HeartBeatMemory {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HeartBeatMemory(
                date: date,
                title: "这一天",
                summary: response,
                mood: .neutral,
                category: .daily
            )
        }
        
        let title = json["title"] as? String ?? "这一天"
        let summary = json["summary"] as? String ?? ""
        let moodString = json["mood"] as? String ?? "平常"
        let categoryString = json["category"] as? String ?? "日常"
        let tags = json["tags"] as? [String] ?? []
        
        let mood = Mood.allCases.first { $0.rawValue == moodString } ?? .neutral
        let category = Category.allCases.first { $0.rawValue == categoryString } ?? .other
        
        return HeartBeatMemory(
            date: date,
            title: title,
            summary: summary,
            mood: mood,
            category: category,
            locations: locations,
            photos: photos,
            events: events,
            aiTags: tags
        )
    }
}

// MARK: - 错误类型

enum AIError: Error {
    case modelNotFound
    case invalidResponse
    case generationFailed
}
