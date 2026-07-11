# 侧边栏会话标签标题 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 侧边栏 worktree 行主标题显示当前选中终端 tab 的标题，分支名移到副标题；多 tab 行可展开为 tab 子行，点击子行切换到该 tab；由设置开关控制（默认开）。

**Architecture:** 新增独立于 `WorktreeRowProjection` 的 tabs 快照投影：`TerminalTabManager`（tab 标题真源）→ `WorktreeTerminalState`（合并下一 tick 发射）→ `WorktreeTerminalManager`（Equatable 去重后 emit `TerminalClient.Event.worktreeTabsChanged`）→ `AppFeature` 路由 → `SidebarItemFeature.State`（per-leaf）。视图从 per-leaf scoped store 渲染标题与子行，`sidebarStructure` 完全不感知 tabs（标题风暴不触发全表重算）。子行是 Button 行（复刻 `SidebarPathGroupHeaderRow` 模式），点击复用现成的 `delegate(.selectTerminalTab)` 通路。

**Tech Stack:** Swift 6 / SwiftUI / TCA（swift-composable-architecture）/ swift-testing（`@Test` + `#expect`）

**设计文档:** `docs/superpowers/specs/2026-07-11-sidebar-session-tab-titles-design.md`

## Global Constraints

- Target macOS 26.0+，Swift 6.0；现代 SwiftUI（`foregroundStyle()`、`Button` 而非 `onTapGesture`）；不硬编码字号；按钮必须带 `.help()` tooltip。
- 日志一律 `SupaLogger`，禁止 `print()` / `os.Logger`。
- 单测禁止 `Task.sleep`；需要驱动时间用 `TestClock` / `ImmediateClock`。
- Reducer 逻辑变更必须加测试。
- 侧边栏铁律：视图零派生计算离开 per-leaf scoped store 的范围；per-leaf 读取必须经 `store.scope(state: \.sidebarItems[id:])`；新增 action 必须在 `SidebarStructure.swift` 的两个穷尽 `cacheInvalidations` switch 里登记（漏登记是编译错误）。
- **Git 纪律（重要）：**
  - 先建分支：`git switch -c sidebar-session-tab-titles`（当前在 main，不允许直接提交 main）。
  - 工作区已有**与本计划无关的未提交改动**：`supacode/Features/Terminal/Models/WorktreeTerminalState.swift`（通知 dedupe hunks）、`supacodeTests/WorktreeTerminalManagerTests.swift`（`newNotificationReplacesOlderOnesInSameTab` 测试），以及未跟踪的 `openspec/`、`supacode/Clients/Github/GithubIssue*.swift`、`supacodeTests/GithubIssues*.swift`。**不得提交、不得回退这些内容。**本计划恰好也要改这两个文件：提交时用 `git add -p <file>` 只暂存本计划的 hunks，绝不 `git add .` / `git add -A`。
  - 提交信息不写 AI co-author（仓库规则：作者只能是人）。
- 每个任务结束跑 `make build-app` 确认可编译；测试用下面的单 suite 命令（全量 `make test` 只在收尾跑一次）：

```bash
DEVELOPER_DIR="$(./scripts/select-developer-dir.sh)" xcodebuild test \
  -workspace supacode.xcworkspace -scheme supacode-tests -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation \
  -only-testing:supacodeTests/<SuiteName> 2>&1 | mise exec -- xcbeautify
```

---

### Task 1: `WorktreeTabsSummary` 类型 + `TerminalTabManager.onSnapshotChanged` 回调

**Files:**
- Modify: `supacode/Features/Repositories/Reducer/SidebarItemFeature.swift`（文件尾部，`WorktreeRowProjection` 定义之后，约 :280）
- Modify: `supacode/Features/Terminal/Models/TerminalTabManager.swift`
- Test: `supacodeTests/TerminalTabManagerTests.swift`

**Interfaces:**
- Produces: `struct WorktreeTabsSummary: Equatable, Sendable { struct Tab: Equatable, Identifiable, Sendable { let id: TerminalTabID; let title: String; let icon: String?; let tint: RepositoryColor? }; var tabs: [Tab]; var selectedTabID: TerminalTabID? }`（默认 init：`tabs: [] / selectedTabID: nil`）
- Produces: `TerminalTabManager.onSnapshotChanged: (() -> Void)?` — `tabs` 数组任何变异（含元素级 `title`/`customTitle`/`isDirty` 写入）和 `selectedTabId` 实际变化时触发。

- [ ] **Step 1: 写失败测试**（追加到 `TerminalTabManagerTests` struct 内）

