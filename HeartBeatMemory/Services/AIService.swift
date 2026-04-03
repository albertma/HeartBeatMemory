import Foundation
import MLXLMCommon
import Photos
import UIKit
import ImageIO
import CoreLocation

/// AI分析服务
class AIService {
    static let shared = AIService()
    
    // MLXService 实例
    private let mlxService = MLXService()
    
    // VLM模型用于图像分析
    private var visionModel: LMModel? {
        // 查找可用的VLM模型
        MLXService.availableModels.first { $0.type == .vlm }
    }
    
    // MARK: - 生成每日回忆
    func generateDailyMemory(
        date: Date,
        events: [EventData],
        photos: [PhotoData],
        locations: [LocationData]
    ) async throws -> HeartBeatMemory {
        
        // 1. 先用VLM分析每张照片，提取关键词和地点信息
        var photoKeywords: [String] = []
        var photoLocations: [LocationData] = []
        
        for photo in photos.prefix(20) {  // 限制最多20张照片
            // 收集照片的地点信息
            if let photoLoc = photo.location {
                // 检查是否已存在相同位置
                let exists = photoLocations.contains { existing in
                    abs(existing.latitude - photoLoc.latitude) < 0.001 && 
                    abs(existing.longitude - photoLoc.longitude) < 0.001
                }
                if !exists {
                    // 逆地理编码获取地点名称
                    let locationName = await reverseGeocode(latitude: photoLoc.latitude, longitude: photoLoc.longitude)
                    let namedLocation = LocationData(
                        name: locationName,
                        latitude: photoLoc.latitude,
                        longitude: photoLoc.longitude,
                        timestamp: photoLoc.timestamp
                    )
                    photoLocations.append(namedLocation)
                }
            }
            
            // VLM分析照片内容
            if let keywords = await analyzePhoto(photo) {
                photoKeywords.append(contentsOf: keywords)
            }
        }
        
        NSLog("Photo keywords extracted: \(photoKeywords)")
        NSLog("Photo locations extracted: \(photoLocations.map { $0.name })")
        
        if photoKeywords.count > 5{
            photoKeywords = Array(photoKeywords.prefix(5))
        }
        
        // 合并传入的locations和照片的locations
        let allLocations = locations + photoLocations
        
        // 2. 构建包含照片关键词和地点的prompt
        let (systemMessage, userMessage) = buildMessages(
            date: date,
            events: events,
            photoKeywords: photoKeywords,
            locations: allLocations
        )
        
        // 3. 使用LLM生成回忆
        let response = try await callMLX(messages: [systemMessage, userMessage])
        
        return parseMemoryResponse(response, date: date, events: events, photos: photos, locations: allLocations, photoKeywords: photoKeywords)
    }
    
    // MARK: - 逆地理编码
    private func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
               
