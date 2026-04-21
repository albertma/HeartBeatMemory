# HeartBeatMemory

用 AI 将你的照片和日程自动生成温暖的生活回忆日记。 使用iOS侧本地的VLM，而不是用云端的VLM。我相信未来LLM不只出现在云端，还会出现在设备端。

## 功能

- 📅 **自动获取日程** - 从系统日历读取当天的日程安排
- 📸 **照片分析** - 使用 VLM（视觉语言模型）分析照片，提取画面元素
- 🤖 **AI 回忆生成** - 结合照片和日程，用 VLM 生成温暖的回忆日记
- 🏷️ **智能分类** - 自动识别心情(mood)和分类(category)
- 💾 **本地存储** - 使用 SQLite 本地保存

## 技术栈

- **SwiftUI** - UI 框架
- **MLX** - 苹果机器学习框架（本地 VLM 推理）
- **PhotosUI** - 照片库访问
- **EventKit** - 日历访问
- **SQLite.swift** - 本地数据存储

## 项目结构

```
HeartBeatMemory/
├── HeartBeatMemoryApp.swift       # App 入口
├── ContentView.swift              # 主内容视图
├── Item.swift                    # 项目定义
├── Models/
│   ├── HeartBeatMemory.swift      # 数据模型
│   ├── MLModels/
│   │   ├── LMModel.swift         # LM 模型定义
│   │   └── Message.swift        # 消息模型
│   └── PersistenceController.swift # 持久化控制器
├── Services/
│   ├── AIService.swift          # AI 分析服务
│   ├── DataService.swift        # 数据获取服务
│   ├── MLXService.swift         # MLX 模型服务
│   ├── DownloadMetadataManager.swift
│   └── ResumableModelDownloader.swift
├── Skills/
│   ├── Skill.swift              # Skill 协议
│   ├── SkillManager.swift        # Skill 管理器
│   ├── AnalyzePhotoSkill.swift  # 照片分析 Skill
│   └── GenerateDiarySkill.swift # 日记生成 Skill
├── ViewModels/
│   └── ChatViewModel.swift       # 聊天视图模型
├── Views/
│   ├── ChatView.swift           # 聊天视图
│   ├── ConversationView.swift   # 对话视图
│   ├── DownloadProgressView.swift
│   ├── MediaPreviewView.swift    # 媒体预览视图
│   ├── MessageView.swift         # 消息视图
│   ├── ModelDownloadView.swift    # 模型下载视图
│   ├── OnboardingView.swift    # 引导视图
│   ├── PromptField.swift       # 输入框视图
│   ├── SearchView.swift        # 搜索视图
│   ├── SettingsView.swift       # 设置视图
│   ├── TimelineView.swift      # 时间线视图
│   └── Toolbar/
│       ├── ChatToolbarView.swift
│       ├── ErrorView.swift
│       └── GenerationInfoView.swift
└── Support/
    └── HubApi+default.swift    # Hub API 支持
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
| 心情 | 描述 |
|------|------|
| Happy 😊 | 开心 |
| Sad 😢 | 难过 |
| Excited 🎉 | 兴奋 |
| Calm 😌 | 平静 |
| Grateful 🙏 | 感恩 |
| Nostalgic 💭 | 怀念 |
| Neutral 😐 | 中性 |

### Category (分类)
| 分类 | 描述 |
|------|------|
| Travel | 旅行 |
| Family | 家庭 |
| Work | 工作 |
| Friends | 朋友 |
| Hobby | 爱好 |
| Food | 美食 |
| Milestone | 里程碑 |
| Daily | 日常 |
| Other | 其他 |

## 使用要求

- iOS 17.0+ / macOS 14.0+
- 需要照片库和日历访问权限
- 需要下载 MLX 模型（应用内自动下载）

## 依赖

通过 Swift Package Manager 安装：
- **MLXLMCommon** - 本地 VLM 推理 (mlx-community)
- **SQLite.swift** - 本地数据存储

## License

MIT License - 查看 [LICENSE](LICENSE)

## 了解更多

- [MLX 文档](https://ml-explore.github.io/MLX/)
- [Apple 开发者文档](https://developer.apple.com/documentation/)