```swift
@Test func snapshotCallbackFiresOnTabAndSelectionMutations() {
  let manager = TerminalTabManager()
  var fireCount = 0
  manager.onSnapshotChanged = { fireCount += 1 }

  let first = manager.createTab(title: "one", icon: nil)  // tabs + selectedTabId
  let afterCreate = fireCount
  #expect(afterCreate >= 1)

  manager.updateTitle(first, title: "renamed")
  #expect(fireCount == afterCreate + 1)

  // No-op title write must not fire (updateTitle's equality guard).
  manager.updateTitle(first, title: "renamed")
  #expect(fireCount == afterCreate + 1)

  let second = manager.createTab(title: "two", icon: nil)
  let afterSecond = fireCount
  manager.selectTab(first)
  #expect(fireCount == afterSecond + 1)

  // Selecting the already-selected tab must not fire.
  manager.selectTab(first)
  #expect(fireCount == afterSecond + 1)

  manager.closeTab(second)
  #expect(fireCount > afterSecond + 1)
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 上面的单 suite 命令，`<SuiteName>` = `TerminalTabManagerTests`
Expected: FAIL，编译错误 `value of type 'TerminalTabManager' has no member 'onSnapshotChanged'`

- [ ] **Step 3: 实现**

`TerminalTabManager.swift`：`tabs` 的 didSet 追加回调，`selectedTabId` 新增 didSet：

```swift
var tabs: [TerminalTabItem] = [] {
  // Drops `editingTabID` when the edited tab disappears across any close path.
  didSet {
    onSnapshotChanged?()
    guard let id = editingTabID, !tabs.contains(where: { $0.id == id }) else { return }
    editingTabID = nil
  }
}
var selectedTabId: TerminalTabID? {
  didSet {
    guard oldValue != selectedTabId else { return }
    onSnapshotChanged?()
  }
}
private(set) var editingTabID: TerminalTabID?
/// Fires on any tab-array mutation (create / close / reorder / title / dirty)
/// or selected-tab change. `WorktreeTerminalState` coalesces this into a
/// next-tick tabs-summary projection emit.
var onSnapshotChanged: (() -> Void)?
```

`SidebarItemFeature.swift`（`WorktreeRowProjection` 定义后追加）：

```swift
/// Per-worktree snapshot of the terminal tab strip (titles / icons / selected
/// tab), emitted separately from `WorktreeRowProjection` so title storms never
/// touch the sidebar-structure recompute path. Consumed by
/// `SidebarItemFeature.tabsSnapshotChanged`.
struct WorktreeTabsSummary: Equatable, Sendable {
  struct Tab: Equatable, Identifiable, Sendable {
    let id: TerminalTabID
    let title: String
    let icon: String?
    let tint: RepositoryColor?
  }

  var tabs: [Tab] = []
  var selectedTabID: TerminalTabID? = nil
}
```

- [ ] **Step 4: 跑测试确认通过**（同 Step 2 命令，Expected: PASS，且原有 TerminalTabManagerTests 全绿）
- [ ] **Step 5: `make build-app` 通过后提交**

```bash
git add supacode/Features/Terminal/Models/TerminalTabManager.swift supacode/Features/Repositories/Reducer/SidebarItemFeature.swift supacodeTests/TerminalTabManagerTests.swift
git commit -m "Add tab-strip snapshot callback and WorktreeTabsSummary type"
```

---

### Task 2: tabs 快照投影管道（State → Manager → TerminalClient 事件）

**Files:**
- Modify: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`（init 约 :212、`currentProjection()` 附近约 :246；**该文件含无关的未提交 dedupe hunks，提交用 `git add -p`**）
- Modify: `supacode/Clients/Terminal/TerminalClient.swift`（`Event` 枚举 :67-111）
- Modify: `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`（`CoalesceKey` :85、`coalesceKey(for:)` :98、`eventStream()` :441、`state(for:)` 接线 :523-597、`invalidateCaches` :1174、`emitProjection` 附近 :1231）
- Test: `supacodeTests/WorktreeTerminalManagerTests.swift`（**同样含无关未提交测试，追加不冲突，提交用 `git add -p`**）

**Interfaces:**
- Consumes: Task 1 的 `WorktreeTabsSummary`、`TerminalTabManager.onSnapshotChanged`
- Produces: `TerminalClient.Event.worktreeTabsChanged(Worktree.ID, WorktreeTabsSummary)`；`WorktreeTerminalState.currentTabsSummary() -> WorktreeTabsSummary`；`WorktreeTerminalState.onTabsSummaryChanged: (() -> Void)?`

- [ ] **Step 1: 写失败测试**（追加到 `WorktreeTerminalManagerTests`，仿 `emitsEventsAfterStreamCreated` 模式）

```swift
@Test func emitsTabsSummaryOnTitleAndSelectionChange() async {
  let manager = WorktreeTerminalManager(runtime: GhosttyRuntime())
  let worktree = makeWorktree()
  let state = manager.state(for: worktree)
  let stream = manager.eventStream()
  guard let tab = state.createTab() else {
    Issue.record("Expected a tab")
    return
  }
  state.tabManager.updateTitle(tab, title: "Claude Code")
  var received: WorktreeTabsSummary?
  for await event in stream {
    guard case .worktreeTabsChanged(let id, let summary) = event, id == worktree.id else { continue }
    if summary.tabs.first?.title == "Claude Code" {
      received = summary
      break
    }
  }
  #expect(received?.selectedTabID == tab)
  #expect(received?.tabs.count == 1)
}
```

- [ ] **Step 2: 跑测试确认失败**（`<SuiteName>` = `WorktreeTerminalManagerTests`；Expected: 编译错误 no member `worktreeTabsChanged`）

- [ ] **Step 3: 实现**

`TerminalClient.swift` — `Event` 枚举里 `worktreeProjectionChanged` case 之后追加：

