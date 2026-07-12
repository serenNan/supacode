## 1. 文件引用解析器（TDD）

- [x] 1.1 写 `TerminalFileReference.resolve` 单元测试（红）：相对/绝对路径、`:line`、`:line:col`、原串精确命中优先、pwd 缺失退化 worktree 根、`file://` URI、http scheme 拒绝、worktree 外前缀伪匹配拒绝、不存在文件拒绝
- [x] 1.2 实现 `TerminalFileReference`（纯函数、`fileExists` 注入），测试转绿

## 2. Ghostty open-url 拦截与事件管线

- [x] 2.1 `GhosttySurfaceBridge` 加 `onOpenURL: ((String) -> Bool)?`，`GHOSTTY_ACTION_OPEN_URL` 分支先问回调、未处理走现有 `NSWorkspace` 路径
- [x] 2.2 `WorktreeTerminalState` 接线 `onOpenURL`（守 `isLiveSurface`、仅本地 worktree、pwd 取 `bridge.state.pwd`），命中调 `onFileReferenceClicked?(path, line)`
- [x] 2.3 `TerminalClient.Event` 加 `fileReferenceClicked(worktreeID:path:line:)`，`WorktreeTerminalManager` 接线 emit

## 3. Reducer 编排（TDD）

- [x] 3.1 写 `RepositoriesFeature` TestStore 测试（红）：`openTerminalFileReference` 打开 History pane、gitHistory 对账初始化、续发 `fileTapped`、`presentedDiff.targetLine` 落位；非选中 worktree 丢弃；pane 已打开时不重复加载
- [x] 3.2 实现主 switch 的 `openTerminalFileReference` case + `fileTapped` 扩 `line:` + `PresentedFileDiff.targetLine`，更新两个视图调用点与受影响测试，转绿
- [x] 3.3 `AppFeature.terminalEvent(.fileReferenceClicked)` 转发到 `.repositories(.openTerminalFileReference)`（含测试）

## 4. Diff sheet 行号定位

- [x] 4.1 `WorktreeFileDiffSheetView` 用 `ScrollViewReader` 在 diff 装载后滚动到首个 `newNumber >= targetLine` 的行；目标缺失/超出渲染上限不滚动

## 5. 媒体/二进制文件走系统默认打开（追加需求）

- [x] 5.1 `TerminalFileReference.prefersSystemOpen`（扩展名大小写不敏感：图片/PDF/音视频/压缩包/office）+ 参数化单测
- [x] 5.2 `handleOpenURL` 分流：prefersSystemOpen 用解析出的绝对路径 `NSWorkspace.open`（修复相对路径回退打不开的问题），其余进 diff viewer

## 6. 验证与收尾

- [x] 6.1 构建 + 全部测试通过（worktree 内用 `xcodebuild -scheme supacode-tests` 直连替代 make；swiftlint/swift-format 对改动文件零新增违规）
- [ ] 6.2 手动验证（留待用户）：Cmd+click `path:line` 打开 diff sheet 并定位行；图片走系统默认打开；http 链接仍走浏览器
- [ ] 6.3 提交（留待用户指示；分支 `worktree-terminal-file-link`）
