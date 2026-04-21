import Foundation

// Bundle 路径测试
func testBundleModelPath() {
    print("🔍 测试 Bundle 模型路径...")
    
    // 方法 1: 使用 subdirectory
    if let bundleURL = Bundle.main.url(
        forResource: "Qwen2-VL-2B-Instruct-4bit",
        withExtension: nil,
        subdirectory: "LLM"
    ) {
        print("✅ 方法 1 - 找到模型路径: \(bundleURL.path)")
        
        // 检查关键文件
        let filesToCheck = [
            "config.json",
            "model.safetensors",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json"
        ]
        
        for filename in filesToCheck {
            let filePath = bundleURL.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: filePath) {
                print("  ✅ \(filename)")
            } else {
                print("  ❌ \(filename) - 不存在")
            }
        }
    } else {
        print("❌ 方法 1 - 找不到模型路径")
    }
    
    print("\n🔍 尝试其他查找方法...")
    
    // 方法 2: 直接查找 LLM 文件夹
    if let llmURL = Bundle.main.url(forResource: "LLM", withExtension: nil) {
        print("✅ 找到 LLM 文件夹: \(llmURL.path)")
        
        // 检查 LLM 文件夹内容
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: llmURL.path)
            print("  LLM 文件夹内容: \(contents)")
        } catch {
            print("  ❌ 无法读取 LLM 文件夹内容: \(error)")
        }
    } else {
        print("❌ 找不到 LLM 文件夹")
    }
    
    // 方法 3: 使用 resourcePath
    if let resourcePath = Bundle.main.resourcePath {
        print("\n📁 Bundle resourcePath: \(resourcePath)")
        
        let llmPath = (resourcePath as NSString).appendingPathComponent("LLM")
        if FileManager.default.fileExists(atPath: llmPath) {
            print("✅ 在 resourcePath 中找到 LLM 文件夹")
            
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: llmPath)
                print("  LLM 文件夹内容: \(contents)")
            } catch {
                print("  ❌ 无法读取 LLM 文件夹内容: \(error)")
            }
        } else {
            print("❌ 在 resourcePath 中找不到 LLM 文件夹")
        }
    }
}

// 运行测试
testBundleModelPath()