```swift
/// Per-worktree tab-strip snapshot (titles / icons / selected tab). Emitted
/// separately from `worktreeProjectionChanged` so per-keystroke shell-title
/// churn never invalidates sidebar-structure caches. Routed into the matching
/// `SidebarItemFeature` via the row's id.
case worktreeTabsChanged(Worktree.ID, WorktreeTabsSummary)
```

`WorktreeTerminalState.swift`：

1. callbacks 区（`onTabProgressDisplayChanged` 声明后）：

```swift
/// Fires (coalesced, next tick) when the tab strip's snapshot (titles /
/// order / selection) drifts. Manager re-emits the Equatable-diffed
/// `WorktreeTabsSummary` so the sidebar row mirrors terminal truth.
var onTabsSummaryChanged: (() -> Void)?
```

2. 属性区（`pendingRunningScriptsProjectionEmit` 旁）：

```swift
/// Coalesces per-mutation tab-manager callbacks into one next-tick emit so a
/// create-then-select or a reorder never reaches TCA mid-operation.
@ObservationIgnored private var pendingTabsSummaryEmit = false
```

3. `init` 末尾（`shouldHideTabBar` 赋值后）：

```swift
tabManager.onSnapshotChanged = { [weak self] in
  self?.scheduleTabsSummaryEmit()
}
```

4. `scheduleRunningScriptsProjectionEmit()` 之后：

```swift
func currentTabsSummary() -> WorktreeTabsSummary {
  WorktreeTabsSummary(
    tabs: tabManager.tabs.map {
      WorktreeTabsSummary.Tab(id: $0.id, title: $0.displayTitle, icon: $0.icon, tint: $0.tintColor)
    },
    selectedTabID: tabManager.selectedTabId
  )
}

private func scheduleTabsSummaryEmit() {
  guard !pendingTabsSummaryEmit else { return }
  pendingTabsSummaryEmit = true
  Task { @MainActor [weak self] in
    guard let self else { return }
    self.pendingTabsSummaryEmit = false
    self.onTabsSummaryChanged?()
  }
}
```

`WorktreeTerminalManager.swift`：

1. 缓存字段（`lastEmittedProjections` 旁 :26）：

```swift
private var lastEmittedTabsSummaries: [Worktree.ID: WorktreeTabsSummary] = [:]
```

2. `CoalesceKey` 加 `case worktreeTabs(Worktree.ID)`；`coalesceKey(for:)` 加：

```swift
case .worktreeTabsChanged(let worktreeID, _): .worktreeTabs(worktreeID)
```

3. `state(for:)` 接线（`onTabProgressDisplayChanged` 接线后）：

```swift
state.onTabsSummaryChanged = { [weak self] in
  self?.emitTabsSummary(for: worktree.id)
}
```

4. `emitProjection(for:)` 之后新增：

```swift
/// Tab-strip mirror of `emitProjection(for:)`: Equatable-diffed against the
/// last emitted summary so dirty-flag churn and no-op writes never reach TCA.
private func emitTabsSummary(for worktreeID: Worktree.ID) {
  guard eventContinuation != nil else { return }
  guard let state = states[worktreeID] else { return }
  let summary = state.currentTabsSummary()
  guard lastEmittedTabsSummaries[worktreeID] != summary else { return }
  lastEmittedTabsSummaries[worktreeID] = summary
  emit(.worktreeTabsChanged(worktreeID, summary))
}
```

5. `eventStream()`：`lastEmittedProjections.removeAll()` 旁加 `lastEmittedTabsSummaries.removeAll()`；seed 循环 `for id in states.keys { emitProjection(for: id) }` 后加 `for id in states.keys { emitTabsSummary(for: id) }`。

6. teardown：`invalidatedCoalesceKeys(by:)` 的 `.worktreeStateTornDown` 数组追加 `.worktreeTabs(worktreeID)`；`invalidateCaches(forPrunedWorktree:)` 加 `lastEmittedTabsSummaries.removeValue(forKey: id)`。

- [ ] **Step 4: 跑测试确认通过**（`WorktreeTerminalManagerTests` 全绿，包括工作区里已有的未提交测试）
- [ ] **Step 5: `make build-app`；注意 `AppFeature.swift` 若因 `terminalEvent` switch 非穷尽而编译失败，临时加 `case .terminalEvent(.worktreeTabsChanged): return .none`（Task 3 会替换成真实路由）**
- [ ] **Step 6: 提交（注意 `git add -p` 跳过 dedupe hunks）**

```bash
git add supacode/Clients/Terminal/TerminalClient.swift supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift
git add -p supacode/Features/Terminal/Models/WorktreeTerminalState.swift   # 只选本任务 hunks
git add -p supacodeTests/WorktreeTerminalManagerTests.swift                # 只选 emitsTabsSummary… 测试
# AppFeature 若加了临时 case 也一并 add
git commit -m "Emit per-worktree tab-strip summaries through TerminalClient"
```

---

### Task 3: `SidebarItemFeature` 收纳快照 + 展开状态 + AppFeature 路由

