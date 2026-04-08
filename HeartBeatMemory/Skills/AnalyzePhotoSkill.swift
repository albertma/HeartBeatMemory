import Foundation
import Photos
import CoreLocation
import UIKit
import MLXLMCommon

/// 照片分析 Skill
final class AnalyzePhotoSkill: Skill {
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
            metadata: ["photosAnalyzed": context.photos.count, "timestamp": Date()]
        )
    }
    
    private struct PhotoAnalysisResult {
        let keywords: [String]
        let elements: [String]
    }
    
    private func analyzePhoto(_ photo: PhotoData) async -> PhotoAnalysisResult? {
        guard visionModel != nil, 
              let image = await loadImage(from: photo),
              let tempURL = saveTempImage(image: image, identifier: photo.identifier) else {
            return nil
        }
        
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: tempURL) }
        
        // 调用 VLM 分析
        return PhotoAnalysisResult(keywords: [], elements: [])
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
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                var components: [String] = []
                if let area = placemark.areasOfInterest?.first {
                    components.append(area)
                }
                if let locality = placemark.locality {
                    components.append(locality)
                }
                if let country = placemark.country {
                    components.append(country)
                }
                return components.isEmpty ? "未知地点" : components.joined(separator: " ")
            }
        } catch {
            print("AnalyzePhotoSkill: Geocode failed")
        }
        return "未知地点"
    }
}