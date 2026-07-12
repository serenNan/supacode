## ADDED Requirements

### Requirement: 本地化基础设施

应用 SHALL 声明 `en` 为开发区域并将 `zh-Hans` 注册为受支持区域，且 SHALL 提供一个作为翻译唯一事实源的 String Catalog 资源（`Localizable.xcstrings`）。构建产物 SHALL 在 app bundle 中包含 `zh-Hans` 本地化资源。

#### Scenario: 中文被注册为受支持语言

- **WHEN** 构建完成后检查 app bundle 的 `CFBundleLocalizations` 与 bundle 内的 `.lproj` 目录
- **THEN** `zh-Hans` 出现在受支持区域中，且 String Catalog 编译出的 `zh-Hans` 资源存在于 bundle

#### Scenario: 开发区域保持英文

- **WHEN** 系统语言不含中文时启动应用
- **THEN** 界面回退到英文（`en`），行为与本次改动前一致

### Requirement: LocalizedStringKey 文案自动提取

已使用 SwiftUI `LocalizedStringKey` 的用户可见文案（`Text`、`Label`、`Button`、`.navigationTitle`、`.help`、`.accessibilityLabel` 等）SHALL 通过编译期字符串提取自动进入 String Catalog，无需逐行改写源码即可获得对应的可翻译条目。

#### Scenario: 构建后核心文案出现在 Catalog

- **WHEN** 执行一次应用构建以触发字符串提取
- **THEN** 核心主流程界面的英文源字符串（如 "General"、"Notifications"、"Restore Defaults"）作为待翻译条目出现在 `Localizable.xcstrings`

### Requirement: 核心用户主流程中文译文

应用 SHALL 为核心用户主流程界面提供 zh-Hans 译文，覆盖：设置各面板、侧边栏、工具栏、onboarding 卡片、通知文案、命令面板核心项。当有效语言为中文时，这些界面的用户可见文案 SHALL 显示为简体中文。

#### Scenario: 中文环境下核心界面显示中文

- **WHEN** 以中文为有效语言（系统语言为中文，或以 `-AppleLanguages (zh-Hans)` 启动）运行应用并打开设置界面
- **THEN** 设置各面板标题与标签、侧边栏与工具栏、onboarding 卡片、通知文案显示为简体中文而非英文

#### Scenario: 未翻译的长尾条目回退英文

- **WHEN** 中文环境下访问尚未纳入本次翻译范围的长尾界面
- **THEN** 该界面回退显示英文源字符串，且不崩溃、不显示空白或 key 名

### Requirement: 翻译范围与排除规则

翻译 SHALL 仅覆盖用户可见文案。以下内容 MUST NOT 被翻译：`SupaLogger` 日志、代码内部标识符、面向机器的字符串（命令名、CLI 参数、URL、shell 片段如 `gh auth login`）、测试断言字符串。核心主流程中无法被自动提取的用户可见字符串（`String(...)` 拼接、显式 `String(localized:)`、带插值的文案）SHALL 被改写为可本地化形式并纳入 Catalog。

#### Scenario: 日志与机器字符串保持英文

- **WHEN** 审阅本次改动的 diff 与 Catalog 条目
- **THEN** `SupaLogger` 调用、CLI 参数、URL、shell 命令片段保持英文原样，未被加入翻译 Catalog

#### Scenario: 带插值的用户文案被本地化

- **WHEN** 中文环境下查看含动态内容的核心文案（如 "\(repository.name) — Scripts"）
- **THEN** 静态部分显示为中文，插值变量正确嵌入，格式正确

### Requirement: app 内语言选择器

设置界面 SHALL 在 General 面板提供语言选择器，至少含「跟随系统」「简体中文」「English」三项。选择非当前项 SHALL 将偏好写入 `AppleLanguages`，并因 macOS/SwiftUI 不支持运行时热切换而提示用户重启；应用 SHALL 提供一键重启入口。选择「跟随系统」SHALL 清除该覆盖、回到系统语言。语言偏好 SHALL 通过 `@Shared(.appStorage)` 持久化并在下次启动早期生效。

#### Scenario: 选择简体中文并重启后生效

- **WHEN** 用户在 设置 → General 的语言选择器选择「简体中文」并确认重启
- **THEN** 应用重启后以 zh-Hans 为有效语言，核心界面显示中文，且该偏好在后续启动中保持

#### Scenario: 跟随系统清除覆盖

- **WHEN** 用户将语言选择器切回「跟随系统」并重启
- **THEN** 应用不再强制某语言，界面随系统语言显示

#### Scenario: 未重启前提示明确

- **WHEN** 用户改了语言但尚未重启
- **THEN** 界面明确提示「重启后生效」，且提供一键重启，而非静默无反馈

### Requirement: 可切换语言验证

改动 SHALL 可通过手动切换语言验证：既能随系统语言切换，也能通过 scheme / 启动参数 `-AppleLanguages` 强制中文，无需重装应用。

#### Scenario: 强制中文启动

- **WHEN** 以 `-AppleLanguages (zh-Hans)` 启动参数运行应用
- **THEN** 已翻译的核心界面立即显示中文，无需修改系统设置