**Files:**
- Modify: `supacode/Features/Repositories/Reducer/SidebarItemFeature.swift`（State :107 附近、Action :124、reducer body :174 附近、extension :208）
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift`（`SidebarItemFeature.Action.cacheInvalidations` :356-374）
- Modify: `supacode/Features/App/Reducer/AppFeature.swift`（`.terminalEvent(.worktreeProjectionChanged…)` :1311 之后；替换 Task 2 的临时 case）
- Test: `supacodeTests/SidebarItemFeatureTests.swift`

**Interfaces:**
- Consumes: Task 1/2 的 `WorktreeTabsSummary`、`.worktreeTabsChanged` 事件
- Produces: `SidebarItemFeature.State.tabsSummary: WorktreeTabsSummary`、`.isTabListExpanded: Bool`、`.selectedTabTitle: String?`（trim 后非空才返回）；`SidebarItemFeature.Action.tabsSnapshotChanged(WorktreeTabsSummary)`、`.tabListExpansionToggled`

- [ ] **Step 1: 写失败测试**（追加到 `SidebarItemFeatureTests`；`makeState(name:)` 是该文件既有 helper）

```swift
@Test func tabsSnapshotUpdatesStateAndCollapsesOnSingleTab() async {
  let tabA = TerminalTabID()
  let tabB = TerminalTabID()
  let store = TestStore(initialState: makeState(name: "feature")) {
    SidebarItemFeature()
  }
  let twoTabs = WorktreeTabsSummary(
    tabs: [
      .init(id: tabA, title: "Claude Code", icon: nil, tint: nil),
      .init(id: tabB, title: "Tests", icon: nil, tint: nil),
    ],
    selectedTabID: tabB
  )
  await store.send(.tabsSnapshotChanged(twoTabs)) {
    $0.tabsSummary = twoTabs
  }
  #expect(store.state.selectedTabTitle == "Tests")

  await store.send(.tabListExpansionToggled) {
    $0.isTabListExpanded = true
  }

  // Identical snapshot: no-op.
  await store.send(.tabsSnapshotChanged(twoTabs))

  // Dropping to one tab resets the expansion.
  let oneTab = WorktreeTabsSummary(
    tabs: [.init(id: tabA, title: "Claude Code", icon: nil, tint: nil)],
    selectedTabID: tabA
  )
  await store.send(.tabsSnapshotChanged(oneTab)) {
    $0.tabsSummary = oneTab
    $0.isTabListExpanded = false
  }
}

@Test func selectedTabTitleFallsBackOnBlankOrMissing() {
  var state = makeState(name: "feature")
  let blankTab = TerminalTabID()
  // Selected tab with a blank title → nil (view falls back to branch name).
  state.tabsSummary = WorktreeTabsSummary(
    tabs: [.init(id: blankTab, title: "   ", icon: nil, tint: nil)],
    selectedTabID: blankTab
  )
  #expect(state.selectedTabTitle == nil)

  // No tabs at all → nil.
  state.tabsSummary = WorktreeTabsSummary(tabs: [], selectedTabID: nil)
  #expect(state.selectedTabTitle == nil)
}

@Test func selectedTabTitleTrimsWhitespace() {
  var state = makeState(name: "feature")
  let tab = TerminalTabID()
  state.tabsSummary = WorktreeTabsSummary(
    tabs: [.init(id: tab, title: "  Claude Code  ", icon: nil, tint: nil)],
    selectedTabID: tab
  )
  #expect(state.selectedTabTitle == "Claude Code")
}
```

- [ ] **Step 2: 跑测试确认失败**（`<SuiteName>` = `SidebarItemFeatureTests`；Expected: 编译错误 no member `tabsSnapshotChanged`）

- [ ] **Step 3: 实现**

`SidebarItemFeature.swift` State（`hasTerminalProjection` 之后）：

```swift
/// Mirror of the worktree's terminal tab strip; the sole populator is
/// `tabsSnapshotChanged`, fed from `TerminalClient.Event.worktreeTabsChanged`.
var tabsSummary: WorktreeTabsSummary = WorktreeTabsSummary()
/// Whether the row's per-tab sub-rows are expanded. In-memory only: tabs are
/// runtime entities, so the expansion doesn't persist across relaunch.
var isTabListExpanded: Bool = false
```

Action（`terminalProjectionChanged` 之后）：

```swift
case tabsSnapshotChanged(WorktreeTabsSummary)
case tabListExpansionToggled
```

reducer body（`.terminalProjectionChanged` arm 之后）：

```swift
case .tabsSnapshotChanged(let summary):
  if state.tabsSummary != summary { state.tabsSummary = summary }
  // A row that fell to 0/1 tabs has nothing to expand; reset so a later
  // multi-tab state starts collapsed.
  if summary.tabs.count <= 1, state.isTabListExpanded {
    state.isTabListExpanded = false
  }
  return .none

case .tabListExpansionToggled:
  state.isTabListExpanded.toggle()
  return .none
```

`extension SidebarItemFeature.State`（`resolvedSidebarTitle` 之后）：

```swift
/// Display title of the currently selected terminal tab, or nil when the
/// worktree has no live tab / the title is blank. Views layer this between
/// the user's custom title and the branch-name fallback.
var selectedTabTitle: String? {
  guard let selectedID = tabsSummary.selectedTabID,
    let tab = tabsSummary.tabs.first(where: { $0.id == selectedID })
  else { return nil }
  let trimmed = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}
```

`SidebarStructure.swift` — `SidebarItemFeature.Action.cacheInvalidations` 的空集 case 追加两个新 action：

```swift
case .diffStatsChanged, .pullRequestQueryStarted,
  .dragSessionChanged,
  .tabsSnapshotChanged, .tabListExpansionToggled,
  .focusTerminalRequested, .focusTerminalConsumed:
  return []
