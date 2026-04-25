import SwiftUI
import UIKit
import SwiftData
import PhotosUI

struct TimelineView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingPermissionAlert: Bool = false
    @State private var permissionAlertMessage: String = ""
    @State private var selectedMemory: HeartBeatMemory?
    @State private var lastGeneratedDate: Date? = nil  // 防止重复触发
    @State private var showLoadMore: Bool = false  // 是否显示加载更多
    @State private var footerID: UUID = UUID()  // 用于滚动到底部检测
    @State private var showCalendarPicker: Bool = false
    @State private var photoDates: [Date] = []  // 有照片的日期列表
    @State private var memoryDates: Set<Date> = []  // 已有memory的日期集合
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // 空状态
                    if appState.memories.isEmpty && !appState.isProcessing {
                        EmptyStateView()
                    }
                    
                    ForEach(sortedMemories) { memory in
                        MemoryCard(hbMemory: memory)
                            .onTapGesture {
                                selectedMemory = memory
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deleteMemory(memory)
                                } label: {
                                    Label(LocalizedStringKey("delete"), systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    appState.deleteMemory(memory)
                                } label: {
                                    Label(LocalizedStringKey("delete"), systemImage: "trash")
                                }
                            }
                    }
                    
                    // 加载更多 - 滚动到底部时显示
                    if showLoadMore {
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text(LocalizedStringKey("pull_to_load_more"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                    } else if appState.isProcessing {
                        HStack {
                            ProgressView()
                            Text(LocalizedStringKey("generating_memory"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                    
                    // 用于检测滚动到底部的 invisible footer
                    Color.clear
                        .frame(height: 1)
                        .id("footer")
                        .onAppear {
                            NSLog("Footer appeared - at bottom!")
                            checkLoadMore()
                        }
                }
                .padding()
            }
            .onAppear {
                loadPendingIfNeeded()
            }
            .navigationTitle(LocalizedStringKey("timeline"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await loadCalendarData()
                        }
                        showCalendarPicker = true
                    }) {
                        if appState.isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "wand.and.stars")
                        }
                    }
                    .disabled(appState.isProcessing)
                }
            }
            .sheet(isPresented: $showCalendarPicker) {
                CalendarPickerView(
                    photoDates: photoDates,
                    memoryDates: memoryDates,
                    onDateSelected: { selectedDate in
                        handleDateSelection(selectedDate)
                    }
                )
            }
            .alert("权限请求", isPresented: $showingPermissionAlert) {
                Button("确定") { }
            } message: {
                Text(permissionAlertMessage)
            }
            .alert("覆盖回忆", isPresented: $showOverwriteAlert) {
                Button("取消", role: .cancel) {
                    overwriteDate = nil
                }
                Button("覆盖", role: .destructive) {
                    if let date = overwriteDate {
                        generateMemoryForDate(date)
                    }
                    overwriteDate = nil
                }
            } message: {
                Text("该日期已有回忆覆盖生成吗？\n\n点击覆盖将删除原回忆并生成新的回忆。")
            }
            .sheet(item: $selectedMemory) { memory in
                MemoryDetailView(memory: memory)
            }
        }
    }
    
    func generateTodayMemory() {
        Task {
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
    
    // 加载日历数据（照片日期和已有memory的日期）
    func loadCalendarData() async {
        let dates = await DataService.shared.fetchPhotoDatesInLast30Days()
        let memoriesDaySet = Set(appState.memories.map { Calendar.current.startOfDay(for: $0.date) })
        
        await MainActor.run {
            photoDates = dates
            memoryDates = memoriesDaySet
        }
    }
    
    // 处理日期选择
    func handleDateSelection(_ date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let existingMemory = appState.memories.first { Calendar.current.startOfDay(for: $0.date) == startOfDay }
        
        if let existingMemory = existingMemory {
            // 已有memory，显示覆盖确认对话框
            showOverwriteAlert(date: date, existingMemory: existingMemory)
        } else {
            // 没有memory，直接生成
            generateMemoryForDate(date)
        }
    }
    
    // 显示覆盖确认对话框
    @State private var showOverwriteAlert: Bool = false
    @State private var overwriteDate: Date?
    
    private func showOverwriteAlert(date: Date, existingMemory: HeartBeatMemory) {
        overwriteDate = date
        showOverwriteAlert = true
    }
    
    // 生成指定日期的memory（会覆盖已有）
    private func generateMemoryForDate(_ date: Date) {
        Task {
            let authorized = await DataService.shared.requestAllPermissions()
            
            if authorized {
                // 如果已有memory，先删除
                let startOfDay = Calendar.current.startOfDay(for: date)
                if let existing = appState.memories.first(where: { Calendar.current.startOfDay(for: $0.date) == startOfDay }) {
                    appState.deleteMemory(existing)
                }
                
                await appState.generateMemory(for: date)
            } else {
                await MainActor.run {
                    permissionAlertMessage = "需要访问日历、照片等权限来生成回忆。请在设置中开启权限。"
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    // 排序后的回忆列表
    private var sortedMemories: [HeartBeatMemory] {
        appState.memories.sorted(by: { $0.date > $1.date })
    }
    
    // 加载待生成日期
    private func loadPendingIfNeeded() {
        NSLog("loadPendingIfNeeded")
        Task {
            let authorized = await DataService.shared.requestAllPermissions()
            if authorized {
                await appState.loadPendingPhotoDates()
                NSLog("Pending dates loaded: \(appState.pendingPhotoDates.count)")
            }
        }
    }
    
    // 检查是否需要加载更多
    private func checkLoadMore() {
        NSLog("checkLoadMore called - pending: \(appState.pendingPhotoDates.count), processing: \(appState.isProcessing)")
        
        guard !appState.isProcessing && !appState.pendingPhotoDates.isEmpty else {
            showLoadMore = false
            return
        }
        
        // 防止重复触发
        if let nextDate = appState.pendingPhotoDates.first {
            if lastGeneratedDate != nextDate {
                NSLog("Loading more - next date: \(nextDate)")
                showLoadMore = true
                lastGeneratedDate = nextDate
                Task {
                    await appState.generateNextPendingMemory()
                }
            }
        }
    }
}

// MARK: - Preference Keys (保留但不使用)

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            VStack(spacing: 8) {
                Text(LocalizedStringKey("no_memories_yet"))
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text(LocalizedStringKey("tap_wand_to_generate"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Text(LocalizedStringKey("ai_will_analyze"))
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
                    Text(formatDate(hbMemory.date))
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
            
            // 标签
            if !hbMemory.aiTags.isEmpty {
                FlowLayout(spacing: 8, lineSpacing: 6) {
                    ForEach(Array(hbMemory.aiTags.enumerated()), id: \.offset) { index, tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            
            // Show data sources if available
            HStack(spacing: 16) {
                if !hbMemory.events.isEmpty {
                    Label("\(hbMemory.events.count) " + NSLocalizedString("events", comment: ""), systemImage: "calendar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !hbMemory.photos.isEmpty {
                    Label("\(hbMemory.photos.count) " + NSLocalizedString("photos", comment: ""), systemImage: "photo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !hbMemory.locations.isEmpty {
                    Label(LocalizedStringKey("location"), systemImage: "location")
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteAlert = false
    @State private var showShareSheet = false
    @State private var capturedImage: UIImage? = nil
    @State private var isCapturing = false
    
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
                    
                    // App Branding
                    appBrandingSection
                }
                .padding()
            }
            .navigationTitle("回忆详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        captureAndShare()
                    } label: {
                        if isCapturing {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isCapturing)
                }
            }
            .alert(LocalizedStringKey("delete_memory"), isPresented: $showDeleteAlert) {
                Button(LocalizedStringKey("cancel"), role: .cancel) {}
                Button(LocalizedStringKey("delete"), role: .destructive) {
                    deleteMemory()
                }
            } message: {
                Text(LocalizedStringKey("confirm_delete_memory"))
            }
            .sheet(isPresented: $showShareSheet) {
                if let image = capturedImage {
                    ShareSheet(items: [image])
                }
            }
        }
    }
    
    // MARK: - Delete Action
    
    private func deleteMemory() {
        appState.deleteMemory(memory)
        dismiss()
    }
    
    // MARK: - Capture & Share
    
    private func captureAndShare() {
        isCapturing = true
        
        // 延迟一下确保视图渲染完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.captureScreenshot()
            self.isCapturing = false
            self.showShareSheet = true
        }
    }
    
    private func captureScreenshot() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        capturedImage = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
    
    // MARK: - App Branding Section
    
    private var appBrandingSection: some View {
        VStack(spacing: 8) {
            Divider()
            
            Text(LocalizedStringKey("memory_from_app"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(LocalizedStringKey("record_moments_with_ai"))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Link(destination: URL(string: "https://apps.apple.com/app/idXXXXXXXXX")!) {
                Text(LocalizedStringKey("app_store_link"))
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
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
                    Text(formatDate(memory.date))
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
                Label(LocalizedStringKey("photos"), systemImage: "photo.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                Spacer()
                Text("\(memory.photos.count)")
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
                Label(LocalizedStringKey("calendar_events"), systemImage: "calendar")
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                Text("\(memory.events.count)")
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
            Label(LocalizedStringKey("ai_tags"), systemImage: "tag.fill")
                .font(.headline)
                .foregroundColor(.orange)

            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(memory.aiTags.enumerated()), id: \.offset) { index, tag in
                    Text("#\(tag)")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(16)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
            // MARK: - Date Formatting

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

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
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
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


// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Custom Calendar Picker View

struct CalendarPickerView: View {
    let photoDates: [Date]
    let memoryDates: Set<Date>
    let onDateSelected: (Date) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedMonth: Date = Date()
    @State private var selectedDate: Date?
    
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月份选择
                HStack {
                    Button(action: {
                        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Text(monthYearString)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: {
                        if canGoToNextMonth {
                            selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .foregroundColor(canGoToNextMonth ? .blue : .gray)
                    }
                    .disabled(!canGoToNextMonth)
                }
                .padding()
                
                // 星期标题
                HStack {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                
                // 日历网格
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(daysInMonth(), id: \.self) { date in
                        if let date = date {
                            CalendarDayCell(
                                date: date,
                                isCurrentMonth: isInCurrentMonth(date),
                                hasPhoto: hasPhoto(on: date),
                                hasMemory: hasMemory(on: date),
                                isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                                isToday: calendar.isDateInToday(date),
                                onTap: {
                                    if hasPhoto(on: date) {
                                        selectedDate = date
                                        onDateSelected(date)
                                        dismiss()
                                    }
                                }
                            )
                        } else {
                            Color.clear
                                .frame(height: 44)
                        }
                    }
                }
                .padding()
                
                // 图例
                HStack(spacing: 20) {
                    LegendItem(color: .green, text: "有照片（可生成）")
                    LegendItem(color: .orange, text: "已有回忆")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                
                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: selectedMonth)
    }
    
    private var canGoToNextMonth: Bool {
        let now = Date()
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
        return calendar.compare(nextMonth, to: now, toGranularity: .month) != .orderedDescending
    }
    
    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: selectedMonth, toGranularity: .month)
    }
    
    private func hasPhoto(on date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return photoDates.contains { calendar.isDate($0, inSameDayAs: startOfDay) }
    }
    
    private func hasMemory(on date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        return memoryDates.contains { calendar.isDate($0, inSameDayAs: startOfDay) }
    }
    
    private func daysInMonth() -> [Date?] {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth))!
        let range = calendar.range(of: .day, in: .month, for: selectedMonth)!
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        for day in 1..<range.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let hasPhoto: Bool
    let hasMemory: Bool
    let isSelected: Bool
    let isToday: Bool
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(textColor)
                
                // 状态指示点
                HStack(spacing: 2) {
                    if hasMemory {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    } else if hasPhoto {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .disabled(!hasPhoto)
    }
    
    private var textColor: Color {
        if !isCurrentMonth {
            return .gray
        }
        if isSelected {
            return .white
        }
        if !hasPhoto {
            return .gray
        }
        return .primary
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return .blue
        }
        if hasMemory {
            return .orange.opacity(0.1)
        }
        if hasPhoto {
            return .green.opacity(0.1)
        }
        return .clear
    }
}

// MARK: - Legend Item

struct LegendItem: View {
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
