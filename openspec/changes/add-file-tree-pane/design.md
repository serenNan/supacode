## Context

Supacode 的右侧 Inspector 已有三个 pane（Git/PR、Notifications、History），通过 SwiftUI 原生 `.inspector(isPresented:)` 挂载在 `WorktreeDetailView`（`WorktreeDetailView.swift:100-125`），由 `WorktreeStatusInspectorContainer` 按 `WorktreeInspectorPane` 枚举分发子视图（`WorktreeStatusInspector.swift:20-37`）。切换入口三条路径（工具栏按钮、菜单命令、快捷键）都汇到同一个 `toggleInspectorPane` action。History pane 是最近合入的同构先例：子 State/Action + reducer 放在 `RepositoriesFeature+GitHistory.swift` extension 中，采用"惰性加载 + default 分支对账"模式（pane 可见且选中 worktree 变化时自动重载/清空）。

现状盘点（探索结论）：
- **没有**通用的文件系统枚举 client、递归目录 watcher、gitignore 解析器。
- `WorktreeInfoWatcherClient` 只 kqueue 监听 `.git/HEAD`，其 `filesChanged` 事件反映的是 git 状态变化，不能感知任意工作区文件增删。
- 文件查看 sheet（`WorktreeFileDiffSheetView`）输入是 `GitFileDiff`（hunk/line 结构），**不支持**普通文件内容渲染；但 sheet 的呈现模式（`PresentedFileDiff` + `.sheet`）、"在编辑器打开"按钮（`WorktreeOpener.openFile`）、`maxRenderedLines` 截断和二进制空态处理都可借鉴。
- worktree 根路径：本地磁盘操作必须用 `Worktree.localWorkingDirectory: URL?`（远程 worktree 为 `nil`），不能用 `workingDirectory`（远程是合成 `file://`）。

## Goals / Non-Goals

**Goals:**
- Inspector 新增 Files pane：当前 worktree 的文件树，目录优先排序、遵循 gitignore、隐藏 `.git`。
- 工作区文件变化时自动刷新，保持展开集合与选中项。
- 激活文件时用内置查看器 sheet 只读预览文本内容，附"在编辑器打开"逃生口。
- 工具栏/菜单/快捷键三入口，与现有 pane 模式完全一致。

**Non-Goals:**
- 远程（SSH）worktree 的文件树（v1 显示"仅支持本地 worktree"占位态）。
- 文件操作（新建/重命名/删除/移动）、拖拽、右键菜单。
- 语法高亮、图片/二进制专用预览（二进制显示不可预览空态）。
- 显示空目录（见决策 2 的取舍）。
- 模糊搜索快速打开（未来可作为 `CommandPaletteItem.Kind` 接入 CommandPalette）。

## Decisions

### 1. 接入方式：复制 History pane 的成熟模式

`WorktreeInspectorPane` 加 `.files` case；新建 `RepositoriesFeature+FileTree.swift`，定义 `FileTreeState` / `FileTreeAction` / `fileTreeReducer`，主 reducer body 组合；容器 switch、工具栏按钮（`WorktreeDetailView.swift:740` 一组）、菜单命令（`SidebarCommands.swift:109` 一组）、`AppShortcuts` 快捷键各加一项。菜单动作遵循项目的 `FocusedAction` 规则。

**为什么**：三个 pane 已验证此模式；`+GitHistory.swift` 的"pane 可见 + worktree 变化 → 对账重载"的 default 分支直接照搬，避免自造生命周期。

### 2. 树数据来源：单次 `git ls-files -co --exclude-standard`，内存建树

在 `GitClientDependency` 上新增一个 closure（如 `listFiles(directory:) -> [String]`），封装 `git ls-files -co --exclude-standard`（已跟踪 + 未跟踪未忽略，一次拿到全部相对路径），reducer 侧从扁平路径列表构建树（目录由路径前缀推导），UI 按展开集合惰性渲染。