```

`AppFeature.swift` — 替换 Task 2 的临时 case，放在 `.terminalEvent(.worktreeProjectionChanged…)` arm 之后：

```swift
case .terminalEvent(.worktreeTabsChanged(let worktreeID, let summary)):
  guard state.repositories.sidebarItems[id: worktreeID] != nil else { return .none }
  return .send(
    .repositories(
      .sidebarItems(
        .element(id: worktreeID, action: .tabsSnapshotChanged(summary))
      )
    )
  )
```

- [ ] **Step 4: 跑测试确认通过**（`SidebarItemFeatureTests` 全绿）
- [ ] **Step 5: `make build-app` 通过后提交**

```bash
git add supacode/Features/Repositories/Reducer/SidebarItemFeature.swift supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift supacode/Features/App/Reducer/AppFeature.swift supacodeTests/SidebarItemFeatureTests.swift
git commit -m "Mirror tab-strip snapshots into sidebar row state"
```

---

### Task 4: `RepositoriesFeature.sidebarTabRowSelected` 动作

**Files:**
- Modify: `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`（Action 枚举、handler 放 `.alert(.presented(.viewTerminalTab…))` :4006 附近）
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift`（`RepositoriesFeature.Action.cacheInvalidations` :381-513 的空集 bucket）
- Test: `supacodeTests/RepositoriesFeatureTests.swift`

**Interfaces:**
- Consumes: 既有 `.selectWorktree(_:focusTerminal:)`、`.delegate(.selectTerminalTab(_:tabId:))`（AppFeature :514 已把后者路由到 `terminalClient.send(.selectTab)`）
- Produces: `RepositoriesFeature.Action.sidebarTabRowSelected(Worktree.ID, tabID: TerminalTabID)` — 视图子行点击的唯一入口

- [ ] **Step 1: 写失败测试**（追加到 `RepositoriesFeatureTests`，仿 :2957 `viewTerminalTabSelectsWorktreeAndDelegatesTabSelection`；`makeWorktree` / `makeRepository` / `makeState` 是该文件既有 helper）

```swift
@Test(.dependencies) func sidebarTabRowSelectionSelectsWorktreeAndDelegates() async {
  let repoRoot = "/tmp/\(UUID().uuidString)-repo"
  let worktree = makeWorktree(id: "\(repoRoot)/feature", name: "feature", repoRoot: repoRoot)
  let repository = makeRepository(id: repoRoot, worktrees: [worktree])
  let tabId = TerminalTabID()
  var state = makeState(repositories: [repository])
  state.reconcileSidebarForTesting()
  let store = TestStore(initialState: state) {
    RepositoriesFeature()
  }
  store.exhaustivity = .off

  await store.send(.sidebarTabRowSelected(worktree.id, tabID: tabId))
  await store.receive(\.selectWorktree)
  await store.receive(\.delegate.selectTerminalTab)
}
```

- [ ] **Step 2: 跑测试确认失败**（`<SuiteName>` = `RepositoriesFeatureTests`，可加 `/sidebarTabRowSelectionSelectsWorktreeAndDelegates` 只跑单测；Expected: 编译错误 no member `sidebarTabRowSelected`）

- [ ] **Step 3: 实现**

Action 枚举（放在 `selectWorktree` case 附近）：

```swift
/// A per-tab sub-row in the sidebar was clicked: select the worktree, then
/// route the tab selection through the existing delegate → TerminalClient path.
case sidebarTabRowSelected(Worktree.ID, tabID: TerminalTabID)
```

handler（`.alert(.presented(.viewTerminalTab…))` arm 旁）：

```swift
case .sidebarTabRowSelected(let worktreeID, let tabID):
  return .merge(
    .send(.selectWorktree(worktreeID, focusTerminal: true)),
    .send(.delegate(.selectTerminalTab(worktreeID, tabId: tabID)))
  )
```

`SidebarStructure.swift` — `RepositoriesFeature.Action.cacheInvalidations` 最后的 `return []` bucket 里加 `.sidebarTabRowSelected,`（它是纯 effect 发射器；下游 `.selectWorktree` 自带 `.selectedWorktreeSlice`）。

- [ ] **Step 4: 跑测试确认通过**
- [ ] **Step 5: `make build-app` 通过后提交**

```bash
git add supacode/Features/Repositories/Reducer/RepositoriesFeature.swift supacode/Features/Repositories/BusinessLogic/SidebarStructure.swift supacodeTests/RepositoriesFeatureTests.swift
git commit -m "Add sidebarTabRowSelected action routing to tab selection"
```

---

### Task 5: 设置开关 `sidebarShowsSessionTitles` + View 菜单入口

**Files:**
- Modify: `supacode/Features/Repositories/BusinessLogic/SidebarPersistenceKey.swift`（:158-176 的 `SharedReaderKey` extension）
- Modify: `supacode/Commands/SidebarCommands.swift`（@Shared 声明 :11-19、菜单 Section :121-128）

**Interfaces:**
- Produces: `@Shared(.sidebarShowsSessionTitles)`（Bool，默认 `true`）— Task 6/7 的视图读取它

- [ ] **Step 1: 实现**（纯配置 + 菜单，无 reducer 逻辑，此任务无独立测试）

