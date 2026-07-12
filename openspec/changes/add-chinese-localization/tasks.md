## 1. 本地化基础设施接入

- [x] 1.1 在 `Project.swift` 的 app target（`name: "supacode"`）settings.base 中加入 `SWIFT_EMIT_LOC_STRINGS = "YES"`，开启编译期字符串提取
- [x] 1.2 在 `supacode/Info.plist` 增加 `CFBundleLocalizations`（数组：`en`、`zh-Hans`），保持 `CFBundleDevelopmentRegion` 为 `en`
- [x] 1.3 新建空 String Catalog `supacode/Resources/Localizable.xcstrings`（source language 设为 en，含 zh-Hans 语言），并加入 `Project.swift` 的 `appResources`
- [ ] 1.4 `tuist generate` 后执行一次构建，触发字符串提取；确认 `Localizable.xcstrings` 被填入源字符串条目（构建进行中）
- [ ] 1.5 校验产物：构建后检查 app bundle 含 `zh-Hans.lproj` 且 `CFBundleLocalizations` 含 `zh-Hans`（对应 spec「本地化基础设施」场景）

## 2. 术语表与翻译规则

- [x] 2.1 在本 change 目录建一份小术语表（如 `glossary.md`）：确定专有名词译法（倾向 Worktree/Agent/Pane 保留英文；Repository→仓库、Settings→设置、Notifications→通知、Scripts→脚本 等）
- [x] 2.2 明确排除清单：`SupaLogger`、CLI 参数、URL、shell 片段（如 `gh auth login`）、测试字符串一律不译（对应 spec「翻译范围与排除规则」）

## 3. 核心主流程翻译 —— 设置

- [ ] 3.1 翻译 `Features/Settings/Views/SettingsView.swift` 相关条目（面板标签 General/Notifications/Worktrees/Developer/GitHub/Shortcuts/Global Scripts/Updates、navigationTitle 等）
- [ ] 3.2 翻译其余设置面板：`KeyboardShortcutsSettingsView`、`GithubSettingsView`、`DeveloperSettingsView`、Notifications / Worktrees / Updates 面板的用户可见文案
- [ ] 3.3 处理设置内非自动提取文案（`String(...)`/显式 `String(localized:)`/插值如 `"\(repository.name) — Scripts"`），改为可本地化形式并翻译

## 4. 核心主流程翻译 —— 侧边栏 / 工具栏 / onboarding / 通知 / 命令面板

- [ ] 4.1 翻译侧边栏与工具栏用户可见文案（按钮、tooltip `.help`、`.accessibilityLabel`、菜单项）
- [ ] 4.2 翻译 onboarding 卡片：`Features/Repositories/Views/*OnboardingCardView.swift`、`RemoteRepositoriesBetaCardView`、`CodingAgentsSidebarCardView`、`SidebarCardView`
- [ ] 4.3 翻译通知构造文案（通知标题/正文/计数文案；如遇复数/计数按需配置 Catalog 变体）
- [ ] 4.4 翻译命令面板核心项（高频命令名与说明）

## 5. app 内语言选择器（设置 → General）

- [ ] 5.1 定义语言偏好模型（枚举 `system`/`zh-Hans`/`en`），用 `@Shared(.appStorage("preferredLanguage"))` 持久化
- [ ] 5.2 在 app 启动早期把 `preferredLanguage` 同步到 `UserDefaults.standard` 的 `AppleLanguages`（`system` 时移除该 key）
- [ ] 5.3 在 `SettingsView.swift` General 段加语言 `Picker`，绑定偏好；改动后展示「重启后生效」提示与一键重启按钮
- [ ] 5.4 实现一键重启（走 app 既有 relaunch-safe 收尾后 `Process` 拉起自身 + `NSApp.terminate`）；重启失败时提示手动重开
- [ ] 5.5 为语言偏好写入 / 切「跟随系统」清除覆盖 / 触发重启的 reducer 逻辑补 TCA 测试（用 `TestClock`，不用 `Task.sleep`）

## 6. 巡检与验证

- [ ] 6.1 以 `-AppleLanguages (zh-Hans)` 启动应用，逐屏巡检核心主流程：设置 / 侧边栏 / 工具栏 / onboarding / 通知 / 命令面板均显示中文（对应 spec「核心用户主流程中文译文」场景）
- [ ] 6.2 经 app 内选择器切「简体中文」→ 重启 → 验证中文生效且偏好持久化（对应 spec「app 内语言选择器」场景）
- [ ] 6.3 巡检漏译/未提取文案：补 `String(localized:)` 后重新构建，直至核心界面无遗留英文
- [ ] 6.4 验证长尾未译界面回退英文、不崩溃、不露 key（对应「未翻译的长尾条目回退英文」场景）
- [ ] 6.5 验证英文环境（不含中文的系统语言）行为与改动前一致（对应「开发区域保持英文」场景）
- [ ] 6.6 `make build-app` 确认构建通过

## 7. 收尾

- [ ] 7.1 只提交本次改动文件（`Project.swift`、`Info.plist`、`Localizable.xcstrings`、语言选择器与少量视图源码、openspec 文档）到分支 `中文支持-ch`，不用 `git add .`
- [ ] 7.2 `openspec archive add-chinese-localization`（可选，视是否需要保留 openspec 而定，fork 自用可保留在 changes）
