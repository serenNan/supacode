## Why

Supacode 目前完全没有本地化基础设施：3000+ 个 Swift 源文件里的用户可见文案全是英文字符串字面量，`Project.swift` 未配置任何非英文区域。中文用户只能看到英文界面。本次为 fork 自用引入本地化地基并翻译核心用户主流程，让中文界面可用，同时为后续分批翻译长尾界面打好底。

## What Changes

- **Tuist 项目接入本地化**：在 `Project.swift` 为 app target 声明 `developmentRegion`（保持 `en`）并把 `zh-Hans` 加入已知区域，新增一个 `Localizable.xcstrings` String Catalog 资源，开启编译期字符串提取（`Info.plist` / build settings 层面注册 `CFBundleLocalizations`）。
- **建立 String Catalog 工作流**：构建一次让 Xcode 自动把源码里的 `LocalizedStringKey`（`Text`/`Label`/`Button`/`.navigationTitle`/`.help`/`.accessibilityLabel` 等）提取进 `Localizable.xcstrings`，作为翻译单一事实源。
- **翻译核心用户主流程**：为高频界面提供 zh-Hans 译文——侧边栏、工具栏、设置各面板、onboarding 卡片、通知文案、命令面板核心项。长尾/低频界面留待后续分批。
- **处理非自动提取文案**：把核心主流程里少量无法被自动提取的用户可见字符串（`String(...)` 拼接、显式 `String(localized:)`、带插值的文案）改成可本地化形式；`SupaLogger` 日志、内部标识符、非 UI 字符串**不翻译**。
- **app 内语言选择器**：在 设置 → General 增加「语言」下拉（跟随系统 / 简体中文 / English），选择写入 `AppleLanguages` 偏好，切换后提示并一键重启 app 生效（macOS/SwiftUI 不支持真正的运行时热切换）。
- **手动切换验证**：文档化并验证通过系统语言 / scheme `-AppleLanguages` 参数 / app 内选择器切到中文时界面正确显示。

## Capabilities

### New Capabilities
- `chinese-localization`: 应用的本地化基础设施与简体中文（zh-Hans）翻译——String Catalog 资源、Tuist 区域注册、核心用户主流程的中文译文、哪些字符串该译 / 不该译的规则，以及 app 内语言选择器（写 `AppleLanguages` + 重启生效）。

### Modified Capabilities
<!-- 无：现有 openspec/specs/ 下没有与本地化相关的既有 capability，本次纯新增 -->

## Impact

- **构建配置**：`Project.swift`（app target 区域、资源、build settings）、可能新增 `supacode/Info.plist` 键。
- **新增资源**：`supacode/Resources/Localizable.xcstrings`（新文件，翻译事实源）。
- **源码**：核心主流程视图文件里少量非自动提取字符串的可本地化改写（预计个位数到低两位数文件，主要在 `supacode/Features/{Settings,Repositories,AgentPresence}`、通知与命令面板相关文件）。绝大多数已用 `LocalizedStringKey` 的视图**无需改源码**。
- **语言选择器**：设置 → General 视图（`SettingsView.swift` 内嵌 General 段）新增语言 Picker；新增语言偏好的 `@Shared(.appStorage)` 读写与启动早期同步到 `AppleLanguages` 的逻辑；新增 app 重启辅助逻辑（当前无现成 relaunch 机制）。
- **不影响**：`ThirdParty/`（Ghostty/Sparkle 等自带本地化）、日志、测试断言里的英文字符串、CLI。
- **交付去向**：fork 自用分支 `中文支持-ch`，先构建安装验证；后续若向 upstream #629 提 PR 再单独裁剪。
