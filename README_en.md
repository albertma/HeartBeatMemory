# HeartBeatMemory

Automatically generate warm life memory diaries from your photos and calendar events using AI.

## Features

- 📅 **Automatic Calendar Fetch** - Read today's schedule from system calendar
- 📸 **Photo Analysis** - Use VLM (Vision Language Model) to analyze photos and extract visual elements
- 🤖 **AI Memory Generation** - Combine photos and calendar events to generate warm memory diaries
- 🏷️ **Smart Classification** - Automatically identify mood and category
- 💾 **Local Storage** - Store data locally with SQLite

## Tech Stack

- **SwiftUI** - UI framework
- **MLX** - Apple machine learning framework (local VLM inference)
- **PhotosUI** - Photo library access
- **EventKit** - Calendar access
- **SQLite.swift** - Local data storage

## Project Structure

```
HeartBeatMemory/
├── HeartBeatMemoryApp.swift       # App entry point
├── ContentView.swift              # Main content view
├── Item.swift                    # Item definition
├── Models/
│   ├── HeartBeatMemory.swift      # Data model
│   ├── MLModels/
│   │   ├── LMModel.swift         # LM model definition
│   │   └── Message.swift        # Message model
│   └── PersistenceController.swift # Persistence controller
├── Services/
│   ├── AIService.swift          # AI analysis service
│   ├── DataService.swift        # Data fetching service
│   ├── MLXService.swift         # MLX model service
│   ├── DownloadMetadataManager.swift
│   └── ResumableModelDownloader.swift
├── Skills/
│   ├── Skill.swift              # Skill protocol
│   ├── SkillManager.swift      # Skill manager
│   ├── AnalyzePhotoSkill.swift # Photo analysis skill
│   └── GenerateDiarySkill.swift # Diary generation skill
├── ViewModels/
│   └── ChatViewModel.swift       # Chat view model
├── Views/
│   ├── ChatView.swift           # Chat view
│   ├── ConversationView.swift   # Conversation view
│   ├── DownloadProgressView.swift
│   ├── MediaPreviewView.swift   # Media preview view
│   ├── MessageView.swift        # Message view
│   ├── ModelDownloadView.swift  # Model download view
│   ├── OnboardingView.swift    # Onboarding view
│   ├── PromptField.swift        # Prompt input field
│   ├── SearchView.swift         # Search view
│   ├── SettingsView.swift       # Settings view
│   ├── TimelineView.swift       # Timeline view
│   └── Toolbar/
│       ├── ChatToolbarView.swift
│       ├── ErrorView.swift
│       └── GenerationInfoView.swift
└── Support/
    └── HubApi+default.swift     # Hub API support
```

## Data Models

### HeartBeatMemory
| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique identifier |
| date | Date | Memory date |
| title | String | Memory title |
| summary | String | Memory content |
| mood | Mood | Mood type |
| category | Category | Category type |

### Mood
| Mood | Description |
|------|-------------|
| Happy 😊 | Happy |
| Sad 😢 | Sad |
| Excited 🎉 | Excited |
| Calm 😌 | Calm |
| Grateful 🙏 | Grateful |
| Nostalgic 💭 | Nostalgic |
| Neutral 😐 | Neutral |

### Category
| Category | Description |
|----------|-------------|
| Travel | Travel |
| Family | Family |
| Work | Work |
| Friends | Friends |
| Hobby | Hobby |
| Food | Food |
| Milestone | Milestone |
| Daily | Daily |
| Other | Other |

## Requirements

- iOS 17.0+ / macOS 14.0+
- Photo library and calendar access permissions required
- MLX model download required (automatic in-app download)

## Dependencies

Installed via Swift Package Manager:
- **MLXLMCommon** - Local VLM inference (mlx-community)
- **SQLite.swift** - Local data storage

## License

MIT License - See [LICENSE](LICENSE)

## Learn More

- [MLX Documentation](https://ml-explore.github.io/MLX/)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)