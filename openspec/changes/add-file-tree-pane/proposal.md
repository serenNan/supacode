## Why

Supacode 目前没有任何方式在应用内浏览当前会话所在 worktree 的文件夹结构——想看某个文件、确认 agent 生成了哪些文件，必须切到 Finder、终端 `ls` 或外部编辑器。作为以 worktree 为核心工作单元的工具，缺少文件树浏览是明显的能力空白，也让已有的内置文件查看器（diff sheet）少了一个自然的入口。

## What Changes

- 右侧 Inspector 新增「Files」pane，与现有 Git/PR、Notifications、History 面板并列，展示当前选中 worktree 的完整文件夹树。
- 文件树行为：
  - 目录可展开/折叠，懒加载子目录内容（大仓库不全量扫描）
  - 目录优先、按名称排序；显示文件/文件夹系统图标
  - 默认隐藏 `.git` 目录；遵循 `.gitignore`（被忽略的条目默认不显示）
  - worktree 文件变化时自动刷新（跟随现有 `WorktreeInfoWatcherClient` 的 `filesChanged` 事件），并保持已展开状态与选中项
- 点击/回车打开文件：复用现有内置文件查看 sheet 在 Supacode 内预览文件内容（如现有查看器仅支持 diff 输入，扩展其支持普通工作区文件的只读预览）。
- 工具栏新增 Files 切换按钮（仿现有 inspector pane 按钮），菜单命令与快捷键跟随现有 inspector pane 模式，按钮带 tooltip 与快捷键说明。
- 空态/错误态：worktree 路径不可读时显示错误提示；空目录显示空态。

非目标（后续迭代）：文件操作（新建/重命名/删除/移动）、拖拽、右键菜单（外部编辑器打开、Reveal in Finder、拷贝路径）、模糊搜索快速打开（未来可复用 CommandPalette）、二进制/图片专用预览。

## Capabilities

### New Capabilities

- `file-tree-pane`: Inspector 中的 worktree 文件树面板——树的内容与排序、懒加载与展开状态、.gitignore/.git 过滤、自动刷新、点击文件的内置预览行为、切换入口（工具栏/菜单/快捷键）、空态/错误态。

### Modified Capabilities

（无——现有能力尚无对应 spec，本变更不修改现有面板的行为；文件查看器如需扩展为普通文件预览，属于实现层扩展，其对外行为在 `file-tree-pane` spec 中约束。）

## Impact

- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`：inspector pane 枚举新增 `files` case；新增文件树状态（根节点、展开集合、选中项）与加载/展开/刷新 action。
- `supacode/Features/Repositories/Views/`：新建文件树视图文件；inspector 容器 switch 分发新 pane；工具栏与 `WorktreeDetailView.swift` 新增切换按钮。
- `supacode/Commands/SidebarCommands.swift`：新增菜单命令与快捷键。
- `supacode/Clients/`：新增（或扩展现有）文件系统枚举 client：列目录、过滤 .gitignore（可复用 `git check-ignore` / `git ls-files` 封装）。
- 文件查看 sheet（`WorktreeFileDiffSheetView` 一系）：扩展支持非 diff 的普通文件预览入口。
- 测试：`supacodeTests/` 新增 reducer 测试（展开/折叠、刷新保持状态、打开文件）与目录枚举/过滤逻辑测试（项目规则：reducer 逻辑变更必须加测试）。
- 无新第三方依赖；只读文件系统操作，无数据迁移。
