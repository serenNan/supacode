# 侧边栏显示会话标签标题 — 设计文档

日期：2026-07-11
状态：已确认（方案 A）

## 背景与目标

侧边栏 worktree 行目前主标题是分支名。用户常在同一分支/worktree 里开多个终端 tab（多个 Claude Code 会话），侧边栏无法区分"这个分支正在干什么"，也无法展开查看各 tab。

目标：

1. worktree 行主标题改为显示**当前选中 tab 的标题**（如 "✳ Claude Code"），分支名移到副标题。
2. 多 tab 的 worktree 行可通过 chevron 展开，逐个显示 tab 子行；点击子行直接切换到该 tab。
3. 新增设置开关"侧边栏标题显示：会话标签 / 分支名"，默认会话标签；关闭时完全恢复现状。

非目标：不改顶部 tab bar；不改 Active/Pinned 高亮分类逻辑；展开状态不做持久化。

## 现状关键事实

- tab 标题只存在于 `TerminalTabManager`（每 worktree 一个的 `@MainActor @Observable`，`TerminalTabItem.displayTitle = customTitle ?? title`），未流入任何 TCA state。
- 每个 `WorktreeTerminalState` 已向 `SidebarItemFeature.State` 推送 per-worktree 行投影（`WorktreeRowProjection`，携带通知/运行脚本/agent 等）。
- 侧边栏架构铁律：per-leaf 数据存 `RepositoriesFeature.State.sidebarItems`；视图只渲染 reducer 后置钩子里算好的 `sidebarStructure`，视图零派生计算。
- 已有可参照的子行机制：分支前缀嵌套（`SidebarBranchNesting.buildRows` + chevron 折叠）。

## 方案（A：扩展行投影）

### 1. 数据流

- `WorktreeRowProjection` 新增：
  - `tabs: [TabSummary]`，`TabSummary` 含 `id`、`displayTitle`、`icon`、`tintColor`；
  - `selectedTabID: TerminalTabID?`。
- `WorktreeTerminalState` 在 tab 增删、标题变化（`updateTitle`/`setCustomTitle`）、选中变化（`selectTab`）时照常 emit 行投影。
- `SidebarItemFeature.State` 存 `tabs` 与 `selectedTabID`，并新增展开标志 `isTabListExpanded: Bool = false`（内存态，不持久化）。
- 标题解析优先级（在行 state / 结构计算中解析，不在视图）：
  1. worktree 自定义标题（`customTitle`）
  2. 选中 tab 的 `displayTitle`（开关开启时）
  3. 分支名（终端未打开 / 开关关闭时兜底）

### 2. 结构计算（实现阶段修订）

- tab 子行**不进** `sidebarStructure`：tabs 快照走独立事件（`TerminalClient.Event.worktreeTabsChanged`，对应 action 的 `cacheInvalidations = []`），子行由视图从 per-leaf scoped store 渲染。shell 标题的高频刷新因此完全不触发全表结构重算，符合侧边栏性能铁律（per-leaf 失效不外溢）。

### 3. UI

- worktree 行：主标题=解析后的标题；副标题=分支名（普通区），高亮区为 `repo · 分支名`；行尾多 tab 时显示 chevron + tab 计数。
- tab 子行（实现阶段修订）：缩进显示 tab 图标 + 标题，当前选中 tab 加粗并带 `.isSelected` accessibility trait；**不参与** `List` selection——子行是 Button 行（复刻既有 `SidebarPathGroupHeaderRow` 模式），父行保持选中高亮。
- 点击子行：新 action `sidebarTabRowSelected(Worktree.ID, tabID:)` → merge 发 `.selectWorktree(id, focusTerminal: true)` + 复用现成的 `delegate(.selectTerminalTab(_:tabId:))` 通路（AppFeature 已路由到 `terminalClient.send(.selectTab)`）。
- chevron 按钮带 tooltip；字体用系统样式，不硬编码字号。

### 4. 设置开关

- `@Shared` 新增布尔项（如 `sidebarShowsSessionTitles`，默认 `true`），设置界面加一行开关。
- 关闭时：主标题回退分支名、不生成子行、不显示 chevron/计数 —— 与现状完全一致。

### 5. 错误与边界

- worktree 无终端 state（未打开过）：无 tabs，兜底分支名，无 chevron。
- 单 tab：主标题用该 tab 标题，但不显示 chevron/子行（展开无意义）。
- tab 全部关闭后：回退分支名，展开标志复位。
- 标题为空字符串：视为无标题，走下一级兜底。

### 6. 测试

- 投影层：tab 标题/选中/增删变化 → `SidebarItemFeature.State` 更新（仿 `RepositoriesSidebarTestHelpers` 模式）。
- 结构层：展开/折叠生成与不生成子行；开关关闭不生成；进 `SidebarStructureTests`。
- 标题解析优先级单测（customTitle > tab 标题 > 分支名，含开关关闭分支）。
- `selectWorktreeTab` action 单测。
- 测试禁用 `Task.sleep`，用 `TestClock`。

## 涉及文件（预估）

- `WorktreeTerminalState.swift`（投影字段 + emit 时机）
- `SidebarItemFeature.swift`（行 state 字段、展开 action、标题解析）
- `SidebarStructure.swift`（子行结构、cacheInvalidations）
- `SidebarItemView.swift` / `SidebarItemsView.swift`（标题/副标题、chevron、子行渲染）
- `RepositoriesFeature.swift`（`selectWorktreeTab` action）
- 设置界面对应文件（新开关）
- 测试：`SidebarStructureTests.swift`、`SidebarItemFeatureTests.swift`、`RepositoriesFeatureSidebarTests.swift` 等
