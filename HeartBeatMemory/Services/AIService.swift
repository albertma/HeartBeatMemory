import Foundation
import MLXLMCommon
import Photos
import UIKit
import ImageIO

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
        
        // 1. 先用VLM分析每张照片，提取关键词
        var photoKeywords: [String] = []
        for photo in photos.prefix(20) {  // 限制最多20张照片
            if let keywords = await analyzePhoto(photo) {
                photoKeywords.append(contentsOf: keywords)
            }
        }
        
        NSLog("Photo keywords extracted: \(photoKeywords)")
        
        if photoKeywords.count > 5{
            photoKeywords = Array(photoKeywords.prefix(5))
        }
        // 2. 构建包含照片关键词的prompt
        let (systemMessage, userMessage) = buildMessages(
            date: date,
            events: events,
            photoKeywords: photoKeywords,
            locations: locations
        )
        
        // 3. 使用LLM生成回忆
        let response = try await callMLX(messages: [systemMessage, userMessage])
        
        return parseMemoryResponse(response, date: date, events: events, photos: photos, locations: locations, photoKeywords: photoKeywords)
    }
    
    // MARK: - 分析单张照片
    
    private func analyzePhoto(_ photo: PhotoData) async -> [String]? {
        NSLog("Start to analyzePhoto")
        
        // 确保清理旧的VLM图片
        cleanupVLMImages()
        
        // 加载图片
        guard let image = await loadImage(from: photo) else {
            NSLog("Failed to load image for photo: \(photo.identifier)")
            return nil
        }
        NSLog("Image loaded successfully, size: \(image.size)")
        
        // 检查VLM模型
        guard let vlm = visionModel else {
            NSLog("No VLM model available for photo analysis")
            return nil
        }
        NSLog("vlm model: \(vlm.name)")
        
        // 保存图片到临时文件
        guard let tempURL = saveTempImage(image: image, identifier: photo.identifier) else {
            NSLog("Failed to save image for VLM analysis")
            return nil
        }
        
        // 验证文件存在
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: tempURL.path) else {
            NSLog("Temp file does not exist: \(tempURL.path)")
            return nil
        }
        
        // 检查文件大小
        if let attributes = try? fileManager.attributesOfItem(atPath: tempURL.path),
           let fileSize = attributes[.size] as? Int64 {
            NSLog("Saved image size: \(fileSize) bytes")
            if fileSize < 1000 {
                NSLog("Warning: Image file too small, may be corrupted")
            }
        }
        
        defer {
            // 清理临时文件
            try? fileManager.removeItem(at: tempURL)
        }
        
        // 重要：对于安全范围内的URL，需要访问资源
        // 但Application Support目录不需要安全访问，所以注释掉
        // tempURL.startAccessingSecurityScopedResource()
        // defer { tempURL.stopAccessingSecurityScopedResource() }
        
        do {
            // 构建图像分析prompt
            let analysisPrompt = """
            分析这张图片，提取3-5个关键词描述照片中的内容。
            关键词应该包括：场景、活动、物品、人物、情感等。
            只返回关键词，用逗号分隔，不要其他内容。
            """
            
            // 创建消息，包含图片URL
            let userMessage = Message(role: .user, content: analysisPrompt, images: [tempURL])
            let systemMessage = Message(role: .system, content: "你是一个专业的图像分析助手，可以准确描述照片内容并提取关键信息。")
            
            NSLog("Starting VLM analysis with image URL: \(tempURL.path)")
            NSLog("Image URL absoluteString: \(tempURL.absoluteString)")
            
            var response = ""
            let stream = try await mlxService.generate(messages: [systemMessage, userMessage], model: vlm)
            
            for try await token in stream {
                response += token.chunk ?? ""
            }
            
            NSLog("VLM response: \(response.prefix(200))")
            
            // 解析关键词
            let keywords = parseKeywords(from: response)
            NSLog("Photo analysis keywords: \(keywords)")
            
            return keywords
        
        } catch {
            NSLog("Photo analysis failed: \(error)")
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
        // 清理响应，去除换行和多余空格
        let cleaned = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: ",")
        
        // 按逗号分割
        let keywords = cleaned.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        // 去重并限制数量
        var uniqueKeywords: [String] = []
        for keyword in keywords {
            if !uniqueKeywords.contains(keyword) && uniqueKeywords.count < 20 {
                uniqueKeywords.append(keyword)
            }
        }
        
        return uniqueKeywords
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
        NSLog("Build LLM request message for \(dateString)")
        
        var prompt = """
        请分析以下数据，为 \(dateString) 生成一条温暖的"回忆日记"。
        
        要求：
        1. 生成一个简短有感的标题（10字内）
        2. 用2-3句话根据下面的数据，总结当天的美好瞬间
        3. 判断心情类型：开心/难过/激动/平静/感恩/怀念/平常
        4. 分类：旅行/家庭/工作/朋友/爱好/美食/里程碑/日常/其他
        5. 提取3-5个关键词标签
        
        数据：
        """
        
        if !events.isEmpty {
            prompt += "\n 日历事件：\n"
            for event in events.prefix(10) {
                prompt += "- \(event.title)"
                if let loc = event.location { prompt += " @\(loc)" }
                if let notes = event.notes, !notes.isEmpty { prompt += ": \(notes)" }
                prompt += "\n"
            }
        }
        
        if !locations.isEmpty {
            prompt += "\n 位置：\n"
            for loc in locations.prefix(5) {
                if !loc.name.isEmpty {
                    prompt += "- \(loc.name)\n"
                }
            }
        }
        
        if !photoKeywords.isEmpty {
            prompt += "\n 照片内容关键词：\n"
            // 按5个一组显示，便于阅读
            let groupedKeywords = stride(from: 0, to: min(photoKeywords.count, 25), by: 5).map {
                photoKeywords[$0..<min($0 + 5, photoKeywords.count)].joined(separator: "、")
            }
            for group in groupedKeywords {
                prompt += "- \(group)\n"
            }
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
        NSLog("prompt: \(prompt)")
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
        
        NSLog("Parsing response JSON: \(cleanedResponse.prefix(200))")
        
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
