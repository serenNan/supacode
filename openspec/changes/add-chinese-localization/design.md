## Context

Supacode 是 macOS 26+ / Swift 6 的 TCA + SwiftUI 应用，用 Tuist 4.180 生成工程。当前无任何本地化：app target 的 `Info.plist` 只有 `CFBundleDevelopmentRegion`（en），`Project.swift` 未声明其它区域，也没有 String Catalog。绝大多数用户可见文案已写成 SwiftUI 原生形式（`Text("General")`、`Label`、`Button`、`.navigationTitle`、`.help`、`.accessibilityLabel`），这些参数类型是 `LocalizedStringKey`，因此**天然可被编译期字符串提取**。真正的障碍只是：没有开启提取、没有目标语言资源、没有译文。

本次为 fork 自用引入本地化地基 + 简体中文核心主流程译文，在当前分支 `中文支持-ch` 落地并构建安装验证。

## Goals / Non-Goals

**Goals:**
- 用最小源码改动接入本地化：优先靠 String Catalog 编译期自动提取，而非逐行手工包裹字符串。
- 单一翻译事实源：一个 `Localizable.xcstrings`。
- 覆盖核心用户主流程（设置面板 / 侧边栏 / 工具栏 / onboarding / 通知 / 命令面板核心项）的中文译文。
- 未翻译条目安全回退英文，不崩溃、不露 key。
- 在 设置 → General 提供语言选择器（跟随系统 / 简体中文 / English），写 `AppleLanguages` + 一键重启生效。
- 可通过系统语言、`-AppleLanguages` 启动参数、或 app 内选择器验证。

**Non-Goals:**
- 全量翻译 3000+ 文件里的所有文案（长尾留后续分批）。
- 简体以外的中文变体（zh-Hant/zh-HK）或其它语言。
- 运行时**热切换**语言（点一下无需重启立即全界面变语言）——app 内选择器采用「写偏好 + 重启」，不自建 locale bundle 热刷新机制。
- 翻译 `ThirdParty/`（Ghostty/Sparkle 自带本地化）、日志、CLI、测试字符串。
- 向 upstream #629 提 PR（本次只 fork 自用，PR 裁剪是后续独立工作）。

## Decisions

**决策 1：用 String Catalog（`.xcstrings`）而非传统 `.strings`/`.stringsdict`。**
理由：Xcode 15+ 官方现代方案，单文件管理所有语言与复数规则，支持编译期从 `LocalizedStringKey` 自动提取，翻译状态（待译/已译/需复审）可视。备选 `.strings` 需手工维护 key 且易与源码漂移，弃用。

**决策 2：编译期自动提取为主，手工可本地化改写为辅。**
开启 `SWIFT_EMIT_LOC_STRINGS = YES`（app target build settings），构建时 Xcode 把源码中的 `LocalizedStringKey` 抽入 `Localizable.xcstrings`。只有无法被自动提取的用户可见字符串才手改：`String(...)` 拼接 → `String(localized:)`；纯 `String` 常量喂给非 LocalizedStringKey 参数的场景。带插值文案（如 `"\(repository.name) — Scripts"`）本就是有效的 `LocalizedStringKey` 插值，提取后在 Catalog 里以 `%@` 占位，直接翻译即可。备选「全手工 `String(localized:)` 包裹」改动面过大，弃用。

**决策 3：区域注册走 Tuist 资源推断 + Info.plist 显式声明双保险。**
把 `Localizable.xcstrings` 加入 `appResources`；Tuist 会据 Catalog 内含的 `zh-Hans` 自动把它加进工程 knownRegions。同时在 `supacode/Info.plist` 增加 `CFBundleLocalizations = [en, zh-Hans]` 显式声明受支持语言，`CFBundleDevelopmentRegion` 保持 `en`。双保险避免 Tuist 版本行为差异导致 bundle 漏掉 `zh-Hans.lproj`。

**决策 4：不新建 target、不引依赖。**
Catalog 放 `supacode/Resources/Localizable.xcstrings`，归属现有 app target。符合 CLAUDE.md「不为包装引入新客户端」的精神。