`SidebarPersistenceKey.swift`（`sidebarGroupActiveRows` 之后）：

```swift
/// "Show Session Titles" view-menu toggle. When on, a worktree row's title
/// shows the selected terminal tab's title (branch name moves to the
/// subtitle) and multi-tab rows can expand into per-tab sub-rows. Off
/// restores the branch-name-first rows exactly.
static var sidebarShowsSessionTitles: Self {
  Self[.appStorage("sidebarShowsSessionTitles"), default: true]
}
```

`SidebarCommands.swift`：声明区加

```swift
@Shared(.sidebarShowsSessionTitles) private var showsSessionTitles: Bool
```

菜单最后一个 Section 里（`Toggle("Nest Worktrees by Branch"…)` 旁）加

```swift
Toggle("Show Session Titles", isOn: Binding($showsSessionTitles))
```

- [ ] **Step 2: `make build-app` 通过后提交**

```bash
git add supacode/Features/Repositories/BusinessLogic/SidebarPersistenceKey.swift supacode/Commands/SidebarCommands.swift
git commit -m "Add Show Session Titles sidebar toggle"
```

---

### Task 6: 行标题解析（`ResolvedRowDisplay` 支持 sessionTitle）

**Files:**
- Modify: `supacode/Features/Repositories/Views/SidebarItemView.swift`（`ResolvedRowDisplay` :89-167、`SidebarItemView.body` :39-51）
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift`（`SidebarItemContainer` :442-472、`SidebarItemBody` :474-507 传参）
- Test: `supacodeTests/ResolvedRowDisplayTests.swift`（已存在，追加）

**Interfaces:**
- Consumes: Task 3 的 `store.selectedTabTitle`、Task 5 的 `@Shared(.sidebarShowsSessionTitles)`
- Produces: `ResolvedRowDisplay.init` 新参数 `sessionTitle: String? = nil`。解析规则（仅 `.gitWorktree`；`.folder` 行为不变）：
  - `name` = customTitle（trim 后非空）?? sessionTitle ?? branchName
  - `sessionTitle != nil` 时副标题固定显示分支：普通区 `.plain(branchName)`，高亮区 trail = branchName；且**跳过** hide-on-match 折叠（副标题是唯一的分支线索）
  - `sessionTitle == nil`（开关关 / 无 tab / 空标题）时一切与现状完全一致

- [ ] **Step 1: 写失败测试**（追加到 `ResolvedRowDisplayTests`；参数用既有测试同款调用形式，`kind: .gitWorktree`）

```swift
@Test func sessionTitleTakesOverAndBranchMovesToSubtitle() {
  let resolved = ResolvedRowDisplay(
    kind: .gitWorktree,
    branchName: "feature/login",
    worktreeName: "login",
    isMainWorktree: false,
    isPinned: false,
    hideSubtitle: false,
    hideSubtitleOnMatch: true,
    sessionTitle: "✳ Claude Code"
  )
  #expect(resolved.name == "✳ Claude Code")
  #expect(resolved.subtitle == .plain("feature/login"))
}

@Test func customTitleStillBeatsSessionTitle() {
  let resolved = ResolvedRowDisplay(
    kind: .gitWorktree,
    branchName: "main",
    worktreeName: nil,
    isMainWorktree: true,
    isPinned: false,
    hideSubtitle: false,
    hideSubtitleOnMatch: false,
    customTitle: "My Repo",
    sessionTitle: "✳ Claude Code"
  )
  #expect(resolved.name == "My Repo")
  #expect(resolved.subtitle == .plain("main"))
}

@Test func sessionTitleHighlightSubtitleTrailsBranch() {
  let resolved = ResolvedRowDisplay(
    kind: .gitWorktree,
    branchName: "main",
    worktreeName: nil,
    isMainWorktree: true,
    isPinned: false,
    hideSubtitle: false,
    hideSubtitleOnMatch: false,
    highlightSubtitle: SidebarHighlightRepoTag(repoName: "supacode", repoColor: nil, hostInfo: nil),
    sessionTitle: "✳ Claude Code"
  )
  #expect(resolved.name == "✳ Claude Code")
  #expect(
    resolved.subtitle
      == .highlight(repo: "supacode", repoColor: nil, trail: "main", hostInfo: nil)
  )
}

@Test func nilSessionTitleKeepsLegacyBehavior() {
  let resolved = ResolvedRowDisplay(
    kind: .gitWorktree,
    branchName: "feature/login",
    worktreeName: "login",
    isMainWorktree: false,
    isPinned: false,
    hideSubtitle: false,
    hideSubtitleOnMatch: true,
    sessionTitle: nil
  )
  #expect(resolved.name == "feature/login")
  // hide-on-match still collapses: worktree name matches branch last component.
  #expect(resolved.subtitle == .none)
}
```

- [ ] **Step 2: 跑测试确认失败**（`<SuiteName>` = `ResolvedRowDisplayTests`；Expected: 编译错误 extra argument `sessionTitle`）

- [ ] **Step 3: 实现**

`ResolvedRowDisplay.init` 签名加 `sessionTitle: String? = nil`（放 `customTitle` 参数后）。init 体改动（folder 分支保持原样，git 分支）：

```swift
let resolvedWorktreeName = worktreeName ?? "Default"
let effectiveWorktreeName = resolvedWorktreeName.isEmpty ? branchName : resolvedWorktreeName
self.name = resolvedCustom ?? sessionTitle ?? branchName

