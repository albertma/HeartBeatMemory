import Foundation
import EventKit
import Photos
import CoreLocation
import Combine

/// 数据服务 - 整合所有数据源
class DataService: ObservableObject {
    static let shared = DataService()
    
    private let eventStore = EKEventStore()
    private let locationManager = CLLocationManager()
    
    @Published var isAuthorized: Bool = false
    
    // MARK: - 权限请求
    
    func requestAllPermissions() async -> Bool {
        var results: [Bool] = []
        
        // 日历
        if #available(iOS 17.0, *) {
            let calendarStatus = EKEventStore.authorizationStatus(for: .event)
            if calendarStatus == .notDetermined {
                do {
                    try await eventStore.requestFullAccessToEvents()
                    results.append(true)
                } catch {
                    results.append(false)
                }
            }
        }
        
        // 照片
        let photoStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photoStatus == .notDetermined {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            results.append(status == .authorized)
        }
        
        // 位置
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        
        // 提醒 (iOS 17+)
        if #available(iOS 17.0, *) {
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            if reminderStatus == .notDetermined {
                do {
                    try await eventStore.requestFullAccessToReminders()
                    results.append(true)
                } catch {
                    results.append(false)
                }
            }
        }
        
        return results.allSatisfy { $0 }
    }
    
    // MARK: - 获取数据
    
    /// 获取日历事件
    func fetchCalendarEvents(from startDate: Date, to endDate: Date) async -> [EventData] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        return events.map { event in
            EventData(
                identifier: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "无标题",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                notes: event.notes
            )
        }
    }
    
    /// 获取提醒
    func fetchReminders(completion: @escaping ([EKReminder]) -> Void) {
        let predicate = eventStore.predicateForReminders(in: nil)
        eventStore.fetchReminders(matching: predicate) { reminders in
            completion(reminders ?? [])
        }
    }
    
    /// 获取照片
    func fetchPhotos(from startDate: Date, to endDate: Date) async -> [PhotoData] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            startDate as NSDate,
            endDate as NSDate
        )
        
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var photos: [PhotoData] = []
        
        assets.enumerateObjects { asset, _, _ in
            var location: LocationData?
            if let loc = asset.location {
                location = LocationData(
                    name: "",
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude,
                    timestamp: asset.creationDate
                )
            }
            
            photos.append(PhotoData(
                identifier: asset.localIdentifier,
                creationDate: asset.creationDate,
                location: location
            ))
        }
        
        return photos
    }
    
    /// 获取位置历史
    func fetchLocationHistory(from startDate: Date, to endDate: Date) -> [CLLocation] {
        return []
    }
}
