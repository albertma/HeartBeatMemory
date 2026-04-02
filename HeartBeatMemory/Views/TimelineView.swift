import SwiftUI
import PhotosUI

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingPermissionAlert: Bool = false
    @State private var permissionAlertMessage: String = ""
    @State private var selectedMemory: HeartBeatMemory?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if appState.memories.isEmpty {
                    EmptyStateView()
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(appState.memories.sorted(by: { $0.date > $1.date })) { memory in
                            MemoryCard(hbMemory: memory)
                                .onTapGesture {
                                    selectedMemory = memory
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        appState.deleteMemory(memory)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        appState.deleteMemory(memory)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(LocalizedStringKey("timeline"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: generateTodayMemory) {
                        if appState.isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .disabled(appState.isProcessing)
                }
            }
            .alert("权限请求", isPresented: $showingPermissionAlert) {
                Button("确定") { }
            } message: {
                Text(permissionAlertMessage)
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
        }
    }
    
    func generateTodayMemory() {
        Task {
            // Request permissions first
            let authorized = await DataService.shared.requestAllPermissions()
            
            if authorized {
                await appState.generateMemory(for: Date())
            } else {
                await MainActor.run {
                    permissionAlertMessage = "需要访问日历、照片等权限来生成回忆。请在设置中开启权限。"
                    showingPermissionAlert = true
                }
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("还没有回忆")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("点击右上角的魔杖按钮，让AI帮你生成今天的回忆")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Text("AI会分析你的日历、照片和位置，生成温暖的回忆")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .padding(.top, 100)
    }
}

// MARK: - Memory Card

struct MemoryCard: View {
    let hbMemory: HeartBeatMemory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(hbMemory.mood.emoji)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text(hbMemory.title)
                        .font(.headline)
                    Text(hbMemory.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(hbMemory.category.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Text(hbMemory.summary)
                .font(.body)
                .lineLimit(3)
            
            // 👇 这里是修复后的整齐标签
            if !hbMemory.aiTags.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    ForEach(hbMemory.aiTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1) // 强制不折行
                    }
                }
            }
            
            // Show data sources if available
            HStack(spacing: 16) {
                if !hbMemory.events.isEmpty {
                    Label("\(hbMemory.events.count)个事件", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !hbMemory.photos.isEmpty {
                    Label("\(hbMemory.photos.count)张照片", systemImage: "photo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !hbMemory.locations.isEmpty {
                    Label("位置", systemImage: "location")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var rows: [CGFloat] = []
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, !currentRowWidth.isZero {
                rows.append(currentRowHeight)
                currentRowWidth = 0
                currentRowHeight = 0
            }
            currentRowWidth += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        rows.append(currentRowHeight)
        let totalHeight = rows.reduce(0) { $0 + $1 } + CGFloat(rows.count - 1) * lineSpacing
        return CGSize(width: maxWidth, height: totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var maxHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += maxHeight + lineSpacing
                maxHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .init(size))
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }
    }
}
// MARK: - Memory Detail View

struct MemoryDetailView: View {
    let memory: HeartBeatMemory
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection
                    
                    // Generated Diary
                    diarySection
                    
                    // Photos
                    if !memory.photos.isEmpty {
                        photosSection
                    }
                    
                    // Calendar Events
                    if !memory.events.isEmpty {
                        calendarSection
                    }
                    
                    // Locations
                    if !memory.locations.isEmpty {
                        locationSection
                    }
                    
                    // Tags
                    if !memory.aiTags.isEmpty {
                        tagsSection
                    }
                }
                .padding()
            }
            .navigationTitle("回忆详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(memory.mood.emoji)
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(memory.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(memory.date, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack {
                Label(memory.mood.rawValue, systemImage: "face.smiling")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(8)
                
                Text(memory.category.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Diary Section
    
    private var diarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("日记内容", systemImage: "book.fill")
                .font(.headline)
                .foregroundColor(.blue)
            
            Text(memory.summary)
                .font(.body)
                .lineSpacing(6)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
        }
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("照片", systemImage: "photo.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                Text("\(memory.photos.count)张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(memory.photos.prefix(20), id: \.identifier) { photo in
                        PhotoThumbnail(photo: photo)
                    }
                }
            }
        }
    }
    
    // MARK: - Calendar Section
    
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("日历事件", systemImage: "calendar")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                Text("\(memory.events.count)个")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ForEach(memory.events, id: \.identifier) { event in
                EventRow(event: event)
            }
        }
    }
    
    // MARK: - Location Section
    
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("位置", systemImage: "location.fill")
                .font(.headline)
                .foregroundColor(.red)
            
            ForEach(memory.locations, id: \.latitude) { location in
                LocationRow(location: location)
            }
        }
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI标签", systemImage: "tag.fill")
                .font(.headline)
                .foregroundColor(.orange)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(memory.aiTags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(16)
                        .foregroundColor(.orange)
                        .lineLimit(1) // 👈 强制不换行，彻底杜绝乱序
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading) // 👈 强制左对齐
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

// MARK: - Supporting Views

struct PhotoThumbnail: View {
    let photo: PhotoData
    @State private var thumbnailImage: UIImage?
    
    var body: some View {
        ZStack {
            if let image = thumbnailImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 100, height: 100)
                    .cornerRadius(8)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    }
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        guard let creationDate = photo.creationDate else { return }
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "creationDate == %@", creationDate as NSDate)
        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        
        if let asset = assets.firstObject {
            let manager = PHImageManager.default()
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.isNetworkAccessAllowed = true
            
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                if let image = image {
                    DispatchQueue.main.async {
                        thumbnailImage = image
                    }
                }
            }
        }
    }
}

struct EventRow: View {
    let event: EventData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            HStack {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(formatDate(event.startDate))
                    .font(.caption)
                if let end = event.endDate {
                    Text("- \(formatTime(end))")
                        .font(.caption)
                }
            }
            .foregroundColor(.secondary)
            
            if let location = event.location {
                HStack {
                    Image(systemName: "mappin")
                        .font(.caption2)
                    Text(location)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct LocationRow: View {
    let location: LocationData
    
    var body: some View {
        HStack {
            Image(systemName: "mappin.circle.fill")
                .font(.title2)
                .foregroundColor(.red)
            
            VStack(alignment: .leading) {
                if !location.name.isEmpty {
                    Text(location.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

