# HeartBeatMemory

用 AI 将你的照片和日程自动生成温暖的生活回忆日记。

## 功能

- 📅 **自动获取日程** - 从系统日历读取当天的日程安排
- 📸 **照片分析** - 使用 VLM（视觉语言模型）分析照片，提取画面元素
- 🤖 **AI 回忆生成** - 结合照片和日程，用 LLM 生成温暖的回忆日记
- 🏷️ **智能分类** - 自动识别心情(mood)和分类(category)
- 💾 **本地存储** - 使用 UserDefaults 本地保存

## 技术栈

- **SwiftUI** - UI 框架
- **MLX** - 苹果机器学习框架（本地LLM + VLM）
- **PhotosUI** - 照片库访问
- **EventKit** - 日历访问

## 项目结构

```
HeartBeatMemory/
├── HeartBeatMemoryApp.swift   # App 入口
├── Models/
│   └── HeartBeatMemory.swift  # 数据模型
├── Services/
│   ├── AIService.swift        # AI 分析服务
│   ├── DataService.swift     # 数据获取服务
│   └── MLXService.swift      # MLX 模型服务
├── Views/                    # SwiftUI 视图
└── ViewModels/              # 视图模型
```

## 数据模型

### HeartBeatMemory
| 字段 | 类型 | 描述 |
|------|------|------|
| id | UUID | 唯一标识 |
| date | Date | 回忆日期 |
| title | String | 回忆标题 |
| summary | String | 回忆正文 |
| mood | Mood | 心情类型 |
| category | Category | 分类类型 |

### Mood (心情)
Happy 😊 | Sad 😢 | Excited 🎉 | Calm 😌 | Grateful 🙏 | Nostalgic 💭 | Neutral 😐

### Category (分类)
Travel | Family | Work | Friends | Hobby | Food | Milestone | Daily | Other

## 使用要求

- iOS 17.0+ / macOS 14.0+
- 需要照片库和日历访问权限
- 需要下载 MLX 模型（应用内自动下载）

## 依赖

通过 Swift Package Manager 安装：
- **MLXLMCommon** - 本地 LLM + VLM 推理

## License

MIT License - 查看 [LICENSE](LICENSE)