**为什么，及替代方案**：
- 备选 A（每次展开目录时 `FileManager.contentsOfDirectory` + `git check-ignore --stdin` 批量过滤）：真·懒加载，但每次展开都要起 git 进程，刷新时要逐个重扫已加载目录，状态机复杂得多。
- 备选 B（自己解析 `.gitignore`）：忽略语义有嵌套 ignore、全局 excludes、否定模式等大量边角，自解析必然与 git 行为漂移。
- 选定方案一次 git 调用拿全量路径（即使 10 万文件也只是字符串列表），忽略语义与 git 完全一致，刷新 = 重跑同一命令 + diff 替换，最符合"行数砍半"。`.git` 目录天然不在 `ls-files` 输出中，无需额外过滤。
- 代价：**空目录不会显示**（`ls-files` 只列文件）。可接受——对"快速打开某个文件"的目标无损。
- 树构建是纯函数，放独立类型（如 `enum FileTreeBuilder` 的 static 方法，遵循"避免顶层自由函数"规则），单测友好。

### 3. 文件变化监听：新建 FSEvents watcher，仅 pane 可见时激活

现有 `WorktreeInfoWatcherClient` 的 kqueue/`.git/HEAD` 模式感知不到 agent 写入的普通文件。新增一个小 client（如 `FileTreeWatcherClient`：`observe(root: URL) -> AsyncStream<Void>`），用 `FSEventStream` 递归监听 worktree 根目录，事件去抖（~500ms，注入 clock 以便 TestClock 驱动测试）后触发重跑 `listFiles`。仅在 Files pane 可见且为本地 worktree 时订阅，pane 关闭或切换 worktree 时取消。

**为什么**：FSEvents 是 macOS 上递归目录监听的标准答案（kqueue 需要每目录一个 fd，不可扩展）；按可见性生命周期订阅避免常驻开销。备选"复用 filesChanged 事件 + 手动刷新按钮"感知不到 agent 产出的新文件，违背本功能的核心场景。

### 4. 刷新保持视图状态：以相对路径为身份

`FileTreeState` 保存 `expandedPaths: Set<String>`（相对路径）与 `selectedPath: String?`。刷新时重建树后：展开集合与选中项按路径求交集，消失的路径自动剔除（覆盖"选中的文件被删除"场景）。视图用 `List` + 递归 `DisclosureGroup`，展开状态绑定 reducer state（不用 `OutlineGroup` 内部状态，否则刷新即丢展开态）。

### 5. 文件预览：新的只读文本 sheet，不改造 diff sheet

新增 `WorktreeFilePreviewSheetView` + `PresentedFilePreview`（仿 `PresentedFileDiff` 的形状：路径、内容/错误），呈现走与 History pane 相同的 `.sheet` 模式。内容读取新增 client closure（如 `readFileContent(url:) -> String?`）：按大小上限（1 MB）与行数上限（沿用 diff sheet 的 4000 行截断策略）读取，探测到二进制（NUL 字节启发式）返回 nil → `ContentUnavailableView`。sheet 工具栏带"在编辑器打开"按钮，复用 `WorktreeOpener.openFile(at:defaultEditorID:)`。

**为什么**：`WorktreeFileDiffSheetView` 的渲染核心是 `GitFileDiff` 的 hunk/line 结构，把普通文件伪装成 diff（单个全加 hunk）语义扭曲且渲染成本更高；一个 monospaced 文本 + 行号的只读视图更简单。等宽字体用 `.monospaced()`，颜色全用系统色（项目 UX 规范）。

### 6. 远程 worktree 降级

`worktree.localWorkingDirectory == nil` 时，Files pane 显示 `ContentUnavailableView`（"文件树仅支持本地 worktree"），不发起任何加载。SSH 场景留待后续（`GitClientDependency.ssh` 可跑 `ls-files`，但 FSEvents 与文件读取都需要另一套远程通道，不值得塞进 v1）。

## Risks / Trade-offs

- [超大仓库 `ls-files` 输出巨大（>10 万行）] → 单次调用仍是毫秒级；建树在后台 effect 中做，UI 只渲染展开部分。若实测有压力，加路径数上限 + 提示。
- [FSEvents 在 agent 高频写入时事件风暴] → 500ms 去抖 + 刷新任务合并（新事件到达时取消未开始的旧刷新）。
- [空目录不显示，用户可能困惑] → 面板空态/文档说明"显示 git 可见的文件"；对目标场景（打开文件）无实际损失。
- [刷新与用户展开操作竞态（刷新结果覆盖刚展开的节点）] → 展开状态存于 `expandedPaths` 而非树节点内，重建树不影响展开集合。
- [大文件/二进制预览卡顿] → 读取前先 stat 大小，超限直接显示"文件过大"空态，不读入内存。

## Open Questions

（无——关键分叉已在提案阶段与用户确认：Inspector 文件树 + 内置查看器预览。）
