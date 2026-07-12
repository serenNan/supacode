## 1. 数据层：枚举与建树

- [ ] 1.1 `GitClientDependency` 新增 `listFiles(directory:)` closure，封装 `git ls-files -co --exclude-standard`，返回相对路径数组；补 `testValue` 与解析测试
- [ ] 1.2 新建 `FileTreeBuilder`（caseless enum + static 方法）：扁平相对路径列表 → 树结构（目录优先、名称本地化不区分大小写排序）；单测覆盖排序、嵌套目录推导、空列表
- [ ] 1.3 新增文件内容读取 client closure `readFileContent(url:)`：stat 大小上限 1 MB、4000 行截断、NUL 字节二进制探测返回 nil；单测覆盖三种边界

## 2. 文件系统监听

- [ ] 2.1 新建 `FileTreeWatcherClient`（`observe(root:) -> AsyncStream<Void>`），FSEventStream 递归监听 + 注入 clock 的 500ms 去抖；`testValue` 用可控 continuation
- [ ] 2.2 Reducer 侧订阅生命周期：仅 Files pane 可见且本地 worktree 时订阅，pane 关闭/切 worktree 时取消（`TestClock` 驱动去抖测试）

## 3. Reducer：FileTree 子功能

- [ ] 3.1 新建 `RepositoriesFeature+FileTree.swift`：`FileTreeState`（worktreeID、树、`expandedPaths`、`selectedPath`、`presentedPreview`、加载/错误态）与 `FileTreeAction`；`WorktreeInspectorPane` 加 `.files` case
- [ ] 3.2 实现 `fileTreeReducer`：加载/重载、展开折叠、激活文件（目录→切换展开，文件→加载预览）、预览 dismiss；default 分支照搬 GitHistory 的"pane 可见 + worktree 变化 → 对账重载"模式
- [ ] 3.3 刷新保持状态：重建树后 `expandedPaths`/`selectedPath` 按现存路径求交集；测试覆盖"新文件出现保持展开"与"选中文件被删除后清除选中"
- [ ] 3.4 新建 `RepositoriesFeatureFileTreeTests.swift`（TestStore + swift-testing），覆盖 spec 全部场景对应的 reducer 路径

## 4. 视图：Files pane 与预览 sheet

- [ ] 4.1 新建 `WorktreeFileTreeInspectorView`：`List` + 递归 `DisclosureGroup`，展开状态绑定 reducer state；文件/文件夹系统图标、Dynamic Type、系统色
- [ ] 4.2 空态/错误态/加载态/远程 worktree 占位（`ContentUnavailableView`）
- [ ] 4.3 新建 `WorktreeFilePreviewSheetView` + `PresentedFilePreview`：monospaced 只读文本、行号、二进制/超大文件空态；工具栏"在编辑器打开"按钮复用 `WorktreeOpener.openFile`
- [ ] 4.4 `WorktreeStatusInspector` 容器 switch 加 `.files` 分支

## 5. 入口：工具栏、菜单、快捷键

- [ ] 5.1 `WorktreeDetailView` 工具栏组加 Files 切换按钮（tooltip 含用途与快捷键）
- [ ] 5.2 `SidebarCommands` 加 "Toggle Files Inspector" 菜单命令；`AppShortcuts` 加快捷键；焦点动作按 `FocusedAction` 规则注册
- [ ] 5.3 toggle 行为测试：再次触发关闭、与其他 pane 互斥切换

## 6. 收尾

- [ ] 6.1 `make build-app` 通过；跑 supacodeTests 相关测试全绿
- [ ] 6.2 手动验证清单：打开面板看到文件树；`.git`/gitignored 不显示；终端 `touch` 新文件后自动出现且展开态保持；点击文本文件弹预览；二进制文件显示空态；远程 worktree 显示占位；快捷键/菜单/工具栏三入口一致
