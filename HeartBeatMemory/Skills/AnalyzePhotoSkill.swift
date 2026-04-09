import Foundation
import Photos
import CoreLocation
import UIKit
import MLXLMCommon
import MapKit

/// 照片分析 Skill - 使用 MLX VLM 分析照片
final class AnalyzePhotoSkill: Skill, @unchecked Sendable {
    let id = "analyze_photo"
    let name = "Analyze Photo"
    let description = "VLM 分析照片，提取关键词、位置"
    
    private let mlxService = MLXService()
    
    private var visionModel: LMModel? {
        MLXService.availableModels.first { $0.type == .vlm }
    }
    
    func execute(with context: SkillContext) async throws -> SkillResult {
        var allKeywords: [String] = []
        var allLocations: [LocationData] = []
        var allElements: [String] = []
        
        for photo in context.photos.prefix(20) {
            if let photoLoc = photo.location {
                let exists = allLocations.contains { existing in
                    abs(existing.latitude - photoLoc.latitude) < 0.001 &&
                    abs(existing.longitude - photoLoc.longitude) < 0.001
                }
                if !exists {
                    let locationName = await reverseGeocode(
                        latitude: photoLoc.latitude,
                        longitude: photoLoc.longitude
                    )
                    let namedLocation = LocationData(
                        name: locationName,
                        latitude: photoLoc.latitude,
                        longitude: photoLoc.longitude,
                        timestamp: photoLoc.timestamp
                    )
                    allLocations.append(namedLocation)
                }
            }
            
            if let result = await analyzePhoto(photo) {
                allKeywords.append(contentsOf: result.keywords)
                allElements.append(contentsOf: result.elements)
            }
        }
        
        let uniqueKeywords = Array(Set(allKeywords)).prefix(10).map { $0 }
        let uniqueElements = Array(Set(allElements)).prefix(10).map { $0 }
        
        return SkillResult(
            skillId: id,
            data: .analysis(PhotoAnalysis(
                keywords: Array(uniqueKeywords),
                locations: allLocations,
                elements: Array(uniqueElements)
            )),
            metadata: ["photosAnalyzed": context.photos.count]
        )
    }
    
    private struct PhotoAnalysisResult {
        let keywords: [String]
        let elements: [String]
    }
    
