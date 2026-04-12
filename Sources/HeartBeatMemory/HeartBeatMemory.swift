// HeartBeatMemory - Download Manager for iOS/macOS
//
// Features:
// 1. .tmp files indicate incomplete downloads, automatically deleted on startup
// 2. Can pause/stop downloads, stop deletes partial files
// 3. Can delete any completed file from the list

@main
struct HeartBeatMemory {
    static func main() {
        // 初始化下载管理器（会自动清理.tmp文件）
        let manager = DownloadManager.shared
        print("HeartBeatMemory 下载管理器已初始化")
        
        // 示例：开始下载
        // manager.startDownload(from: URL(string: "https://example.com/file.zip")!)
        
        // 示例：列出已下载文件
        // for file in manager.listCompleted() {
        //     print("\(file.fileName) - \(file.sizeFormatted)")
        // }
    }
}