let branchLastComponent = branchName.split(separator: "/").last.map(String.init) ?? branchName
let isMatch = effectiveWorktreeName == branchLastComponent
// Session mode pins the branch into the subtitle (the title no longer carries
// it), so the hide-on-match collapse only applies to the legacy layout.
let shouldHideOnMatch = hideSubtitleOnMatch && !hasCustomTitle && isMatch && sessionTitle == nil

if let highlightSubtitle {
  let trail: String?
  if sessionTitle != nil {
    trail = branchName
  } else if shouldHideOnMatch {
    trail = nil
  } else if isMainWorktree {
    trail = "Default"
  } else if let worktreeName, !worktreeName.isEmpty {
    trail = worktreeName
  } else {
    trail = nil
  }
  self.subtitle = .highlight(
    repo: highlightSubtitle.repoName,
    repoColor: highlightSubtitle.repoColor,
    trail: trail,
    hostInfo: highlightSubtitle.hostInfo
  )
  return
}

if hideSubtitle || shouldHideOnMatch {
  self.subtitle = .none
} else if sessionTitle != nil {
  self.subtitle = .plain(branchName)
} else {
  self.subtitle = .plain(effectiveWorktreeName)
}
```

注意：`hideSubtitle`（sole-main slot 收紧）优先级维持——session 模式下 sole-main 行也不显示副标题，与现有紧凑规则一致。

`SidebarItemView`：加 `let showsSessionTitles: Bool` 存储属性（`hideSubtitleOnMatch` 旁），body 里：

```swift
let resolved = ResolvedRowDisplay(
  kind: store.kind,
  branchName: displayNameOverride ?? store.branchName,
  worktreeName: store.sidebarDisplayName,
  isMainWorktree: store.isMainWorktree,
  isPinned: store.isPinned,
  hideSubtitle: hideSubtitle,
  hideSubtitleOnMatch: hideSubtitleOnMatch,
  highlightSubtitle: highlightSubtitle,
  customTitle: store.customTitle,
  customTint: store.customTint,
  sessionTitle: showsSessionTitles && store.kind == .gitWorktree ? store.selectedTabTitle : nil
)
```

（`sessionTitle` 参数在 init 里排 `customTint` 后即可，与调用处一致。）

`SidebarItemsView.swift`：`SidebarItemContainer` 加

```swift
@Shared(.sidebarShowsSessionTitles) private var showsSessionTitles: Bool
```

并把 `showsSessionTitles` 经 `SidebarItemBody`（新增 `let showsSessionTitles: Bool`）传入 `SidebarItemView(showsSessionTitles:)`。

- [ ] **Step 4: 跑测试确认通过**（`ResolvedRowDisplayTests` 全绿）
- [ ] **Step 5: `make build-app` 通过后提交**

```bash
git add supacode/Features/Repositories/Views/SidebarItemView.swift supacode/Features/Repositories/Views/SidebarItemsView.swift supacodeTests/ResolvedRowDisplayTests.swift
git commit -m "Show selected session tab title as the sidebar row title"
```

---

### Task 7: 展开控件 + tab 子行渲染 + 手动验证

**Files:**
- Modify: `supacode/Features/Repositories/Views/SidebarItemView.swift`（`TrailingView` :498-563）
- Modify: `supacode/Features/Repositories/Views/SidebarItemsView.swift`（`SidebarItemRow` :408-440，文件尾部新增子行视图）

**Interfaces:**
- Consumes: Task 3 的 `isTabListExpanded` / `tabsSummary` / `.tabListExpansionToggled`；Task 4 的 `.sidebarTabRowSelected`；Task 5 的开关
- Produces: 展开控件（tab 计数 + chevron，Button 带 tooltip）；`SidebarTabSubRow`（缩进 Button 行，选中 tab 加粗 + 选中 accessibility trait）

- [ ] **Step 1: TrailingView 加展开控件**

`TrailingView` 加存储属性 `let showsSessionTitles: Bool`，`SidebarItemView.body` 的调用处改为：

```swift
TrailingView(
  store: store,
  shortcutHint: shortcutHint,
  showsPullRequestInfo: showsPullRequestInfo,
  showsSessionTitles: showsSessionTitles
)
```

`TrailingView.body` 的 `ZStack` 外包一层 `HStack(spacing: 6)`，在 ZStack 之后追加：

```swift
if showsSessionTitles, store.kind == .gitWorktree, store.tabsSummary.tabs.count > 1 {
  TabListExpander(
    count: store.tabsSummary.tabs.count,
    isExpanded: store.isTabListExpanded
  ) {
    store.send(.tabListExpansionToggled)
  }
}
```

新增（`TrailingView` 下方）：

```swift
private struct TabListExpander: View, Equatable {
  let count: Int
  let isExpanded: Bool
  let toggle: () -> Void

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.count == rhs.count && lhs.isExpanded == rhs.isExpanded
  }

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 2) {
        Text("\(count)")
          .font(.caption)
          .monospacedDigit()
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .animation(.easeInOut(duration: 0.15), value: isExpanded)
      }
      .foregroundStyle(.secondary)
      .contentShape(.interaction, .rect)
    }
    .buttonStyle(.plain)
    .help(isExpanded ? "Collapse session tabs" : "Expand session tabs (\(count))")
    .accessibilityLabel("\(count) session tabs, \(isExpanded ? "expanded" : "collapsed")")
  }
}
```

- [ ] **Step 2: SidebarItemRow 渲染子行**

`SidebarItemRow.body` 改为（`SidebarItemContainer` 调用保持原参数）：

```swift
var body: some View {
  if let itemStore = store.scope(state: \.sidebarItems[id: rowID], action: \.sidebarItems[id: rowID]) {
    SidebarItemContainer(
      store: itemStore,
      parentStore: store,
      terminalManager: terminalManager,
      selectedWorktreeIDs: selectedWorktreeIDs,
      isRepositoryRemoving: isRepositoryRemoving,
      hideSubtitle: hideSubtitle,
      moveMode: moveMode,
      shortcutHint: shortcutHint,
      displayNameOverride: displayNameOverride,
      nestDepth: nestDepth,
      highlightSubtitle: highlightSubtitle
    )
    SidebarTabSubRows(store: itemStore, parentStore: store, nestDepth: nestDepth)
  }
}
```

文件尾部新增：

```swift
/// Per-tab sub-rows under an expanded worktree row. Reads only the leaf's own
/// scoped store, so a title tick on this worktree invalidates just these rows.
/// Sub-rows are plain Buttons (mirroring `SidebarPathGroupHeaderRow`), not
/// List-selection tags: the parent row keeps the selection highlight and the
/// click routes through `sidebarTabRowSelected`.
private struct SidebarTabSubRows: View {
  let store: StoreOf<SidebarItemFeature>
  @Bindable var parentStore: StoreOf<RepositoriesFeature>
  let nestDepth: Int
  @Shared(.sidebarShowsSessionTitles) private var showsSessionTitles: Bool

