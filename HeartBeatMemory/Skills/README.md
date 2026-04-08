# Skills

模块化 AI Agent 技能系统

## 架构

```
Skills/
├── Skill.swift              # 基础协议和数据结构
├── SkillManager.swift       # Skill 管理器
├── AnalyzePhotoSkill.swift   # 照片分析技能
└── GenerateDiarySkill.swift # 日记生成技能
```

## 使用方式

```swift
let skillManager = SkillManager.shared

let context = SkillContext(
    date: Date(),
    events: events,
    photos: photos,
    locations: locations
)

// 单个执行
let result = try await skillManager.execute("analyze_photo", with: context)

// 链式执行（推荐）
let results = try await skillManager.executeChain(
    ["analyze_photo", "generate_diary"],
    with: context
)
```

## 内置 Skills

| ID | Name | 功能 | 输出 |
|----|------|------|------|
| analyze_photo | Analyze Photo | VLM 照片分析 | `SkillData.analysis` |
| generate_diary | Generate Diary | LLM 日记生成 | `SkillData.diary` |

## 自定义 Skill

```swift
final class MyCustomSkill: Skill {
    let id = "my_skill"
    let name = "My Skill"
    let description = "描述技能功能"
    
    func execute(with context: SkillContext) async throws -> SkillResult {
        // 实现逻辑
        return SkillResult(
            skillId: id,
            data: .custom(data),
            metadata: [:]
        )
    }
}

// 注册
skillManager.register(MyCustomSkill())
```