    private func analyzePhoto(_ photo: PhotoData) async -> PhotoAnalysisResult? {
        guard let model = visionModel else {
            print("AnalyzePhotoSkill: No VLM model available")
            return nil
        }
        
        // 加载图片
        guard let image = await loadImage(from: photo) else {
            return nil
        }
        
        // 保存临时图片
        guard let tempURL = saveTempImage(image: image, identifier: photo.identifier) else {
            return nil
        }
        
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: tempURL) }
        
        // 构建 prompt
        let prompt = """
        观察图片，提取3-5个关键词。
        必须包含：场景、物体、动作、氛围。
        仅输出关键词，用逗号分隔，无其他文字。
        """
        
        // 创建消息
        let systemMessage = Message(
            role: .system,
            content: "你只输出图片关键词，不解释，不造句，不输出多余内容。"
        )
        let userMessage = Message(role: .user, content: prompt, images: [tempURL])
        
        // 调用 MLX（自动下载并加载模型）
        var fullResponse = ""
        do {
            let stream = try await mlxService.generate(messages: [systemMessage, userMessage], model: model)
            for try await token in stream {
                fullResponse += token.chunk ?? ""
            }
        } catch {
            print("AnalyzePhotoSkill: MLX generate failed - \(error)")
        }
        
        // 解析关键词
        let keywords = parseKeywords(from: fullResponse)
        let elements = keywords
        
        return PhotoAnalysisResult(keywords: keywords, elements: elements)
    }
    
    private func parseKeywords(from response: String) -> [String] {
        var cleaned = response
            .replacingOccurrences(of: "关键词：", with: "")
            .replacingOccurrences(of: "Keywords:", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let separators = CharacterSet(charactersIn: ",，\n")
        let rawKeywords = cleaned.components(separatedBy: separators)
        
        return rawKeywords.compactMap { keyword -> String? in
            let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            return k.isEmpty ? nil : k
        }.prefix(5).map { $0 }
    }
    
    private func loadImage(from photo: PhotoData) async -> UIImage? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [photo.identifier], options: nil)
        guard let asset = fetchResult.firstObject else { return nil }
        
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1024, height: 1024),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    private func saveTempImage(image: UIImage, identifier: String) -> URL? {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vlmImagesDir = appSupport.appendingPathComponent("VLMImages", isDirectory: true)
        
        try? fileManager.createDirectory(at: vlmImagesDir, withIntermediateDirectories: true)
        
        let fileName = "skill_photo_\(identifier.prefix(20)).png"
        let fileURL = vlmImagesDir.appendingPathComponent(fileName)
        
        guard let pngData = image.pngData() else { return nil }
        
        do {
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
    
    private func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // 尝试 MapKit（加大搜索范围和重试）
        for radius in [2000.0, 5000.0, 10000.0] {
            if let result = await searchWithMapKit(coordinate: coordinate, radius: radius) {
                return result
            }
        }
        
        // Fallback: CLGeocoder
        return await reverseGeocodeFallback(latitude: latitude, longitude: longitude)
    }
    
    private func searchWithMapKit(coordinate: CLLocationCoordinate2D, radius: Double) async -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "地点"
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radius,
            longitudinalMeters: radius
        )
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            
            if let item = response.mapItems.first {
                var components: [String] = []
                
                // POI 名称
                if let name = item.name, !name.isEmpty {
                    components.append(name)
                }
                
                // 使用 MKPlacemark 的详细字段（中国地址格式）
                let placemark = item.placemark
                
                // 省级
                if let administrativeArea = placemark.administrativeArea {
                    components.append(administrativeArea)
                }
                
                // 城市
                if let locality = placemark.locality {
                    if !components.contains(locality) {
                        components.append(locality)
                    }
                }
                
                // 区/县
                if let subLocality = placemark.subLocality {
                    components.append(subLocality)
                }
                
                // 街道
                if let thoroughfare = placemark.thoroughfare {
                    components.append(thoroughfare)
                }
                
                // 门牌号
                if let subThoroughfare = placemark.subThoroughfare {
                    components.append(subThoroughfare)
                }
                
                return components.isEmpty ? nil : components.joined(separator: "")
            }
        } catch {
            print("AnalyzePhotoSkill: MKLocalSearch failed (radius=\(radius)) - \(error)")
        }
        
        return nil
    }
    
    private func reverseGeocodeFallback(latitude: Double, longitude: Double) async -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                var components: [String] = []
                
                // 中国地址格式：省 -> 市 -> 区 -> 街道
                if let administrativeArea = placemark.administrativeArea {  // 省/州
                    components.append(administrativeArea)
                }
                if let locality = placemark.locality {  // 城市
                    if !components.contains(locality) {
                        components.append(locality)
                    }
                }
                if let subLocality = placemark.subLocality {  // 区/县
                    components.append(subLocality)
                }
                if let thoroughfare = placemark.thoroughfare {  // 街道
                    components.append(thoroughfare)
                }
                if let subThoroughfare = placemark.subThoroughfare {  // 门牌号
                    components.append(subThoroughfare)
                }
                
                if components.isEmpty {
                    return formatCoordinate(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }
                return components.joined(separator: "")
            }
        } catch {
            print("AnalyzePhotoSkill: CLGeocoder failed - \(error)")
        }
        
        return formatCoordinate(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        let latDir = coordinate.latitude >= 0 ? "N" : "S"
        let lonDir = coordinate.longitude >= 0 ? "E" : "W"
        return String(format: "%.4f°%@ %.4f°%@", abs(coordinate.latitude), latDir, abs(coordinate.longitude), lonDir)
    }
}
