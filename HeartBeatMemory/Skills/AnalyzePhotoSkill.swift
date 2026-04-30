import Foundation
import MLXLMCommon
import Photos
import UIKit
import ImageIO
import CoreLocation
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
                    print("Location: \(locationName)")
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
        
        guard let image = await loadImage(from: photo) else {
            return nil
        }
        
        guard let tempURL = saveTempImage(image: image, identifier: photo.identifier) else {
            return nil
        }
        
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: tempURL) }
        
        let language = UserDefaults.standard.string(forKey: "language") ?? "zh"
        let prompts = language == "en" ? (
            user: """
            Analyze this image and extract 3-5 keywords.
            Must include: scene, objects, action, atmosphere.
            Only output keywords, separated by commas, nothing else.
            """,
            system: "You only output image keywords. No explanation, no sentences, no extra text."
        ) : (
            user: """
            观察图片，提取3-5个关键词。
            必须包含：场景、物体、动作、氛围。
            仅输出关键词，用逗号分隔，无其他文字。
            """,
            system: "你只输出图片关键词，不解释，不造句，不输出多余内容。"
        )
        
        let systemMessage = Message(role: .system, content: prompts.system)
        let userMessage = Message(role: .user, content: prompts.user, images: [tempURL])

        var fullResponse = ""
        do {
            let stream = try await mlxService.generate(messages: [systemMessage, userMessage], model: model)
            for try await token in stream {
                fullResponse += token.chunk ?? ""
            }
        } catch {
            print("AnalyzePhotoSkill: MLX generate failed - \(error)")
        }
        
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
                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
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
        // 中国的经纬度需要从 WGS-84 → GCJ-02 转换后再进行逆地理编码
        let wgsCoord = Coordinate(lat: latitude, lng: longitude, type: .wgs84)
        let gcjCoord = CoordTransform.wgs84ToGcj02(wgsCoord)
        let coordinate = CLLocationCoordinate2D(latitude: gcjCoord.lat, longitude: gcjCoord.lng)
        
//        for radius in [50.0, 300.0, 800.0] {
//            if let result = await searchWithMapKit(coordinate: coordinate, radius: radius) {
//                return result
//            }
//        }
        
        return await reverseGeocodeFallback(latitude: gcjCoord.lat, longitude: gcjCoord.lng)
    }
    
    private func searchWithMapKit(coordinate: CLLocationCoordinate2D, radius: Double) async -> String? {
        print("Search with mapkit")
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
                
                if let name = item.name, !name.isEmpty {
                    components.append(name)
                }
                
                let placemark = item.placemark
                if let administrativeArea = placemark.administrativeArea {
                    components.append(administrativeArea)
                }
                if let locality = placemark.locality {
                    if !components.contains(locality) {
                        components.append(locality)
                    }
                }
                if let subLocality = placemark.subLocality {
                    components.append(subLocality)
                }
                
                if !components.isEmpty {
                    return components.joined(separator: "")
                }
            }
        } catch {
            print("AnalyzePhotoSkill: MKLocalSearch failed - \(error)")
        }
        
        return nil
    }
    
    private func reverseGeocodeFallback(latitude: Double, longitude: Double) async -> String {
        print("Run RGC fallback")
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            if let placemark = placemarks.first {
                var components: [String] = []
                if let aOI = placemark.areasOfInterest{
                    if !aOI.isEmpty{
                        components.append(aOI[0])
                    }
                }
                if let administrativeArea = placemark.administrativeArea {
                    components.append(administrativeArea)
                }
                if let locality = placemark.locality {
                    if !components.contains(locality) {
                        components.append(locality)
                    }
                }
                if let subLocality = placemark.subLocality {
                    components.append(subLocality)
                }
                
                if !components.isEmpty {
                    return components.joined(separator: "")
                }
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
