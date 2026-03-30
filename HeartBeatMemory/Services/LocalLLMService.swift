import Foundation

/// 本地 LLM 服务 - 使用 llama.cpp
/// 模型需要手动下载并放入 Models/MLModels 目录
class LocalLLMService {
    static let shared = LocalLLMService()
    
    private var baseURL: String {
        // 本地服务器地址，生产环境可配置
        UserDefaults.standard.string(forKey: "LocalLLMURL") ?? "http://localhost:8080"
    }
    
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "EnableLocalLLM")
    }
    
    // MARK: - 切换模型源
    
    /// 启用本地 LLM
    func enableLocalModel(_ enable: Bool) {
        UserDefaults.standard.set(enable, forKey: "EnableLocalLLM")
    }
    
    /// 设置本地服务器地址
    func setServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "LocalLLMURL")
    }
    
    // MARK: - 生成每日回忆
    
    func generateDailyMemory(
        date: Date,
        events: [EventData],
        photos: [PhotoData],
        locations: [LocationData]
    ) async throws -> HeartBeatMemory {
        
        let prompt = buildPrompt(date: date, events: events, photos: photos, locations: locations)
        
        let response: String
        if isEnabled {
            response = try await callLocalLLM(prompt: prompt)
        } else {
            // 回退到 OpenAI
            return try await AIService.shared.generateDailyMemory(
                date: date,
                events: events,
                photos: photos,
                locations: locations
            )
        }
        
        return parseMemoryResponse(response, date: date, events: events, photos: photos, locations: locations)
    }
    
    // MARK: - 构建提示词
    
    private func buildPrompt(date: Date, events: [EventData], photos: [PhotoData], locations: [LocationData]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        let dateString = dateFormatter.string(from: date)
        
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
        
        return prompt
    }
    
    // MARK: - 调用本地 LLM
    
    private func callLocalLLM(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "prompt": prompt,
            "max_tokens": 512,
            "temperature": 0.7
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.networkError
        }
        
        let result = try JSONDecoder().decode(LocalLLMResponse.self, from: data)
        return result.text
    }
    
    // MARK: - 解析结果
    
    private func parseMemoryResponse(_ response: String, date: Date, events: [EventData], photos: [PhotoData], locations: [LocationData]) -> HeartBeatMemory {
        // 尝试解析 JSON
        let cleanedResponse = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedResponse.data(using: .utf8),
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
    
    // MARK: - 检查服务状态
    
    func checkServerStatus() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - 错误类型

enum LLMError: Error {
    case modelNotLoaded
    case networkError
    case invalidResponse
}

// MARK: - 响应模型

struct LocalLLMResponse: Codable {
    let text: String
}