  var body: some View {
    if showsSessionTitles, store.state.isTabListExpanded {
      let summary = store.state.tabsSummary
      let rowID = store.state.id
      ForEach(summary.tabs) { tab in
        SidebarTabSubRow(
          tab: tab,
          isSelected: tab.id == summary.selectedTabID,
          nestDepth: nestDepth
        ) {
          parentStore.send(.sidebarTabRowSelected(rowID, tabID: tab.id))
        }
      }
    }
  }
}

private struct SidebarTabSubRow: View {
  let tab: WorktreeTabsSummary.Tab
  let isSelected: Bool
  let nestDepth: Int
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 6) {
        Image(systemName: tab.icon ?? "terminal")
          .imageScale(.small)
          .foregroundStyle(tab.tint.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
          .accessibilityHidden(true)
        Text(tab.title)
          .font(.callout)
          .fontWeight(isSelected ? .semibold : .regular)
          .lineLimit(1)
          .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        Spacer(minLength: 0)
      }
      .contentShape(.interaction, .rect)
    }
    .buttonStyle(.plain)
    .listRowInsets(.leading, CGFloat(nestDepth) * SidebarNestLayout.indentStep + 22)
    .listRowInsets(.vertical, 4)
    .moveDisabled(true)
    .help("Switch to \(tab.title)")
    .accessibilityLabel("Session tab \(tab.title)\(isSelected ? ", selected" : "")")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
```

- [ ] **Step 3: `make build-app` 编译通过**
- [ ] **Step 4: 手动验证（`make run-app`）**

1. 打开一个 worktree，开 3 个 tab（其中一个跑 `claude`）——侧边栏该行主标题应随选中 tab 变化（如 "✳ Claude Code"），副标题显示分支名。
2. 行尾出现 `3 ›` 控件；点击展开出 3 个缩进子行，当前 tab 加粗；点另一个子行 → 主视图切到该 tab，行主标题同步更新。
3. 关掉 tab 到只剩 1 个 → chevron 消失、子行收起。
4. View 菜单关闭 "Show Session Titles" → 一切恢复原状（分支名主标题、无 chevron）。
5. Pinned/Active 高亮区的行同样生效（副标题 `repo · 分支名`）。
6. 给 worktree 设置自定义标题（Customize Appearance）→ 自定义标题仍然优先。

- [ ] **Step 5: 全量测试 + 提交**

```bash
make test   # 全绿（工作区已有的未提交 dedupe 测试也应通过）
git add supacode/Features/Repositories/Views/SidebarItemView.swift supacode/Features/Repositories/Views/SidebarItemsView.swift
git commit -m "Render expandable session-tab sub-rows in the sidebar"
```

---

## 与设计文档的两处实现级偏差（已择优）

1. **子行不参与 `List` selection**（spec 原写 `SidebarSelection.worktreeTab` case）：改用 Button 行，完全复刻既有 `SidebarPathGroupHeaderRow` 模式并复用现成 `delegate(.selectTerminalTab)` 通路。父行保持选中高亮，不污染多选/持久化选择机制。
2. **tab 子行不进 `sidebarStructure`**（spec 原写在 `computeSidebarStructure` 生成子行）：tabs 快照走独立事件（`worktreeTabsChanged`，`cacheInvalidations = []`），视图从 per-leaf scoped store 渲染。shell 标题每秒级刷新的风暴因此完全不触发全表结构重算，忠于仓库的侧边栏性能铁律。