**决策 6：语言选择器用「写 `AppleLanguages` + 重启」而非运行时热切换。**
macOS/AppKit 在启动时加载语言 bundle，SwiftUI 无官方运行时热切换。选择器把偏好写入 `@Shared(.appStorage("preferredLanguage"))`（值 `system`/`zh-Hans`/`en`），并同步写 `UserDefaults.standard` 的 `AppleLanguages`（`system` 时移除该 key 回到系统语言）；改动后弹提示并提供一键重启。重启通过辅助方式实现（如 `Process` 延迟拉起自身可执行文件后 `NSApp.terminate(nil)`）。偏好在启动早期（app 入口，AppKit 读取 bundle 前不可行——故依赖下次启动读取 `AppleLanguages`）生效。备选「自建 locale bundle + 环境注入热刷新」复杂且与 TCA/SwiftUI 集成脆弱，弃用（列入 Non-Goals）。选择器 UI 放 `SettingsView.swift` 的 General 段，用 `Picker` + 现有 `@Shared` 模式，符合 CLAUDE.md「`@Shared` 直接进 reducer/视图」。

**决策 5：翻译范围用「文件白名单」而非全量。**
先构建让 Catalog 收集全部提取条目，然后**只翻译核心主流程涉及的源字符串**，其余 stale/未译条目保持英文回退。核心清单：`Features/Settings/Views/*`、`Features/Repositories/Views/*`（含 onboarding 卡片）、`Features/AgentPresence/Views/*`、工具栏与侧边栏视图、通知构造文案、命令面板核心项。术语统一（如 Worktree、Repository、Agent 等专有名词的中文/保留英文取舍）在 tasks 阶段定一份小术语表。

## Risks / Trade-offs

- **自动提取覆盖不全** → 部分文案在运行时才拼装，编译期抓不到。缓解：核心界面构建后逐屏人工巡检，漏掉的手动改 `String(localized:)` 再构建。
- **误译机器字符串**（CLI 参数、URL、`gh auth login`、shell 片段） → 破坏功能。缓解：spec 明确排除规则；翻译时只碰界面标签，机器字符串即便进了 Catalog 也保持英文原样、不填中文。
- **Catalog 噪音**：编译期会提取到大量长尾/无关条目 → Catalog 很大。缓解：可接受；只翻核心条目，其余留「待译」状态不影响回退。
- **Tuist regenerate 覆盖手改**：`Project.swift`/Info.plist 由 Tuist 生成工程。缓解：改动写在 `Project.swift` 与 `Info.plist` 源（Tuist 的输入），而非生成后的 `.xcodeproj`，regenerate 安全。
- **多会话构建互踩**（记忆已知坑）→ 用 worktree + 直连 tuist/xcodebuild，避免 `make` 清共享 DerivedData。缓解：构建验证遵循既有 worktree 构建规范。
- **术语不一致** → 各面板译法漂移。缓解：tasks 阶段先定小术语表，翻译时对照。
- **重启体验粗糙**：一键重启若失败（沙盒/权限/多窗口未保存）→ 用户困惑或丢状态。缓解：重启前走正常退出流程（复用 app 既有的 relaunch-safe 收尾，如通知徽章/终端状态持久化）；重启失败时提示用户手动重开。
- **AppleLanguages 时序**：偏好只在下次启动读取，当前会话不变 → 用户以为没生效。缓解：UI 明确「重启后生效」并引导一键重启，不承诺即时变化。

## Migration Plan

1. 改 `Project.swift`（app target settings 加 `SWIFT_EMIT_LOC_STRINGS`）+ `Info.plist`（`CFBundleLocalizations`）。
2. 新建空 `Localizable.xcstrings` 加入资源，`tuist generate` 后构建一次触发提取。
3. 在 Catalog 中为核心主流程条目填 zh-Hans 译文。
4. 处理巡检出的非自动提取文案，再构建。
5. 实现 设置 → General 语言选择器：`@Shared(.appStorage("preferredLanguage"))` + `AppleLanguages` 同步 + 一键重启，并加 reducer 测试。
6. 以 `-AppleLanguages (zh-Hans)` 启动 + app 内选择器切换两条路径验证核心界面中文显示、长尾回退英文。
7. `make build-app` 确认构建通过后提交（仅本次改动文件）。

回滚：还原 `Project.swift`/`Info.plist` 改动并删除 `Localizable.xcstrings`，工程回到纯英文，无数据迁移风险。

## Open Questions

- 专有名词中文化边界：Worktree / Repository / Agent / Pane 等是译成中文还是保留英文？→ tasks 阶段定术语表时明确（倾向：Worktree、Agent 保留英文，Repository→仓库、Settings→设置、Notifications→通知等通用词译中文）。
- 是否需要为通知的复数/计数文案（如 "N notifications"）配置 Catalog 复数变体？→ 巡检到再定，MVP 可先用简单占位。
