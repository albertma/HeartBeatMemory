import Foundation
import StoreKit

/// StoreKit 2.0 内购管理器
@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    /// 可用产品
    @Published var products: [Product] = []
    
    /// 已购买产品ID（Non-Consumable 永久拥有，Consumable 需要服务端验证）
    @Published var purchasedIDs: Set<String> = []
    
    /// 购买状态
    @Published var purchaseStatus: PurchaseStatus = .idle
    
    /// 错误信息
    @Published var errorMessage: String?
    
    enum PurchaseStatus {
        case idle
        case purchasing
        case success
        case failed
    }
    
    // MARK: - Product IDs
    #if DEBUG
    // 测试产品ID（需要替换为实际 App Store Connect 中的产品ID）
    private let productIDs = Set(["com.heartbeatmemory.premium", "com.heartbeatmemory.unlock_all"])
    #else
    private let productIDs = Set(["com.heartbeatmemory.premium", "com.heartbeatmemory.unlock_all"])
    #endif
    
    // MARK: - 初始化
    
    private init() {
        Task {
            await loadProducts()
            await updatePurchasedStatus()
        }
    }
    
    // MARK: - 加载产品
    
    func loadProducts() async {
        do {
            // 从 App Store 请求产品信息
            let storeProducts = try await Product.products(for: productIDs)
            
            // 按价格排序
            products = storeProducts.sorted { $0.price < $1.price }
            
            print("StoreManager: Loaded \(products.count) products")
        } catch {
            print("StoreManager: Failed to load products - \(error)")
            errorMessage = "无法加载产品信息: \(error.localizedDescription)"
        }
    }
    
    // MARK: - 更新购买状态
    
    func updatePurchasedStatus() async {
        // 查询已购买的非消耗型产品
        var ids = Set<String>()
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                // 产品未过期
                if transaction.revocationDate == nil {
                    ids.insert(transaction.productID)
                }
            }
        }
        
        purchasedIDs = ids
        print("StoreManager: Purchased IDs: \(purchasedIDs)")
    }
    
    // MARK: - 购买产品
    
    func purchase(_ product: Product) async {
        purchaseStatus = .purchasing
        errorMessage = nil
        
        do {
            // 显示购买对话框
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // 验证交易
                let transaction = try checkVerified(verification)
                
                // 保存购买记录
                await finishTransaction(transaction)
                
                purchaseStatus = .success
                print("StoreManager: Purchase successful!")
                
            case .userCancelled:
                purchaseStatus = .idle
                print("StoreManager: Purchase cancelled by user")
                
            case .pending:
                purchaseStatus = .idle
                print("StoreManager: Purchase pending")
                
            @unknown default:
                purchaseStatus = .idle
            }
        } catch {
            purchaseStatus = .failed
            errorMessage = "购买失败: \(error.localizedDescription)"
            print("StoreManager: Purchase error - \(error)")
        }
    }
    
    // MARK: - 验证交易
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    // MARK: - 完成交易
    
    private func finishTransaction(_ transaction: Transaction) async {
        // 更新已购买列表
        await updatePurchasedStatus()
        
        // 完成交易（重要！）
        await transaction.finish()
    }
    
    // MARK: - 检查是否已购买
    
    func isPurchased(_ productID: String) -> Bool {
        purchasedIDs.contains(productID)
    }
    
    // MARK: - 检查高级功能
    
    var isPremium: Bool {
        isPurchased("com.heartbeatmemory.premium")
    }
    
    // MARK: - 恢复购买
    
    func restorePurchases() async {
        purchaseStatus = .purchasing
        
        do {
            try await AppStore.sync()
            await updatePurchasedStatus()
            purchaseStatus = .success
        } catch {
            purchaseStatus = .failed
            errorMessage = "恢复购买失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - 错误类型

enum StoreError: Error, LocalizedError {
    case verificationFailed
    case purchaseFailed
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "交易验证失败"
        case .purchaseFailed:
            return "购买失败"
        }
    }
}

// MARK: - 产品类型枚举

enum ProductType: String, CaseIterable {
    case premium = "premium"
    case unlockAll = "unlock_all"
    
    var displayName: String {
        switch self {
        case .premium:
            return "高级版"
        case .unlockAll:
            return "解锁全部功能"
        }
    }
    
    var description: String {
        switch self {
        case .premium:
            return "无广告 + 更多主题"
        case .unlockAll:
            return "所有功能无限使用"
        }
    }
}