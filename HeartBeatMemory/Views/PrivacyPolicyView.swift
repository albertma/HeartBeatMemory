import SwiftUI
import WebKit

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("language") private var language: String = "zh"
    
    private var navTitle: String {
        language == "en" ? "Privacy Policy" : "隐私政策"
    }
    
    private var doneButton: String {
        language == "en" ? "Done" : "完成"
    }
    
    var body: some View {
        NavigationStack {
            WebView(url: Bundle.main.url(forResource: "privacy_policy", withExtension: "html")!)
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(doneButton) {
                            dismiss()
                        }
                    }
                }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL?
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = url else { return }
        
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

#Preview {
    PrivacyPolicyView()
}