                var components: [String] = []
                if let aresOfInterest = placemark.areasOfInterest{
                    if !aresOfInterest.isEmpty{
                        components.append(contentsOf: aresOfInterest)
                    }
                }
                if let subThoroughfare = placemark.subThoroughfare{
                    components.append(subThoroughfare)
                }
                if let thoroughfare = placemark.thoroughfare{
                    components.append(thoroughfare)
                }
                if let locality = placemark.locality {
                    components.append(locality)
                }
                if let country = placemark.country {
                    components.append(country)
                }
                let name = components.joined(separator: " ")
                return name.isEmpty ? "未知地点" : name
            }
        } catch {
            NSLog("Reverse geocode failed: \(error)")
        }
        return "未知地点"
    }
    
    // MARK: - 分析单张照片
    
    private func analyzePhoto(_ photo: PhotoData) async -> [String]? {
        NSLog("🔍 Start to analyze photo: \(photo.identifier)")
        
        // 1. 确保清理旧的 VLM 图片资源
        cleanupVLMImages()
        
        // 2. 加载图片
        guard let image = await loadImage(from: photo) else {
            NSLog("❌ Failed to load image for photo: \(photo.identifier)")
            return nil
        }
        NSLog("✅ Image loaded, size: \(image.size)")
        
        // 3. 检查 VLM 模型
        guard let vlm = visionModel else {
            NSLog("❌ No VLM model available")
            return nil
        }
        
        // 4. 保存图片到临时文件
        // 💡 建议：在 saveTempImage 内部确保图片已被缩放（例如长边不超过 1024），
        // 否则 Qwen2VL 处理 4K 图片会非常慢。
        guard let tempURL = saveTempImage(image: image, identifier: photo.identifier) else {
            NSLog("❌ Failed to save temp image")
            return nil
        }
        
        let fileManager = FileManager.default
        defer {
            try? fileManager.removeItem(at: tempURL)
        }
        
        do {
            // --- 优化点：增强 Prompt ---
            let analysisPrompt = """
            请仔细观察这张照片，提取 3-5 个能够描述画面内容的关键词或短语。
            
            要求：
            1. 语言：必须使用简体中文。
            2. 内容：包含场景（如“海边日落”）、物体（如“咖啡”）、动作（如“奔跑”）或氛围（如“温馨”）。
            3. 格式：仅返回关键词，用逗号分隔。不要包含序号、句号或其他解释性文字。
            
            示例输出：
            海滩, 夕阳, 奔跑的狗, 惬意
            """
            
            // 5. 创建消息
            // 注意：确保 Message 的 init 方法能正确处理本地文件 URL
            let userMessage = Message(role: .user, content: analysisPrompt, images: [tempURL])
            
            // 优化 System Prompt，赋予角色感
            let systemMessage = Message(
                role: .system,
                content: "你是一个精准的视觉分析助手，擅长捕捉图片中的关键元素和情感氛围。"
            )
            
            NSLog("🚀 Starting VLM generation...")
            
            var response = ""
            // 6. 流式获取结果
            let stream = try await mlxService.generate(messages: [systemMessage, userMessage], model: vlm)
            
            for try await token in stream {
                response += token.chunk ?? ""
            }
            
            NSLog("📝 Raw VLM response: \(response)")
            
            // 7. 解析关键词
            let keywords = parseKeywords(from: response)
            
            if keywords.isEmpty {
                NSLog("⚠️ Parsed keywords are empty")
            } else {
                NSLog("✅ Final keywords: \(keywords)")
            }
            
            return keywords
            
        } catch {
            NSLog("❌ VLM analysis error: \(error)")
            return nil
        }
    }
    
    // MARK: - 加载图片
    
    private func loadImage(from photo: PhotoData) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // 跳过低质量预览图，等待最终图片
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // MARK: - 保存临时图片 (VLM兼容格式)
    
    private func saveTempImage(image: UIImage, identifier: String) -> URL? {
        // 使用Application Support目录
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vlmImagesDir = appSupport.appendingPathComponent("VLMImages", isDirectory: true)
        
        // 创建目录
        try? fileManager.createDirectory(at: vlmImagesDir, withIntermediateDirectories: true)
        
        // 使用PNG格式
        let fileName = "vlm_photo_\(identifier.prefix(20)).png"
        let fileURL = vlmImagesDir.appendingPathComponent(fileName)
        
        // 将UIImage转换为PNG数据并保存
        guard let pngData = image.pngData() else {
            NSLog("Failed to convert image to PNG data")
            return nil
        }
        
        do {
            try pngData.write(to: fileURL, options: .atomic)
            NSLog("Saved PNG image: \(fileURL.path), size: \(pngData.count) bytes")
            return fileURL
        } catch {
            NSLog("Failed to write PNG: \(error)")
            return nil
        }
    }
    
    // MARK: - 清理VLM图片缓存
    
    private func cleanupVLMImages() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vlmImagesDir = appSupport.appendingPathComponent("VLMImages", isDirectory: true)
        
        // 删除24小时前的文件
        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60)
        
        if let files = try? fileManager.contentsOfDirectory(at: vlmImagesDir, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files {
                if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
    
    // MARK: - 解析关键词
    
    private func parseKeywords(from response: String) -> [String] {
        // 1. 去除常见的废话前缀
        var cleaned = response
            .replacingOccurrences(of: "关键词：", with: "")
            .replacingOccurrences(of: "Keywords:", with: "")
            .replacingOccurrences(of: "```", with: "") // 防止模型输出 markdown
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 2. 按逗号或换行符分割
        let separators = CharacterSet(charactersIn: ",，\n")
        let rawKeywords = cleaned.components(separatedBy: separators)
        
        // 3. 清洗每个关键词并过滤空值
        let result = rawKeywords.compactMap { keyword -> String? in
            let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "^[0-9]+[.、]", with: "", options: .regularExpression) // 去除 "1." "2、"
            return k.isEmpty ? nil : k
        }
        
        // 4. 去重并限制数量
        return Array(Set(result)).prefix(5).map { String($0) }
    }
    
    // MARK: - 构建消息
    
    private func buildMessages(
        date: Date,
        events: [EventData],
        photoKeywords: [String],
        locations: [LocationData]
    ) -> (Message, Message) {
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy年MM月dd日"
        let dateString = dateFormatter.string(from: date)
        
        NSLog("🔨 Build LLM request message for \(dateString)")
        
        // 1. 构建文本上下文 (Context)
        // 对于多模态模型，文本部分应作为“背景信息”提供，而不是全部依据
        var contextBuilder = ""
        
        // 位置信息
        if !locations.isEmpty {
            let locNames = locations.prefix(3).compactMap { $0.name }.joined(separator: "、")
            contextBuilder += "📍 所在位置：\(locNames)\n"
        }
        
        // 日历事件
        if !events.isEmpty {
            let eventTitles = events.prefix(3).map { $0.title }.joined(separator: "、")
            contextBuilder += "📅 日程安排：\(eventTitles)\n"
        }
        
        // 关键词 (作为视觉辅助，防止模型识别错误)
        if !photoKeywords.isEmpty {
            let topKeywords = photoKeywords.prefix(8).joined(separator: "、")
            contextBuilder += "🏷️ 画面元素提示：\(topKeywords)\n"
        }
        
        // 2. 构建核心 Prompt
        let prompt = """
        今天是 \(dateString)。请结合**用户提供的图片画面**以及下方的**文本上下文**，写一篇温暖的“回忆日记”。

        ### 文本上下文：
        \(contextBuilder)

        ### 任务要求：
        1. **视觉优先**：仔细观察图片，描述画面中的光影、人物表情、动作或氛围（例如：阳光洒在脸上的温暖、朋友大笑的瞬间）。
        2. **情境融合**：利用文本上下文（地点、日程）来辅助理解图片内容。例如，如果图片是食物且日程是“加班”，请描述为“加班后的慰藉”。
        3. **语气风格**：使用第一人称（“我”），语气自然、治愈、像是在写手帐或发朋友圈。字数控制在 60-100 字之间。
        4. **严格格式**：直接返回 JSON 字符串，不要包含 markdown 标记（如 ```json ... ```）。

        ###使用JSON格式返回：
        {
            "title": "简短且文艺的标题（10字以内）",
            "summary": "日记正文内容（包含对画面的描述和当下的感受）",
            "mood": "开心/平静/激动/治愈/怀念/平常",
            "category": "旅行/美食/日常/聚会/工作/其他",
            "tags": ["标签1", "标签2", "标签3"]
        }
        """
        
        // 3. 构建 System Message (人设)
        let systemMessage = Message(
            role: .system,
            content: "你是一个拥有敏锐观察力的多模态生活记录助手。你擅长通过图片细节捕捉情绪，并结合环境信息，用细腻、温暖的文字为用户定格美好瞬间。"
        )
        
        // 4. 构建 User Message
        // 注意：在实际调用 Qwen2VL 时，请务必在 userMessage 的 content 数组中加入图片数据 (Data 或 URL)
        let userMessage = Message(role: .user, content: prompt)
        
        return (systemMessage, userMessage)
    }
    
    // MARK: - 调用 MLX (LLM)
    
    private func callMLX(messages: [Message]) async throws -> String {
        // 获取选中的模型，默认使用第一个LLM模型
        let selectedModelName = UserDefaults.standard.string(forKey: "MLXModelName") ?? MLXService.availableModels.first(where: { $0.type == .llm })?.name ?? "qwen3:1.7b"
        NSLog("callMLX Selected model name: \(selectedModelName)")
        
        guard let model = MLXService.availableModels.first(where: { $0.name == selectedModelName }) else {
            throw AIError.modelNotFound
        }
        
        var fullResponse = ""
        let stream = try await mlxService.generate(messages: messages, model: model)
        
        for try await token in stream {
            fullResponse += token.chunk ?? ""
        }
        
        NSLog("LLM response: \(fullResponse.prefix(200))...")
        return fullResponse
    }
    
    // MARK: - 解析结果
    
    private func parseMemoryResponse(
        _ response: String,
        date: Date,
        events: [EventData],
        photos: [PhotoData],
        locations: [LocationData],
        photoKeywords: [String]
    ) -> HeartBeatMemory {
        
        // 清理响应，提取JSON
        var cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 安全地提取JSON
        if let jsonStart = cleanedResponse.firstIndex(of: "{"),
           let jsonEnd = cleanedResponse.lastIndex(of: "}") {
            // 确保start在end之前
            if jsonStart < jsonEnd {
                NSLog("cleanedResponse length: \(cleanedResponse.count), jsonStart:\(jsonStart), jsonEnd:\(jsonEnd)")
                cleanedResponse = String(cleanedResponse[jsonStart...jsonEnd])
            }
        }
        
        // 移除可能的markdown代码块标记
        cleanedResponse = cleanedResponse
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        NSLog("Parsing response JSON: \(cleanedResponse)")
        
        guard let data = cleanedResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("Failed to parse JSON, using raw response")
            return HeartBeatMemory(
                date: date,
                title: "这一天",
                summary: response,
                mood: .neutral,
                category: .daily,
                aiTags: photoKeywords
            )
        }
        
        let title = json["title"] as? String ?? "这一天"
        let summary = json["summary"] as? String ?? ""
        let moodString = json["mood"] as? String ?? "平常"
        let categoryString = json["category"] as? String ?? "日常"
        let tags = json["tags"] as? [String] ?? []
        
        // 合并photoKeywords和AI生成的tags
        let allTags = Array(Set(tags + photoKeywords.prefix(10)))
        
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
            aiTags: Array(allTags.prefix(10))
        )
    }
}

// MARK: - 错误类型

enum AIError: Error {
    case modelNotFound
    case invalidResponse
    case generationFailed
    case photoLoadFailed
}
