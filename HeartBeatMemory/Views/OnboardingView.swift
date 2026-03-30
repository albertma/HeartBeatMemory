import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var currentStep: Int = 0
    @State private var isRequesting: Bool = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.red, .pink)
            
            Text("心跳回忆")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("用AI记录生活中的美好瞬间")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "calendar", title: "整合日历", description: "自动读取日历中的重要事件")
                FeatureRow(icon: "photo", title: "分析照片", description: "AI理解照片中的美好时刻")
                FeatureRow(icon: "location", title: "记录位置", description: "标记那些特别的地方")
                FeatureRow(icon: "brain", title: "AI智能", description: "用LLM生成温暖的回忆")
            }
            .padding(.horizontal)
            
            Spacer()
            
            if currentStep == 0 {
                Button(action: {
                    withAnimation { currentStep = 1 }
                }) {
                    Text("下一步")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            } else {
                Button(action: requestPermissions) {
                    HStack {
                        if isRequesting {
                            ProgressView().tint(.white)
                        }
                        Text(isRequesting ? "请求权限中..." : "授权数据访问")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isRequesting)
                .padding(.horizontal)
            }
            
            Button("跳过") { dismiss() }
                .foregroundColor(.secondary)
                .padding(.bottom)
        }
        .padding()
    }
    
    func requestPermissions() {
        isRequesting = true
        Task {
            let granted = await DataService.shared.requestAllPermissions()
            await MainActor.run {
                isRequesting = false
                if granted { dismiss() }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
